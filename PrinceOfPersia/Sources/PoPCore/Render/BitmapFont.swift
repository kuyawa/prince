import Foundation

/// A BMFont page.
///
/// Port source: `reference/PrinceJS/assets/font/prince.fnt` and `prince_0.png` — the 256x256 page
/// the interface's text is drawn from. `Interface` builds it with
/// `game.make.bitmapText(SCREEN_WIDTH * 0.5, (UI_HEIGHT - 2) * 0.5, "font", ...)`.
///
/// The glyph metrics live here rather than in the host so that text layout stays part of the
/// render description: the host is handed final positions and draws them.
public struct BitmapFont: Sendable {
    public struct Glyph: Sendable, Equatable {
        /// `x`/`y`/`width`/`height` are the glyph's rectangle in the 256x256 page.
        public let x: Int
        public let y: Int
        public let width: Int
        public let height: Int
        /// Offsets from the pen position to the glyph's top-left.
        public let xOffset: Int
        public let yOffset: Int
        /// How far the pen advances, which is not the glyph width.
        public let xAdvance: Int
    }

    /// Distance between baselines' tops — the height of one line.
    public let lineHeight: Int
    /// The page file name, e.g. `prince_0.png`.
    public let pageFile: String

    private let glyphs: [Int: Glyph]

    public init(lineHeight: Int, pageFile: String, glyphs: [Int: Glyph]) {
        self.lineHeight = lineHeight
        self.pageFile = pageFile
        self.glyphs = glyphs
    }

    public func glyph(for character: Character) -> Glyph? {
        guard let scalar = character.unicodeScalars.first else { return nil }
        return glyphs[Int(scalar.value)]
    }

    public var glyphCount: Int { glyphs.count }

    /// One positioned glyph, ready to draw.
    public struct Placed: Sendable, Equatable {
        public let frameX: Int
        public let frameY: Int
        public let width: Int
        public let height: Int
        public let x: Int
        public let y: Int
    }

    /// Total advance width of a string.
    public func width(of text: String) -> Int {
        text.reduce(0) { $0 + (glyph(for: $1)?.xAdvance ?? 0) }
    }

    /// Lays a string out with its **top-left** at `(x, y)`.
    ///
    /// Zero-width glyphs — a space is 1x1 in this font — are skipped rather than drawn, but still
    /// advance the pen.
    public func layout(_ text: String, x: Int, y: Int) -> [Placed] {
        var placed: [Placed] = []
        var pen = x
        for character in text {
            guard let glyph = glyph(for: character) else { continue }
            if glyph.width > 1 || glyph.height > 1 {
                placed.append(Placed(
                    frameX: glyph.x, frameY: glyph.y,
                    width: glyph.width, height: glyph.height,
                    x: pen + glyph.xOffset, y: y + glyph.yOffset
                ))
            }
            pen += glyph.xAdvance
        }
        return placed
    }

    /// Lays a string out horizontally centred on `centreX`, its line top at `y`.
    public func layoutCentred(_ text: String, centreX: Int, y: Int) -> [Placed] {
        layout(text, x: centreX - width(of: text) / 2, y: y)
    }

    // MARK: - Parsing

    public enum ParseError: Error, CustomStringConvertible {
        case malformed(String)

        public var description: String {
            switch self {
            case let .malformed(detail): "Malformed BMFont: \(detail)"
            }
        }
    }

    /// Parses the XML form, which is what `prince.fnt` uses.
    ///
    /// The file is a flat list of self-closing elements, so this scans attributes rather than
    /// building an XML tree — there is no nesting to respect and no dependency to add.
    public static func parse(_ xml: String) throws -> BitmapFont {
        var lineHeight = 0
        var pageFile = ""
        var glyphs: [Int: Glyph] = [:]

        for element in xml.split(separator: "<") {
            guard element.hasPrefix("common") else {
                if element.hasPrefix("page"), let file = attribute("file", in: String(element)) {
                    pageFile = file
                }
                if element.hasPrefix("char"), let glyph = glyph(from: String(element)) {
                    glyphs[glyph.id] = glyph.value
                }
                continue
            }
            lineHeight = Int(attribute("lineHeight", in: String(element)) ?? "") ?? 0
        }

        guard lineHeight > 0, !pageFile.isEmpty, !glyphs.isEmpty else {
            throw ParseError.malformed("no line height, page or glyphs")
        }
        return BitmapFont(lineHeight: lineHeight, pageFile: pageFile, glyphs: glyphs)
    }

    private static func glyph(from element: String) -> (id: Int, value: Glyph)? {
        guard let id = Int(attribute("id", in: element) ?? ""),
              let x = Int(attribute("x", in: element) ?? ""),
              let y = Int(attribute("y", in: element) ?? ""),
              let width = Int(attribute("width", in: element) ?? ""),
              let height = Int(attribute("height", in: element) ?? ""),
              let xOffset = Int(attribute("xoffset", in: element) ?? ""),
              let yOffset = Int(attribute("yoffset", in: element) ?? ""),
              let xAdvance = Int(attribute("xadvance", in: element) ?? "")
        else { return nil }

        return (id, Glyph(
            x: x, y: y, width: width, height: height,
            xOffset: xOffset, yOffset: yOffset, xAdvance: xAdvance
        ))
    }

    private static func attribute(_ name: String, in element: String) -> String? {
        guard let range = element.range(of: "\(name)=\"") else { return nil }
        let rest = element[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}
