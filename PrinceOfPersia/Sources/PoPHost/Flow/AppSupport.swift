import Foundation

/// Where this app keeps the small amount it remembers between runs.
///
/// `Application Support`, not the bundle: a `.app` is code-signed and read-only, and both of the
/// files that live here exist to be edited or written by the player — key bindings by hand, and
/// progress by the game itself.
public enum AppSupport {
    public static var directory: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PrinceOfPersia", isDirectory: true)
    }

    /// Creates a directory if it is not there yet. Returns whether it now exists.
    ///
    /// Takes the directory rather than assuming the default one. It used to assume, which was
    /// wrong for the test suite — and would have been wrong for anything that ever wrote to a
    /// different location, including a player who moved the folder.
    @discardableResult
    public static func createDirectory(at url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}
