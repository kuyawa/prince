/// The status bar.
///
/// Port source: `reference/PrinceJS/src/Interface.js`.
///
/// ```js
/// let bmd = this.game.make.bitmapData(SCREEN_WIDTH, UI_HEIGHT);
/// this.layer = this.game.add.sprite(0, (SCREEN_HEIGHT - UI_HEIGHT) * SCALE_FACTOR, bmd);
/// this.text = this.game.make.bitmapText(SCREEN_WIDTH * 0.5, (UI_HEIGHT - 2) * 0.5, "font", "", 16);
/// this.text.anchor.setTo(0.5, 0.5);
///
/// // the Prince's lives, along the left
/// this.playerHPs[i] = this.game.add.sprite(i * 7, 2, "general", "kid-live");
///
/// // the opponent's, right-aligned
/// this.oppHPs[i - 1] = this.game.add.sprite(SCREEN_WIDTH - i * 7 + 1, 2, "general",
///                                           actor.baseCharName + "-live");
/// ```
///
/// Everything here is in screen coordinates, y-down, with the bar occupying the bottom
/// `UI_HEIGHT` pixels — the 11-pixel gap ARCHITECTURE.md open question 4 flags between the room's
/// 189 and the screen's 200.
public enum HudRenderer {
    /// The black bar sits at the bottom of the screen.
    public static let barHeight = Geometry.uiHeight
    public static let barTop = Geometry.screenHeight - barHeight

    /// A pip is seven pixels wide including its gap, two pixels down inside the bar.
    public static let pipSpacing = 7
    public static let pipY = barTop + 2

    /// `Enemy.COLOR` — a guard's tint, selected by the level's `colors` field.
    public static let guardColors: [Int] = [
        0x4890fc, 0xa83000, 0xfc5000, 0x0c9000, 0x5a00fc, 0xc858fc, 0xfcfc00,
    ]

    /// Ticks the level's name stays up before the clock takes over —
    /// `showLevel`'s `hideTextTimer = 25`.
    public static let levelTitleTicks = 25

    public static func describe(
        world: World,
        clock: GameClock,
        ticksInLevel: Int,
        font: BitmapFont
    ) -> HudDescription {
        var hud = HudDescription()

        // The Prince's lives, along the left.
        let prince = world.prince
        for slot in 0..<max(prince.maxHealth, 0) {
            hud.pips.append(HudPip(
                frameName: slot < prince.health ? "kid-live" : "kid-emptylive",
                x: slot * pipSpacing,
                y: pipY,
                tint: nil
            ))
        }

        // The opponent's, right-aligned. `Enemy.COLOR[charColor - 1]`.
        if let opponent = currentOpponent(in: world), opponent.baseCharName != "skeleton" {
            let tint: Int? = opponent.guardColor > 0
                ? guardColors[min(opponent.guardColor - 1, guardColors.count - 1)]
                : nil
            for index in stride(from: opponent.health, through: 1, by: -1) {
                hud.pips.append(HudPip(
                    frameName: "\(opponent.baseCharName)-live",
                    x: Geometry.screenWidth - index * pipSpacing + 1,
                    y: pipY,
                    tint: tint
                ))
            }
        }

        // The text: the level's name first, then whatever the clock has to say.
        let message: String
        if ticksInLevel < levelTitleTicks {
            message = "LEVEL \(world.level.data.number)"
        } else {
            switch clock.readout {
            case .none:
                message = ""
            case let .timeUp(value):
                message = "\(value) \(value == 1 ? "SECOND" : "SECONDS") LEFT"
            case let .minutes(value):
                message = "\(value) \(value == 1 ? "MINUTE" : "MINUTES") LEFT"
            case let .seconds(value):
                message = "\(value) \(value == 1 ? "SECOND" : "SECONDS") LEFT"
            }
        }
        hud.text = message
        hud.glyphs = font.layoutCentred(message, centreX: Geometry.screenWidth / 2, y: textTop(font))
        return hud
    }

    /// `(UI_HEIGHT - 2) * 0.5` below the bar's top, less half a line, because Phaser centres the
    /// text block on that point rather than top-aligning it.
    static func textTop(_ font: BitmapFont) -> Int {
        let centre = barTop + (barHeight - 2) / 2
        return centre - font.lineHeight / 2
    }

    /// Who the Prince is fighting, if anyone.
    static func currentOpponent(in world: World) -> ActorState? {
        let prince = world.prince
        return world.actors.dropFirst()
            .filter { $0.isAlive && $0.isActive && $0.room == prince.room }
            .min {
                abs($0.charX - prince.charX) < abs($1.charX - prince.charX)
            }
    }
}

/// What the host draws for the status bar.
public struct HudDescription: Sendable, Equatable {
    public var pips: [HudPip] = []
    public var text: String = ""
    /// Text already positioned, so layout stays on this side of the boundary.
    public var glyphs: [BitmapFont.Placed] = []

    public init() {}
}

/// One life pip. `frameName` indexes the `general` atlas; `tint` is 0xRRGGBB.
public struct HudPip: Sendable, Equatable {
    public var frameName: String
    public var x: Int
    public var y: Int
    public var tint: Int?

    public init(frameName: String, x: Int, y: Int, tint: Int?) {
        self.frameName = frameName
        self.x = x
        self.y = y
        self.tint = tint
    }
}
