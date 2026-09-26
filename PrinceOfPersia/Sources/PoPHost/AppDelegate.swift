import AppKit

/// The application delegate, which exists for exactly one reason.
///
/// **AppKit does not quit when the last window closes.** The default is to keep the process alive
/// with a Dock icon and a menu bar that do nothing — which is right for an app with documents to
/// keep open or a window to reopen, and wrong for this one. There is a single window, there is no
/// document, and there is nothing to come back to, so closing it is the player saying they are
/// done.
///
/// Without this, closing the window leaves a game running invisibly behind its own Dock icon, and
/// the only way out is to notice and press Cmd-Q.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    public func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}
