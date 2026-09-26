/// The little pool of blood a hit leaves under a fighter.
///
/// Port source: `reference/PrinceJS/src/Fighter.js#showSplash` (917), `#updateSplash` (928),
/// `#hideSplash` (910), `#tintSplash` (903), and the four call sites.
///
/// ## The exclusion list is the interesting part
///
/// ```js
/// showSplash: function () {
///   if (this.charName === "skeleton") { return; }
///   if (["dropdead", "falldead", "impale", "halve"].includes(this.action)) { return; }
///   this.splash.visible = true;
///   this.splashTimer = 2;
/// }
/// ```
///
/// Those four actions are the deaths that carry their own blood art — impaling and halving in
/// particular are drawn with the tile’s gore, and a pool underneath would be wrong. So the splash
/// is for a *wound*, not for a death.
///
/// **Which means the order of the calls matters.** `damageLife` calls `showSplash()` **before** it
/// sets the action, so a killing blow still shows the splash — he was not yet in a death animation
/// when the check ran. `CMD_DIE` calls it before the action changes for the same reason. Set the
/// action first and the last hit of a fight loses its splash.
public enum Splash {
    /// `splash.y` at rest, relative to the actor’s bottom-left anchor.
    public static let restingOffsetY = -15
    /// `splash.y` when the hit came while crouching.
    public static let crouchingOffsetY = -5
    /// `splash.x` — always six pixels left of the anchor.
    public static let offsetX = -6
    /// How long it stays up.
    public static let ticks = 2

    /// The actions that draw their own blood, so the splash stands down.
    public static let selfBloodying: Set<String> = ["dropdead", "falldead", "impale", "halve"]

    /// `Fighter.showSplash`. A skeleton has no blood to lose.
    public static func show(_ state: inout ActorState, crouching: Bool = false) {
        guard state.charName != "skeleton" else { return }
        guard !selfBloodying.contains(state.action) else { return }

        state.isSplashVisible = true
        state.splashTimer = ticks
        state.splashOffsetY = crouching ? crouchingOffsetY : restingOffsetY
    }

    /// `Fighter.hideSplash` — used by the shadow overlay, which draws its own.
    public static func hide(_ state: inout ActorState) {
        guard state.charName != "skeleton" else { return }
        state.isSplashVisible = false
    }

    /// `Fighter.tintSplash` — a guard’s pool is his own colour.
    public static func tint(_ state: inout ActorState, colour: Int?) {
        guard state.charName != "skeleton" else { return }
        state.splashTint = colour
    }

    /// `Fighter.updateSplash` — two ticks, then it is gone and back to its resting height.
    public static func update(_ state: inout ActorState) {
        guard state.charName != "skeleton" else { return }
        guard state.splashTimer > 0 else { return }

        state.splashTimer -= 1
        if state.splashTimer == 0 {
            state.isSplashVisible = false
            state.splashOffsetY = restingOffsetY
        }
    }

    /// The frame name, from the `general` atlas. `baseCharName` is what makes a `guard-3` draw
    /// `guard-splash` — there is no per-colour splash art.
    public static func frameName(for state: ActorState) -> String {
        "\(state.baseCharName)-splash"
    }
}
