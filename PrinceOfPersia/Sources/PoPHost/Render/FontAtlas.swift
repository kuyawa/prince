import AppKit
import SpriteKit
import PoPCore

/// The BMFont page as a SpriteKit texture, sliced per glyph on demand.
///
/// `BitmapFont` owns the metrics; this owns the pixels. A glyph's position is already final by the
/// time it reaches here, so there is nothing to lay out.
public struct FontAtlas {
    private let base: SKTexture
    public let size: CGSize

    public init(font: BitmapFont) throws {
        let url = GameData.rootURL.appendingPathComponent("font/\(font.pageFile)")
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw TextureAtlas.LoadError.unreadableImage(font.pageFile) }

        let texture = SKTexture(cgImage: cgImage)
        texture.filteringMode = .nearest
        self.base = texture
        self.size = CGSize(width: cgImage.width, height: cgImage.height)
    }

    /// A glyph's rectangle, measured from the page's TOP-left as BMFont declares it.
    public func texture(_ placed: BitmapFont.Placed) -> SKTexture? {
        guard placed.width > 0, placed.height > 0,
              size.width > 0, size.height > 0 else { return nil }

        let rect = CGRect(
            x: CGFloat(placed.frameX) / size.width,
            y: (size.height - CGFloat(placed.frameY) - CGFloat(placed.height)) / size.height,
            width: CGFloat(placed.width) / size.width,
            height: CGFloat(placed.height) / size.height
        )
        let texture = SKTexture(rect: rect, in: base)
        texture.filteringMode = .nearest
        return texture
    }
}
