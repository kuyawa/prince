import AppKit
import SpriteKit
import PoPCore

/// Loads a TexturePacker atlas into individual `SKTexture`s.
///
/// **Not `SKTextureAtlas`.** That type expects Xcode's `.atlas` folder layout; these are
/// TexturePacker JSON sheets with explicit rectangle lists, so each frame becomes a
/// sub-rectangle of one base texture.
public struct TextureAtlas {
    public let textures: [String: SKTexture]
    public let imageSize: CGSize
    public let frameCount: Int

    public enum LoadError: Error, CustomStringConvertible {
        case missingSheet(String)
        case unreadableImage(String)

        public var description: String {
            switch self {
            case let .missingSheet(name): "No such atlas: \(name).json"
            case let .unreadableImage(name): "Could not decode \(name)"
            }
        }
    }

    public init(named name: String) throws {
        let directory = GameData.rootURL.appendingPathComponent("gfx")
        let sheetURL = directory.appendingPathComponent("\(name).json")
        guard let sheetData = try? Data(contentsOf: sheetURL) else {
            throw LoadError.missingSheet(name)
        }
        let sheet = try JSONDecoder().decode(Sheet.self, from: sheetData)

        let imageURL = directory.appendingPathComponent(sheet.meta.image)
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw LoadError.unreadableImage(sheet.meta.image)
        }

        let base = SKTexture(cgImage: cgImage)
        base.filteringMode = .nearest

        let width = CGFloat(sheet.meta.size.w)
        let height = CGFloat(sheet.meta.size.h)

        var textures: [String: SKTexture] = [:]
        textures.reserveCapacity(sheet.frames.count)
        for (key, entry) in sheet.frames {
            // `SKTexture(rect:in:)` measures from the BOTTOM-left, while TexturePacker
            // (and PNG itself) measures from the top-left, so the y origin has to be
            // mirrored. Getting this wrong does not fail loudly — it silently samples the
            // wrong part of the sheet and the room renders as textured noise.
            let rect = CGRect(
                x: CGFloat(entry.frame.x) / width,
                y: (height - CGFloat(entry.frame.y) - CGFloat(entry.frame.h)) / height,
                width: CGFloat(entry.frame.w) / width,
                height: CGFloat(entry.frame.h) / height
            )
            let texture = SKTexture(rect: rect, in: base)
            texture.filteringMode = .nearest
            textures[key] = texture
        }

        self.textures = textures
        self.imageSize = CGSize(width: width, height: height)
        self.frameCount = textures.count
    }

    public func texture(_ frameName: String) -> SKTexture? {
        textures[frameName]
    }

    public var frameNames: [String] { Array(textures.keys) }

    // MARK: - Sheet schema

    private struct Sheet: Decodable {
        let frames: [String: Entry]
        let meta: Meta

        struct Entry: Decodable {
            let frame: Rect
        }

        struct Rect: Decodable {
            let x: Int, y: Int, w: Int, h: Int
        }

        struct Meta: Decodable {
            let image: String
            let size: Size

            struct Size: Decodable {
                let w: Int, h: Int
            }
        }
    }
}
