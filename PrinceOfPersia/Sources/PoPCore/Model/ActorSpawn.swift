import Foundation

public extension ActorState {
    /// `Game.js`'s Prince construction.
    ///
    /// ```js
    /// let turn = json.prince.turn !== false;
    /// let direction = json.prince.direction * (json.prince.reverse || 1);
    /// if (turn) { direction = -direction; }
    /// this.kid = new PrinceJS.Kid(game, level, json.prince.location, direction, json.prince.room);
    /// if (turn) { this.kid.charX += 7; ... action = "turn" ... }
    /// ```
    static func prince(from spawn: PrinceSpawn) -> ActorState {
        var actor = ActorState(
            location: spawn.location,
            room: spawn.room,
            face: spawn.effectiveDirection,
            action: spawn.shouldTurn ? "turn" : "stand",
            charName: "kid"
        )
        if spawn.shouldTurn { actor.charX += 7 }
        actor.hasSword = spawn.sword ?? true
        // The Prince's health comes from the run, not the level.
        actor.health = 3
        actor.maxHealth = 3
        return actor
    }

    /// `Game.js`'s guard construction, plus `Enemy`'s constructor.
    ///
    /// ```js
    /// let enemy = new PrinceJS.Enemy(game, level, data.location + (data.bias || 0),
    ///                                data.direction * (data.reverse || 1), data.room,
    ///                                data.skill, data.colors, data.type, i + 1);
    /// ```
    static func enemy(from spawn: GuardSpawn, levelNumber: Int) -> ActorState {
        let name = ActorKind.enemyCharName(type: spawn.type, colour: spawn.colors)
        var actor = ActorState(
            location: spawn.location + (spawn.bias ?? 0),
            room: spawn.room,
            face: spawn.effectiveDirection,
            action: spawn.type == .skeleton ? "laydown" : "stand",
            charName: name
        )
        // `Enemy`'s constructor nudges him seven x-units forward.
        actor.charX += spawn.effectiveDirection * 7

        actor.baseCharName = spawn.type == .guard ? "guard" : name
        actor.charSkill = spawn.skill
        actor.hasSword = true
        actor.health = GuardBrain.health(skill: spawn.skill, levelNumber: levelNumber)
        actor.maxHealth = actor.health
        actor.isActive = spawn.active ?? true
        actor.isVisible = spawn.visible ?? true
        actor.sneakUp = spawn.sneak ?? true
        actor.hasStartedFight = false
        return actor
    }
}
