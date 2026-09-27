import AppKit
import PoPCore

/// The switch. Presentation-only scaling between the game's native pixel space
/// and the window.
///
/// This is deliberately confined to `PoPHost` (ARCHITECTURE.md Law 8). The
/// simulation always works in the original 320 x 200 pixel units, because every
/// magic number in the reference is expressed in them — 32 x 63 tiles,
/// `charY += 189` on a room change, `maxHurtDistance = 29`. Scaling happens once,
/// at the last possible moment, in the renderer.
///
/// Because of that boundary, changing this number cannot affect gameplay. It is
/// the one thing in the project that is genuinely free to change.
///
/// **Integer multiples only.** A fractional scale would land the 32 x 63 tile
/// grid on non-integer device pixels and the art would shimmer.
public enum WindowScale {
    /// Hard clamp, independent of the display. Guards against nonsense input.
    public static let absoluteRange = 1...8

    /// Default window scale. Mirrors `SCALE_FACTOR` from PrinceJS `Boot.js`
    /// rather than duplicating the value.
    public static let standard = Geometry.scaleFactor

    /// The game's native pixel space. Never scaled, never negotiated with.
    public static var playfieldSize: CGSize {
        CGSize(width: CGFloat(Geometry.screenWidth),
               height: CGFloat(Geometry.screenHeight))
    }

    /// Window content size in points for an integer scale.
    public static func windowSize(for scale: Int) -> CGSize {
        let factor = CGFloat(clamp(scale))
        return CGSize(width: playfieldSize.width * factor,
                      height: playfieldSize.height * factor)
    }

    /// Scales that actually fit on the current display, ascending.
    ///
    /// Offering a window taller than the screen is a bug, not a feature, so the
    /// View menu is built from this rather than from `absoluteRange`.
    public static var fitting: [Int] {
        guard let screen = NSScreen.main else { return [standard] }
        let available = screen.visibleFrame.size
        var result: [Int] = []
        for scale in absoluteRange {
            let size = windowSize(for: scale)
            guard size.width <= available.width, size.height <= available.height else { break }
            result.append(scale)
        }
        return result.isEmpty ? [standard] : result
    }

    /// Clamps to the hard range only. Never consults the screen, so it is safe
    /// to call from `windowSize(for:)` without recursing.
    public static func clamp(_ requested: Int) -> Int {
        guard requested > 0 else { return standard }
        return min(max(requested, absoluteRange.lowerBound), absoluteRange.upperBound)
    }

    /// Clamps to the largest scale that fits the current display.
    ///
    /// Applied to the command line as well as the menu: a window taller than the
    /// screen is unusable, so it is never worth honouring the request literally.
    public static func fitted(_ requested: Int) -> Int {
        let bounded = clamp(requested)
        guard let largest = fitting.last else { return bounded }
        return min(bounded, largest)
    }

    /// Reads `--scale N` from the command line, or `nil` when the flag is absent.
    ///
    /// This only *parses* the flag. What an absent flag should mean is a question about what the
    /// player chose last time, and that belongs to `WindowSettings.startingScale`, which is also
    /// where the value is clamped to the display. Returning `standard` here would erase the
    /// difference between "the player asked for 2" and "the player asked for nothing" — and that
    /// difference is the whole of what is being decided.
    public static func requestedScale(from arguments: [String]) -> Int? {
        guard let index = arguments.firstIndex(of: "--scale"),
              index + 1 < arguments.count,
              let value = Int(arguments[index + 1])
        else { return nil }
        return value
    }
}
