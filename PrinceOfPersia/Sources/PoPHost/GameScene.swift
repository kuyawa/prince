import SpriteKit
import PoPCore

/// M0 placeholder scene.
///
/// The real scene (sprite layers, room camera, tile drawing) arrives in M4.
/// For now this exists to prove the pipeline: SwiftPM executable -> PoPHost ->
/// SpriteKit -> a correctly sized playfield on screen.
@MainActor
public final class GameScene: SKScene {
    public override init(size: CGSize) {
        super.init(size: size)
        self.scaleMode = .aspectFit
        self.backgroundColor = SKColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)
        buildPlaceholder()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("GameScene is created in code, never from a nib")
    }

    /// Draws the playfield bounds so M0 is visually verifiable.
    private func buildPlaceholder() {
        let bounds = CGRect(x: 0, y: 0,
                            width: CGFloat(Geometry.roomWidth),
                            height: CGFloat(Geometry.roomHeight))

        // The 10 x 3 tile grid, so the unusual 32 x 63 tile shape is visible.
        let grid = SKShapeNode()
        let path = CGMutablePath()
        for column in 0...Geometry.roomColumns {
            let x = CGFloat(column * Geometry.blockWidth)
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: bounds.height))
        }
        for row in 0...Geometry.roomRows {
            let y = CGFloat(row * Geometry.blockHeight)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: bounds.width, y: y))
        }
        grid.path = path
        grid.strokeColor = SKColor(white: 1, alpha: 0.14)
        grid.lineWidth = 0.5
        addChild(grid)

        let outline = SKShapeNode(rect: bounds)
        outline.strokeColor = SKColor(white: 1, alpha: 0.45)
        outline.lineWidth = 0.5
        addChild(outline)

        let label = SKLabelNode(text: "M0 — geometry check")
        label.fontName = "Menlo"
        label.fontSize = 11
        label.fontColor = SKColor(white: 0.75, alpha: 1)
        label.position = CGPoint(x: bounds.midX, y: bounds.midY + 6)
        addChild(label)

        let detail = SKLabelNode(text: "\(Geometry.roomColumns)x\(Geometry.roomRows) tiles of \(Geometry.blockWidth)x\(Geometry.blockHeight) = \(Geometry.roomWidth)x\(Geometry.roomHeight)")
        detail.fontName = "Menlo"
        detail.fontSize = 8
        detail.fontColor = SKColor(white: 0.45, alpha: 1)
        detail.position = CGPoint(x: bounds.midX, y: bounds.midY - 8)
        addChild(detail)
    }
}
