import Testing
import AppKit
@testable import PoPHost

// The app-lifecycle policy that lives in PoPHost rather than in a scene.

@MainActor
@Test func closingTheLastWindowQuitsTheApp() {
    // AppKit’s default is to keep running with no windows, which for a single-window game leaves
    // a process behind its own Dock icon with nothing to show and no way out but Cmd-Q.
    let delegate = AppDelegate()
    #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
}

@MainActor
@Test func theDelegateIsAnApplicationDelegate() {
    // A guard against the method above being moved somewhere AppKit never looks: the protocol
    // conformance is what makes the answer reach the framework at all.
    let delegate = AppDelegate()
    #expect(delegate is NSApplicationDelegate)
}
