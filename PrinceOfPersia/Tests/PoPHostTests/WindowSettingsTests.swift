import Testing
import Foundation
@testable import PoPHost
import PoPCore

// Remembering the window size.
//
// The scale is the one setting in the project that cannot affect gameplay — Law 8 keeps it out of
// the simulation entirely — so these tests are about the *reading* rather than the value: a
// preference file is JSON in Application Support, people edit those by hand, and nothing they can
// put in it should do worse than open the window at the default size.

private func temporaryURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pop-window-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("window.json")
}

@Test func theScaleSurvivesARoundTrip() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    #expect(WindowSettings.save(scale: 5, to: url))
    #expect(WindowSettings.load(from: url)?.scale == 5)
}

@Test func aMissingFileMeansTheDefault() {
    #expect(WindowSettings.load(from: temporaryURL()) == nil)
}

@Test func aCorruptFileMeansTheDefault() throws {
    let url = temporaryURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try Data("{ not json".utf8).write(to: url)
    #expect(WindowSettings.load(from: url) == nil)

    // A scale outside the hard range is not a scale. `WindowScale.clamp` would turn 0 into the
    // default anyway, but a file that says 0 is a file somebody edited by hand, and refusing it
    // is more honest than silently rescuing it.
    for nonsense in ["{\"scale\": 0}", "{\"scale\": -3}", "{\"scale\": 99}"] {
        try Data(nonsense.utf8).write(to: url)
        #expect(WindowSettings.load(from: url) == nil, "\(nonsense) is not a scale")
    }
}

@Test func onlyTheHardRangeIsSaved() {
    let url = temporaryURL()
    #expect(!WindowSettings.save(scale: 0, to: url))
    #expect(!WindowSettings.save(scale: 9, to: url))
    #expect(WindowSettings.save(scale: 1, to: url))
    #expect(WindowSettings.save(scale: 8, to: url))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

// MARK: - Which scale a launch opens at

@Test func theDefaultIsUsedWhenNothingIsRemembered() {
    #expect(WindowSettings.startingScale(requested: nil, stored: nil) == WindowScale.standard)
}

@Test func whatThePlayerChoseBeatsTheDefault() {
    // A scale that fits whatever display this test runs on, so the assertion is about the
    // precedence rather than about the size of the screen.
    let fits = WindowScale.fitting.first ?? WindowScale.standard
    #expect(WindowSettings.startingScale(requested: nil, stored: WindowSettings(scale: fits)) == fits)
}

@Test func anExplicitScaleBeatsWhatWasRemembered() {
    // A scale given on the command line is an override for one launch: it is a diagnostic, in the
    // same family as `--level`, and it must not silently rewrite the player's menu choice.
    let wants = WindowScale.fitting.min() ?? WindowScale.standard
    let remembered = WindowScale.fitting.max() ?? WindowScale.standard
    #expect(WindowSettings.startingScale(
        requested: wants, stored: WindowSettings(scale: remembered)
    ) == wants)
}

@Test func aRememberedScaleIsClampedToTheDisplay() {
    // A scale remembered on a large display, read back on a laptop. A window taller than the
    // screen is a bug, so the largest that fits wins — and the file is left alone, because the
    // player may plug the other display back in.
    #expect(WindowSettings.startingScale(requested: nil, stored: WindowSettings(scale: 8))
        == WindowScale.fitted(8))
    #expect(WindowScale.fitted(8) <= (WindowScale.fitting.last ?? 8))
}

@Test func anExplicitScaleIsClampedToo() {
    #expect(WindowSettings.startingScale(requested: 99, stored: nil) == WindowScale.fitted(99))
    #expect(WindowSettings.startingScale(requested: 0, stored: nil) == WindowScale.standard)
}

@Test func theFlagIsParsedAndNothingElse() {
    // This only reads the flag. What an absent flag means is a question about the player's
    // settings, and answering it here is the mistake that made the scale unrememberable: it
    // erased the difference between asking for the default and asking for nothing.
    #expect(WindowScale.requestedScale(from: ["Prince", "--scale", "4"]) == 4)
    #expect(WindowScale.requestedScale(from: ["Prince"]) == nil)
    #expect(WindowScale.requestedScale(from: ["Prince", "--scale"]) == nil)
    #expect(WindowScale.requestedScale(from: ["Prince", "--scale", "big"]) == nil)
    // Unclamped: the clamp belongs to `startingScale`, and is applied once, there.
    #expect(WindowScale.requestedScale(from: ["Prince", "--scale", "99"]) == 99)
}
