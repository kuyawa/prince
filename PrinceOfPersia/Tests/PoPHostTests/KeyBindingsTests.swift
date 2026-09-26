import Testing
import Foundation
@testable import PoPHost
import PoPCore

// M9: keybindings.
//
// The decision itself is a pure function on `KeyBindings`, which is what makes it testable without
// a window or an event loop — the same split Law 6 asks for between the keyboard and the sim.

@Test func theStandardBindingsAreTheArrowKeysAndShift() {
    let keys = KeyBindings.standard
    #expect(keys.left == 123)
    #expect(keys.right == 124)
    #expect(keys.down == 125)
    #expect(keys.up == 126)
    #expect(keys.action == 56, "left shift, from kVK_Shift")
    #expect(keys.shiftIsAction)
}

@Test func theArrowKeysProduceTheExpectedIntents() {
    let keys = KeyBindings.standard
    #expect(keys.intents(pressed: [123], shiftHeld: false) == [.left])
    #expect(keys.intents(pressed: [124], shiftHeld: false) == [.right])
    #expect(keys.intents(pressed: [126], shiftHeld: false) == [.up])
    #expect(keys.intents(pressed: [125], shiftHeld: false) == [.down])
    #expect(keys.intents(pressed: [], shiftHeld: false) == [])
}

@Test func holdingTwoKeysProducesBothIntents() {
    // Left and up together is the standing jump, so this is not hypothetical.
    let keys = KeyBindings.standard
    #expect(keys.intents(pressed: [123, 126], shiftHeld: false) == [.left, .up])
}

@Test func shiftIsTheActionKeyEvenThoughItIsAModifier() {
    // Shift does not arrive as a key-down in a local monitor, so it cannot be read from the
    // pressed set — it comes from the modifier flags. Both routes are supported.
    let keys = KeyBindings.standard
    #expect(keys.intents(pressed: [], shiftHeld: true) == [.action])
    #expect(keys.intents(pressed: [56], shiftHeld: false) == [.action])

    // And it can be turned off, for a player who binds the action to a letter.
    var letters = KeyBindings.standard
    letters.action = 49          // space
    letters.shiftIsAction = false
    #expect(letters.intents(pressed: [], shiftHeld: true) == [])
    #expect(letters.intents(pressed: [49], shiftHeld: false) == [.action])
}

@Test func rebindingTheMovementKeysWorks() {
    // WASD, which is what most players will actually want.
    var wasd = KeyBindings.standard
    wasd.left = 0      // A
    wasd.right = 2     // D
    wasd.down = 1      // S
    wasd.up = 13       // W

    #expect(wasd.intents(pressed: [0], shiftHeld: false) == [.left])
    #expect(wasd.intents(pressed: [2], shiftHeld: false) == [.right])
    #expect(wasd.intents(pressed: [13], shiftHeld: false) == [.up])
    #expect(wasd.intents(pressed: [123], shiftHeld: false) == [], "the arrow no longer does anything")
}

@Test func theReservedKeysCoverEverythingThatIsBound() {
    // The monitor swallows these so AppKit does not beep. An unbindable-but-beeping arrow key is
    // the kind of thing nobody reports and everybody hears.
    var custom = KeyBindings.standard
    custom.up = 13
    #expect(custom.reservedKeyCodes.contains(13))
    #expect(custom.reservedKeyCodes.contains(123))
    #expect(custom.reservedKeyCodes.count == 5)
}

@Test func bindingsSurviveARoundTripThroughJSON() throws {
    var custom = KeyBindings.standard
    custom.right = 2
    custom.shiftIsAction = false

    let data = try JSONEncoder().encode(custom)
    let back = try JSONDecoder().decode(KeyBindings.self, from: data)
    #expect(back == custom)
}

@Test func aMissingOrBrokenFileFallsBackToTheDefaults() throws {
    // A game that refuses to start because a config file has a typo in it is worse than one
    // running with the defaults.
    let missing = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("no-such-keys-\(UUID().uuidString).json")
    #expect(KeyBindings.load(from: missing) == .standard)

    let broken = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("broken-keys-\(UUID().uuidString).json")
    try Data("{ not json at all".utf8).write(to: broken)
    #expect(KeyBindings.load(from: broken) == .standard)
    try? FileManager.default.removeItem(at: broken)
}

@Test func writingATemplateAndReadingItBackRoundTrips() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pop-keys-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("keys.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    #expect(KeyBindings.writeTemplateIfMissing(to: url), "it creates the directory too")
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(!KeyBindings.writeTemplateIfMissing(to: url), "and never overwrites")
    #expect(KeyBindings.load(from: url) == .standard)

    var rebound = KeyBindings.standard
    rebound.up = 13
    #expect(KeyBindings.write(rebound, to: url))
    #expect(KeyBindings.load(from: url) == rebound)
}
