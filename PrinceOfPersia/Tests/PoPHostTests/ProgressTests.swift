import Testing
import Foundation
@testable import PoPHost
import PoPCore

// The one thing this port remembers between runs.
//
// Neither the 1989 original nor PrinceJS saves anything — `Boot.js` hardcodes level 1 and there
// is no `localStorage`. Resuming where you left off is an addition, and these tests are mostly
// about it failing *safely*: a save file is the one file a player can corrupt by hand, and none of
// the ways they can do it should stop the game starting.

private func temporaryURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pop-progress-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("progress.json")
}

@Test func theLevelSurvivesARoundTrip() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    #expect(Progress.save(level: 7, to: url))
    #expect(Progress.load(from: url)?.level == 7)
}

@Test func aMissingFileMeansStartAtTheBeginning() {
    let url = temporaryURL()
    #expect(Progress.load(from: url) == nil)
}

@Test func aCorruptFileMeansStartAtTheBeginning() throws {
    // The file is JSON in Application Support. People edit those.
    let url = temporaryURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    try Data("{ not json".utf8).write(to: url)
    #expect(Progress.load(from: url) == nil)

    try Data("{\"level\": 99}".utf8).write(to: url)
    #expect(Progress.load(from: url) == nil, "a level that does not exist is not a level")

    try Data("{\"level\": 0}".utf8).write(to: url)
    #expect(Progress.load(from: url) == nil)
}

@Test func onlyShippedLevelsAreSaved() {
    let url = temporaryURL()
    #expect(!Progress.save(level: 0, to: url))
    #expect(!Progress.save(level: 15, to: url))
    #expect(Progress.save(level: 14, to: url))
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Test func clearingTheSaveForgetsIt() throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    Progress.save(level: 5, to: url)
    Progress.clear(at: url)
    #expect(Progress.load(from: url) == nil)
}

@Test func anExplicitLevelBeatsTheSave() {
    // `--level 3` means level 3, whatever the save says. This is what makes the diagnostics
    // usable — every screenshot and trace command in the README passes one.
    #expect(Progress.startingLevel(requested: 3) == 3)
    #expect(Progress.startingLevel(requested: 3, newGame: true) == 3)
    #expect(Progress.startingLevel(requested: 99) != 99, "but not one that does not exist")
}

@Test func aNewGameIgnoresTheSave() {
    // The one flag that has to win over the save, or a player who has reached level 12 can never
    // get back to the start.
    #expect(Progress.startingLevel(requested: nil, newGame: true) == 1)
}

@Test func bothFilesShareOneDirectory() {
    // Key bindings and progress sit together, which is what makes them findable — and what the
    // README tells the player to look for.
    #expect(KeyBindings.fileURL.deletingLastPathComponent() == AppSupport.directory)
    #expect(Progress.fileURL.deletingLastPathComponent() == AppSupport.directory)
    #expect(KeyBindings.fileURL.lastPathComponent == "keys.json")
    #expect(Progress.fileURL.lastPathComponent == "progress.json")
}
