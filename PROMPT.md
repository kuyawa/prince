# Kickoff Prompt — Prince of Persia in Swift

**How to use this file:** start a fresh session and say **"read PROMPT.md"**. It is written to
be pasted or referenced as-is. Keep the Status and Task Board sections updated as you go —
this file is the project's memory, `ARCHITECTURE.md` is its law.

---

## The prompt

> You are working on a native macOS port of **Prince of Persia (1989, DOS lineage)** in Swift.
>
> **Read `ARCHITECTURE.md` in full before writing any code.** It contains the thesis, the
> non-negotiable laws, the module layout and the subsystem specs.
>
> The thesis in one line: **port the *game* exactly, rewrite the *engine* completely.**
> PoP's behaviour lives in a data-driven sequence virtual machine; its host was Phaser 2.6.2,
> a dead 2017 engine welded into the logic. `PoPCore` is a faithful port of the former.
> `PoPHost` is an idiomatic Swift 6 rewrite of the latter.
>
> Three references are cloned under `reference/`:
> - `reference/PrinceJS` — **the primary port source.** Public domain, ~8.2k LOC of JS, all
>   assets pre-extracted as PNG + JSON.
> - `reference/SDLPoP` — **the behavioural oracle.** C, GPLv3, actively maintained. Its
>   `doc/` folder is the best documentation of the game's internals that exists. Consult it
>   whenever PrinceJS is ambiguous. **Never port its code** (GPL) — read it only.
> - `reference/POP-AppleII` — Mechner's original 6502 assembly. Historical reference only.
>
> Work one milestone at a time, in order. Do not start the next milestone until the current
> one's "done when" criterion actually passes. When the reference implementation is ambiguous,
> **read it — do not guess.** Every magic number you transcribe should carry a comment naming
> the file and symbol it came from.

---

## The Laws

Repeat these back before you start work. Violating any one of them is how this project dies.

1. **Do not "optimise" the simulation.** Fidelity is the specification. Every offset,
   threshold and probability in the reference is a behavioural contract with 1989.
2. **No ECS, no behaviour trees, no `GKRuleSystem`.** The sequence VM *is* the architecture.
3. **Never use `GKRandomSource` or any non-deterministic RNG.** Use the bit-exact MSVC LCG
   (`ARCHITECTURE.md` §7.7).
4. **Fixed timestep only.** 1/12 s, or 1/10 s while fighting. Never drive the sim from vsync.
5. **`PoPCore` imports no SpriteKit, AppKit, GameplayKit or AVFoundation.** Ever.
6. **The simulation never touches the keyboard.** It consumes `Intents` values.
7. **No `actor` per character.** Hops have no ordering guarantee; determinism wins.
8. **Presentation is disposable.** The sim emits a `RenderDescription`; the host draws it.

---

## Status

| | |
|---|---|
| **Current milestone** | — nothing open. The port is feature-complete |
| **Last completed** | **One keyboard for the process** — a second `KeyboardInput` was swallowing every arrow. 367 tests pass |
| **Blocked on** | nothing |
| **Open questions** | 7, listed in `ARCHITECTURE.md` §10 |
| **Next action** | Optional, in rough value order: cutscenes (open question 5), the shadow overlay (levels 5/6), a title screen. Or stop — it plays |

---

## Task board

Tick these off as they land. Full "done when" criteria are in `ARCHITECTURE.md` §9.

### M0 — Skeleton ✅ *complete*
- [x] `git init`; add `.gitignore` containing `reference/`, `.build/`, `.DS_Store`, `*.xcodeproj`
- [x] Create `PrinceOfPersia/Package.swift` with targets `PoPCore`, `PoPHost`, `Prince`, `PoPCoreTests`
- [x] `swift-tools-version: **6.2**`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`
      — **6.2, not 6.0**: `.macOS(.v26)` does not exist in the 6.0 tools manifest. Verified.
- [x] Copy game assets from `reference/PrinceJS/assets/` into the package's resources
      (`gfx`, `maps`, `anims`, `sfx`, `music`, `font`, `cutscenes`) — 7.8 MB, 133 files.
      `maps/custom/` (212 third-party levels) and `assets/web/` (18 MB of site graphics) excluded.
- [x] `SKScene` in a 640 × 400 window, `scaleMode = .aspectFit`. A 10 × 3 tile grid is drawn so
      the 32 × 63 tile shape is visible. `filteringMode = .nearest` deferred to M4 — there are
      no textures to filter yet.
- [x] Confirm: `swift test` passes (4/4) and `swift run Prince` opens the window
- [x] Bonus: window scale is a **runtime switch** — `--scale N`, plus a View menu
      (Cmd-1..Cmd-N), capped to what fits the display. Nothing in `PoPCore` can see it.
      See `ARCHITECTURE.md` §7.9.1.

### M1 — Data layer ✅ *complete*
- [x] `LevelData`, `RoomData`, `Tile`, `GuardSpawn`, `EventTrigger`, `PrinceSpawn` as `Codable` + `Sendable`
- [x] `TileKind` — **33 values, 0…32**, not 29. §6.2 was wrong and is now corrected
- [x] `AnimationTable` + `FrameDef` + `SwordOffsetTable` decoding; `fcheck` hex string → `UInt8`
- [x] `FrameCheck` bitfield (bits 0–4 foot, 5 thin, 6 check, 7 parity — §7.3)
- [x] Tests: **30 passing**. Levels, tables, bitfields, event holes, the `fcheck` corpus
- [x] Found and handled five data realities the design had assumed away:
  - events are **index-addressed with load-bearing `null` holes** (levels 6 and 8)
  - `guard.reverse` is `-1`, a **number**, not a flag — a `Bool` would decode cleanly and
    silently drop every guard reversal
  - rooms with `id == -1` carry **no `tile` key at all** (200 of 476 room slots)
  - 33 `framedef` entries are **comment-only**, with no `fdx`/`fdy`/`fcheck`
  - `sword.json` is a **different schema** (`swordtab`), and `shadow.json` holds a
    **dangling branch** to a sequence it never defines

### M2 — Sequence VM ✅ *complete*
- [x] `Opcode` enum — 16 values; everything else is `NOOP`, as the reference fills all 256 first
- [x] Opcode bodies transcribed from `Actor.js` / `Fighter.js` / `Kid.js`
- [x] `ActorState` + `CoordinateSpace` conversions from `Utils.js`
- [x] `SequenceInterpreter.step()` — the `while processing` loop, runs until a frame is emitted
- [x] Open question 3 **closed**: `Int` in engine units. `charX` is x-units (140/room), not pixels
- [x] Tests: **56 passing**. `stand`, `startrun`, `running`, `turn`, `softland`, `stepfall` traced
      tick-for-tick against a faithful re-implementation of `processCommand` driving the real
      `kid.json` — expectations are reference-derived, not hand-computed
- [x] Per-class opcode gate proved with real data: `shadow.json`'s `softland` shakes for a Kid and
      is inert for a Fighter; the dangling `shadow → stepfloat` branch is unreachable *because*
      `IFWTLESS` is Kid-only
- [x] Open question 9 also closed: `fsword` is a 1-based **positional** index into `swordtab`

### M3 — Movement and tile queries *（partially complete）*
**Done (M3a):**
- [x] **Open question 8 CLOSED**: actors use `location % 10` / `/ 10`; events use `location - 1`.
      SDLPoP confirms in three places (`pos_guards`, `do_startpos`, teleport). **All 55 actor
      spawns disagree** between the conventions — every guard and the Prince would have been
      one column off. SDLPoP's `TILE_SIZEX 14` / `TILE_MIDX 7` also corroborate the x-units
- [x] `LCG` — MSVC `rand()`, bit-exact with wrapping arithmetic, checked against reference
      values *and* against the raw internal states
- [x] `Ticker` — fixed timestep, 12 Hz / 10 Hz, clamped catch-up, drift-absorbing epsilon
- [x] `LevelRuntime` — room grid, derived links (never stored), `getRoomId` returning `-1`,
      off-map dummy wall
- [x] `TilePredicates` — all eight predicates, verified against a bitmask table generated by
      running the **JavaScript** over all 33 kinds
- [x] `Physics` — gravity (only when `actionCode == 4`), terminal velocity, float variants
- [x] `FallCycle` — `checkFall`, `land`, `startFall` (open-air path), `checkRoomChange`
- [x] Headless trace: a free-fall accelerates 3/6/9/12 and lands on frame 4 at charY 53

**Done (M3b) — the control layer:**
- [x] `Intents` — input as a value type (Law 6: the sim never reads the keyboard)
- [x] `Behaviour.update` — the port of `Kid.updateBehaviour` (`Kid.js:237-490`)
- [x] Verbs: `turn`, `standjump`, `startrun`, `runturn`, `turnrun`, `runjump`, `rdiveroll`,
      `standup`, `crawl`, `runstop`, `stoop`, `step`
- [x] `nearBarrier`, `canCrossGate`, `distanceToEdge`
- [x] Reference traces for walk → run, turn on the spot, run → stop, and jump from a run

**Still open (M3c):**
- [ ] `checkBarrier` — `Kid.js:600-719`. Reads Phaser sprite bounds, and `getBounds` mixes
      screen pixels with engine units (`roomX * 32 + 40`). **Open question 11.** Do not port
      verbatim; decide the engine-unit equivalent first
- [ ] `jump()` — **not a verb.** A decision tree over five tile probes that routes into the
      whole ledge system (`checkClimbable`, `jumphanglong`, `jumpbackhang`, `jumpup`,
      `highjump`, `climbstairs`). Cannot precede the hanging states
- [ ] Ledge and hang: `tryGrabEdge`, `grab`, `climbup`, `climbdown`, `hang`, `hangstraight`
- [ ] `checkButton`, `checkSpikes`, `checkChoppers` — need the trob (interactive tile) layer
- [ ] Cross-room tile resolution (`Level.js#getRoomX`/`#getRoomY`) — **open question 10**,
      already observable in the turning trace
- [ ] Kid's own `checkRoomChange` (the screen-edge version) distinct from Fighter's
- [ ] `stoop`'s pickup branches (`gotSword`, `drinkPotion`) — need trobs
- [ ] Preserve the **call order** from `Enemy.js#updateActor` — the order is behaviour
- [ ] `LCG` (MSVC `rand()`, bit-exact, `UInt32` wrapping) + tests against the reference formula
- [ ] `Ticker`: fixed timestep accumulator, clamped catch-up, 12 Hz / 10 Hz
- [ ] Headless trace: Prince walks, jumps, falls, lands correctly

### M4 — Rendering ✅ *complete*
- [x] `AtlasLoader` — TexturePacker JSON → `SKTexture(rect:in:)`, nearest filtering
- [x] `RenderDescription` / `SpriteInstance` as the sim→render contract (§7.9)
- [x] `RoomRenderer` — background, foreground, the `<element>_<modifier>` detail child, and
      the 212 dungeon wall-shape frames
- [x] `LevelScene` — the y-flip, `roomTopY = 189`, z order (back 10 / actor 20 / front 30)
- [x] `KeyboardInput` → `Intents`; `--screenshot`, `--trace`, `--hold`, `--dump-frame`
- [x] **113 tests pass**, including an exhaustive check that every frame the renderer asks for
      exists in the atlas, across all 14 levels and every room
- [x] Level 1 draws; the Prince falls out of his cell, lands, and walks

**Found while rendering:**
- `SKTexture(rect:in:)` measures from the **bottom-left**, TexturePacker from the top-left.
  The bug is silent — the room rendered as plausible textured noise. The `--dump-frame`
  diagnostic caught it.
- **A mirror draws as floor** (`Tile.Mirror` passes `TILE_FLOOR`); there is no `dungeon_13`.
- `checkFloor`'s falling branch **skips `stepfall`** unless `checkFloorStepFall` is armed —
  without the guard a scripted fall lands on its first tick.
- **Palace wall colour overlays are not ported** (open question 12). Level 4 renders flatter.

### M5 — Level graph and transitions ✅ *complete*
- [x] `RoomGraph` — grid, `id == -1` holes, derived links (done in M3a)
- [x] **Cross-room tile lookup** — `getRoomX`/`getRoomY`, resolving **open question 10**
- [x] Room wrapping in `updateBlockPosition`: `charX ± 140` x-units, `baseX ± 320` pixels
- [x] `Kid.checkRoomChange` (threshold **189**, not the Fighter's 192) + `changeRoomDown`
      with its corner cases for falling through the edge of a room
- [x] `moveL` / `moveR`, and `updateFallingBlocks`
- [x] `CMD_UP`/`CMD_DOWN` were already wired in M2
- [x] **125 tests pass**, including two reference traces crossing from room 21 into room 5

**Found:**
- **Two different cross-room lookups exist.** `Level.getTileAt` chains (X, then Y-then-X);
  `LevelBuilder.getTileObjectAt` applies all four offsets independently against the original
  room. They agree where only x varies, which is every current caller. Open question 13.
- Room 5 has **gates**; the first reference trace silently used a tracer whose `nearBarrier`
  had no gate check, so the trace was wrong. Retargeted to room 21, which has a clean edge.
  A reminder that a tracer is only as faithful as its weakest stub.
- The renderer's wall-shape probe benefits from the same lookup: column 0 of room 1 now sees
  a gate in room 5 rather than an assumed wall, so its wall frame changes — correctly.

- [ ] **Not done:** `guards{}`/`events{}` loading (waits on M6 combat and M7 trobs), and
      "level 1 traversable end to end" still needs `checkBarrier` and the exit door

### M7 — Hazards and mechanisms *(partially complete)*
**Done (M7a):**
- [x] `LevelState` + `World` — the immutable level paired with its mutable state
- [x] **`Gate`** — the full state machine: 47-pixel raise, 50-tick wait, 1px/4-tick close,
      10px/tick slam, and `closedFast` so a held button cannot re-raise a slammed gate
- [x] **`Button`** — push, step timers, raise/drop/stuck variants
- [x] **`fireEvent`** with chaining; level 1's raise button opens two gates through it
- [x] `TileChecks.prepareCheckFloor` and `checkButton`
- [x] `gateBlocks` wired to real state — **the stub is gone**; gates now open
- [x] Gate rendering via `SpriteInstance.clipTop`, verified on screen

**Found:**
- **A button's `modifier` is a 0-based INDEX into the events array**, not the entry's `number`.
  Level 1's room-5 buttons (modifiers 8, 9, 11) all resolve to room-5 events, which is where the
  gates are. The other reading points one of them at room 8.
- `Gate.raise` from `fastDropping` does **not** cancel the slam — the reference's guard excludes
  that state. Reproduced rather than tidied, and pinned by a test.
- I omitted `checkButton`'s `actionCode` guard on the first pass, so a *falling* actor pressed
  buttons. A test caught it.

**Done (M7b):**
- [x] **Loose boards** — eight shake frames, then the board collapses. `floorStartFall` replaces
      the tile with **SPACE**: the hole *is* the mechanism, and the Prince falls through it with
      no special case. Level 1's cell is escaped this way
- [x] **Exit door** — raise 1px/tick until 8 remain, drop 15px/tick, opened by the raise button
      whose modifier indexes `events[3]`
- [x] **`jump()`** — the full five-probe decision tree, and **`climbstairs`**, so an open exit
      actually ends the level. `NEXTLEVEL` was already wired
- [x] `hang`/`hangstraight`/`climbup`/`climbdown`/`stoop` control flow
- [x] `LevelState.overrides` for tiles that change, and `Behaviour` gained an effects channel

**Found:**
- **`floorStartFall` replaces the tile with SPACE.** I expected a "start falling" callback wiring
  the Prince to the board. There is none — the hole does it.
- **The exit door's raise terminator depends on Phaser's `crop()` rewriting `sprite.height`.**
  Modelled as `visibleHeight` instead; the intent is unambiguous.
- A frame definition's foot offset **only arrives at `CMD_FRAME`**, not at construction, so a test
  that asserts `charBlockX` before running the sequence is asserting the wrong thing. Cost me two
  attempts.

**Done (M7c-1):**
- [x] **Spikes** — the five-up/sixteen-out/four-down cycle, `checkSpikes`’ column walk, and the
      standing branch’s impale check
- [x] **`dieSpikes`** and **`alignToTile`**, which is how a body ends up inside the tile it died on
- [x] **Potions** — all five effects, the twelve-tick delay, and `Level.removeObject`
- [x] **Sword pickup** and `gotSword`, which is the moment level 1 turns into a fight
- [x] **`ActorEffect.music`** — `game.sound.play` plays music keys too, and three call sites do
- [x] **Rendering** for all three, including the potion bubbles in the `general` atlas

**Found:**
- **Every spike, chopper, loose board and sword in all fourteen levels has modifier 0.** So the
  `modifier === 0` guard on spike trobs excludes nothing, and the modifier→sprite-frame remap is
  dead code. Ported anyway; recorded so it is a decision rather than an oversight.
- **`POTION_SPECIAL` (6) appears in no level.** The special-potion branch — read a modifier from
  room 8 tile 0, fire an event a second later — is unreachable. Modelled in the data, not built.
- **`inSpikeDistance` returns `true` unconditionally.** Neither `Kid` nor `Fighter` overrides it,
  so the geometry test the name promises does not exist.
- **A running Prince only dies on spikes that are not fully out.** It reads backwards until you see
  that `checkSpikes` raised the field a tick earlier, so it is still rising when he steps on it.
- **Spike retraction skips frame 3** — four ticks down against five up.
- **The pickup key is the action key *alone*.** The standing branch checks up, then down, then
  pickup, so holding down crouches forever on top of the sword. Cost me one wrong trace.
- **`World.apply` was re-applying the whole accumulated effect list on every call within a tick.**
  Invisible for idempotent effects; for the potion queue it meant one drink made three bottles and
  the theme played over itself three times. Fixed by tracking how many effects the world has seen.
- **`Preloader` never loads `Float`.** `Kid.floatFall` calls `sound.play("Float")` and Phaser does
  nothing. The port’s eight music tracks are the complete set.
- **A potion’s bubbles come from the `general` atlas**, not the level’s — the one sprite in the
  game that belongs to neither a tile nor an actor.

**Done (M7c-2):**
- [x] **`SpriteMetrics`** — cel sizes read out of the atlas JSON, for `chopDistance` and eventually
      `checkBarrier`
- [x] **`Chopper`** — the fifteen-step cycle, the cut on step 3 only, and the blood stain
- [x] **`activateChopper`** and the travelling-wave cascade across a row of blades
- [x] **`checkChoppers`**, the halving death, and the `turn` exemption
- [x] Rendering, including the missing-frame-0 trap

**Found:**
- **`activateChopper` takes a starting column and the two callers differ.** `checkChoppers` passes
  `-1` (the leftmost blade); `onChopped` passes its own `roomX`, so a cut wakes the **next** blade
  along. I had it scanning from zero for both, which made level 3's three-blade row walkable —
  blades two and three never ran. Caught by a test asserting which blade woke.
- **A dungeon tile cel is 60 x 79 packed at a 32 x 63 cell origin**, so `tile.centerX` is 14 px
  right of the cell centre. Combined with `PIXI.Sprite.width = scale.x * texture.frame.width` —
  confirmed in the vendored Phaser — half an actor's width swings further than the 6-pixel window
  it is tested against. Hence the cel-size table.
- **There is no `dungeon_chopper_0`.** `update` increments before naming a frame, so the first
  frame drawn is 1 and the resting pose is 5.
- **A chopper is lethal on 3 ticks of 15, in a band about 12 px wide**, while a running Prince
  covers ~11 px a tick. The blades are genuinely dodgeable at a run — level 3's room 16 is a timing
  puzzle, not a wall. Worth knowing before "fixing" it.

**Still open (M6d):**
- [ ] **`checkBarrier`** (M3c) — now unblocked by `SpriteMetrics`; it still gates `bump` and the
      mirror branches of `jump()`
- [ ] The **time-up** hand-off: `timeUp` is detected but the host does not yet end the run
- [ ] The dying animation's splash sprite, and the shadow overlay
- [ ] **Ledges** — `tryGrabEdge`, `checkLedgeSwing`, `jumphang*`; the float potion's two ledge
      tweaks ride along with them
- [ ] `floorStopFall` — the board landing and becoming debris is not modelled (visual only)

### M6 — Combat and guards *(partially complete)*
**Done (M6a):**
- [x] **`Combat`** — the queries (`opponentDistance`, `facingOpponent`, `canSeeOpponent`,
      `canWalkOnNextTile`, the room-visibility helpers), the six verbs, and `checkFight`'s
      strike resolution
- [x] **`GuardBrain`** — the full probability tables, the distance bands, the timers, and the
      engage/advance/retreat/block/strike decisions
- [x] **Open question 2 CLOSED**: SDLPoP's `prandom` is the *same* LCG already ported for wall
      patterns, so guard behaviour is now reproducible from a seed — which PrinceJS cannot do,
      since it draws from a clock-seeded generator
- [x] `ActorState` combat fields: health, skill, the three timers, `frameID`

**Found:**
- **`die()` zeroes the health**, and `damageLife` calls `die` at one health rather than
  decrementing to zero. `stabbed` picks `stabkill` vs `stabbed` by testing `health === 0` after
  the damage — so decrementing to zero makes a fatal blow look like a wound. My first version had
  both wrong; the test was right.
- The animation **is** the state machine: every verb is frame-gated, and a strike on any
  non-strike frame does nothing at all.

**Done (M6b):**
- [x] **`Simulation`** — the tick moved into `PoPCore`, so a duel runs with no window
- [x] **Actors in `World`** — the Prince at index 0, guards after; the shared RNG lives there too
- [x] **Guards spawned from `guards{}`** — `charName` from type and colour, skill, health,
      direction, and the `active`/`visible`/`sneak` flags
- [x] **Guards rendered**, each from its own sprite atlas
- [x] Verified in game: the guard in room 21 draws, then advances, closing from distance 48
      to 16 while the Prince runs at him

**Found:**
- **`shadow.json` and `vizier.json` have no frame 0** — frames start at 1. `ActorState` begins at
  `charFrame = 0`, so a shadow's initial frame is not a real sprite. Never displayed in practice
  (the first `CMD_FRAME` replaces it), and `makeNode` returns nil for a missing texture just as
  Phaser renders nothing. Pinned by a test.
- Swift's exclusivity rules forbid assigning through `world.actors[i]` while handing `world` to
  a function, so the tick copies each actor out and back. The copy is the honest fix.

**Done (M6c):**
- [x] **Sword overlay** — `Fighter.updateSwordPosition`, drawn at z 21 from the `sword` atlas
- [x] **Level chaining** — `CMD_NEXTLEVEL` → effect → `GameCoordinator` loads the next level
- [x] Health and max health carry across a level change; finishing level 14 ends the run
- [x] Added a **`PoPHostTests`** target; `nextLevel(after:)` is a pure `nonisolated` function

**Found:**
- The sword's frame comes from `swordtab[fsword - 1].id`, a **1-based positional** index — the
  clearest confirmation of open question 9.
- Level 1's Prince, running at a guard with his sword **sheathed**, dies on contact. That is
  `stab`'s `charName === "kid" && !swordDrawn` branch, and it is working as intended.
- The sword atlas is not named for any actor, so a test that collected "available frames" per
  `charName` missed it. Worth remembering when adding an atlas.

**Done (M8a):**
- [x] **`GameClock`** — sixty minutes, simulated ticks, and the three readout cases
- [x] **`BitmapFont`** — parses `prince.fnt` (96 glyphs, BMFont XML) and lays text out
- [x] **`HudRenderer`** — the bar, the life pips (both sides, tinted), the level title and the
      clock text
- [x] Rendered in the host, verified on screen: "LEVEL 1" centred, three pips on the left

**Found:**
- **`getDeltaTime().seconds` is the seconds FIELD, not total elapsed seconds**
  (`Math.floor(diff / 1000) % 60`). So `getRemainingSeconds` counts within the current minute and
  resets to 60 each time one rolls over — which is why the bar jumps from "5 MINUTES LEFT" to
  "59 SECONDS LEFT" with nothing in between. I assumed total seconds twice before checking.
- The clock is **wall-clock** in the reference. The port counts ticks: identical under a fixed
  timestep, no drift on dropped frames, and reproducible from a seed.
- A space is a **1x1 glyph with an advance of four**, so the pen moves without anything being
  drawn.

**Done (M8b):**
- [x] **`SoundEffect`** (33 cases) and **`MusicTrack`** (8), raw values and filenames taken from
      `Preloader.js`
- [x] **`ActorEffect.sound`** — the transport. Call sites sit wherever the reference calls
      `game.sound.play`, and the sink is an explicit `inout [ActorEffect]`
- [x] **Opcode and verb hooks** — `TAP`, `engarde`/`turnengarde`, `strike`/`stab`/`checkFight`, and
      `FallCycle.land`'s four landing sounds
- [x] **Mechanisms** — `Gate.update()`, `ExitDoor.update()` and `LooseBoard.update()` return
      `SoundEffect?`; `LevelState.update()` collects them into one array per tick
- [x] **`Fighter.updateFallingBlocks`** — the fifth floor of a fall, kid only
- [x] **`AudioPlayer`** — the only AVFoundation import in the project. Lazy decode, three-voice
      round-robin per effect, looping music, silent on failure
- [x] **Level 1's Danger theme**, 800 ms in, gated on the map's `prince.danger`
- [x] Flags: `--mute`, `--no-music`, `--no-audio`, `--volume`; `--trace` prints sounds by filename

**Found:**
- **`FallingFloorLands` is not a landing sound.** It plays in mid-air five floors down — it is the
  Prince's own cry — and only for `charName == "kid"`. The name is a trap; I had it wired to the
  loose board.
- **`Loose.sweep` plays `Sounds[0]`, a *shake* variant**, not a landing sound. The board's collapse
  and its rattle are the same sample family.
- **`AVAudioPlayer` is single-shot.** Calling `play()` on a player that is already playing restarts
  it, so footsteps two ticks apart cut each other off. Voices, not one player.
- **`MusicTrack` collides with AudioToolbox's `MusicTrack`** the moment AVFoundation is imported.
  Has to be spelled `PoPCore.MusicTrack` in host code.
- **`#expect`'s message is a `Comment`, not a `String`** — a built string has to go through
  `Comment(rawValue:)`.
- The reference plays only **one** cue on a level's first tick (level 1's Danger). The other two
  Danger calls belong to the shadow encounters on levels 5 and 6, which are not ported.

**Done (M3c):**
- [x] **`ScreenRect`** — `Phaser.Rectangle.intersects` transcribed, including the two things that
      are easy to read backwards: an empty rectangle never intersects, and edge-touching rectangles
      **do**
- [x] **`checkBarrier`** — all four branches: the freefall into a two-tile barrier, walking into a
      barrier, the column-ahead probe, and the mirror from behind
- [x] **`bump` / `setBump` / `bumpSound` / `bumpFall`** and `alignToFloor`
- [x] **`Behaviour.step`’s** chopper, mirror and gate branches, which trim `px` rather than clamping
      it to zero
- [x] `Behaviour.update` takes the interpreter, because a verb *may* end the tick with
      `processCommand`
- [x] **Open question 11 closed** — see `ARCHITECTURE.md` §7.9.10

**Found:**
- **The question was wrong, not just unanswered.** Open question 11 assumed there was an engine-unit
  equivalent to find. There is not, because `checkBarrier` is not physics — it is screen-space
  collision over cel sizes, and the cels are in the atlas JSON. Once `SpriteMetrics` existed the
  answer was to transcribe, `roomX * 32 + 40` and all.
- **`Tile.Base.getBounds` and `getBoundsAbs` disagree on purpose.** One is a 4-pixel strip forty
  pixels into the cell — eight past the cell’s end. The other is the full cel at the tile origin,
  overhang included. `checkBarrier` asks for both.
- **`Phaser.Rectangle.intersects` counts edge-touching as intersecting.** The separation tests are
  strict, so an equal `right` and `x` is *not* separated. My first test asserted the opposite; the
  code was right.
- **`Kid.bumpSound` is rate-limited by `bumpTimer`.** Without it, a Prince held against a wall plays
  the thud every tick, which is a buzz rather than a bump.

**Still open (M6d):**
**Done (M6d):**
- [x] **The splash** — shown for two ticks on a wound, suppressed for the four self-bloodying
      deaths, tinted for guards, drawn five units higher for a crouching hit
- [x] **The time-up hand-off** — `ActorEffect.timeUp`, and the host stops the run
- [x] **The medium landing**, which was silently broken (see below)

**Found — and this is the one that matters:**
- **`ActorState.action` was a stored property.** In the reference, assigning it rewinds the
  sequence cursor. `startFall` was the one place that assigned `action` without going through
  `beginAction`, so it resumed the new sequence mid-way and a `stepfall` skipped its own `ACT 3`.
  The cascade: `actionCode` stayed 0 → `checkFloor` took its *standing* branch → it called
  `startFall` again every tick → which zeroed `fallingBlocks` every tick. **Medium landings never
  happened and no fall ever did damage**, from M2 to M6d. Fixed by making the setter do the reset,
  not by patching `startFall`.
- **`Kid.land`'s medium landing was inlined as `health -= 1`.** The reference calls `damageLife(true)`,
  which calls `die` at one health. A Prince on his last life was landing, dropping to zero health,
  and carrying on alive.
- **`die` does not show a splash.** Only the `DIE` opcode, `stabbed` and `damageLife` do — putting it
  in `die` makes a spike death bleed onto the spikes.
- **The splash order matters**: `showSplash` is called *before* the action changes, because it
  refuses the four self-bloodying death animations.
- **Sixty minutes is 43,200 ticks**, not 3,600. And the final minute reads `remainingMinutes == 1`,
  which is why the bar switches to a seconds readout for it.

**Still open (small):**
- [ ] **The shadow overlay** — level 5/6 only, and it needs a mirror-merge effect that is not ported
- [ ] **`floorStopFall`** — a board landing and becoming debris is not modelled (visual only)
- [ ] **Cutscenes** (open question 5) — the title screen, the level 1 prologue, the ending
**Done (ledges):**
- [x] **`tryGrabEdge`** — the two probes, the reach asymmetry, and the fall-length and tapestry
      exclusions
- [x] **`grab`** — pulled onto the ledge, fall stopped, loose board above shaken, `grabWait` armed
- [x] **`checkLedgeSwing`** — the swing-to-momentum mechanic, with the float potion's wider drift
- [x] The fall-action branch of `updateBehaviour`, and `climbup`/`climbdown`'s fall conditions
- [x] `distanceToTopFloor`, `stopFall`

**Found:**
- **The grab window is a window in *time*, not just a place.** `distanceToTopFloor >= -50` reads
  `-63` for a Prince resting on the row below, so a fall only has a few ticks in which catching is
  possible at all. That is why `stepfall` gets three extra units of reach — it is the slowest fall
  and spends the fewest ticks in the window.
- **`checkLedgeSwing` is the only place `charX` is fractional.** It adds **1.5** a tick. The port
  carries the half in `ledgeSwingHalves`, so the accumulated whole units are exact.
- **`grabWait` is 500 ms**, not a tick count, in the reference — six ticks at 1/12 s.
- **Verified live**: level 1 room 12, walking off the ledge at column 4 with the action key held,
  he catches the ledge at tick 18 and the loose board above him shakes. That is the level-1 opening,
  which the port could not previously play.

### M6 — Combat and guards *(original scope)*
- [ ] `Guard` with skill tables from `Enemy.js` — transcribe all twelve columns verbatim
- [ ] `applyStrength` scaling; guard health formula; colour tinting
- [ ] `Swordfight`: distance thresholds `minHurtDistance`/`maxHurtDistance`, frame-ID gates
- [ ] `Autocontrol` protocol: player input vs guard tables vs demo playback
- [ ] Confirm the combat tick rate (open question 1) against `SDLPoP/src/seg000.c`
- [ ] **Optional oracle:** install SDL2, build SDLPoP, record a replay, diff a route

### M7 — Hazards and mechanisms
- [x] Gates, raise/drop/stuck buttons, loose boards, potions, spikes, exit door
- [x] Event triggers and `events[].next` chaining
- [x] Level 1 completable start to finish
- [x] **Choppers** (M7c-2)

### M8 — Audio, UI, flow
- [x] The mp3 bank and the sound channel *(M8b; `AVAudioPlayer`, not `AVAudioEngine` — the bank is
      mp3, and an engine buys nothing over forty decoded one-shots)*
- [x] Health pips, timer, BMFont text *(M8a)*
- [ ] `Space` to reveal remaining time
- [ ] `GameFlow` `GKStateMachine`
- [ ] Title, cutscenes (`Cutscene.js`), ending
- [ ] The full 14-level chain

### M9 — Polish *(complete)*
- [x] **`Scripts/make-app.sh`** — assembles `Prince.app`: release binary, `Info.plist`,
      the SwiftPM resource bundle, an icon, an ad-hoc signature. 9 MB
- [x] **Icon** — centre-cropped from the game’s own `cover.png` through the ten sizes
      `iconutil` wants
- [x] **Key bindings** — JSON in Application Support, written on first launch, editable, with an
      Options menu to open and to reset it
- [x] **Distribution decided and documented** — see `ARCHITECTURE.md` §7.13

**Notes:**
- **No Xcode project**, despite the original plan. The risky part of this port is the *simulation*,
  and SwiftPM is what makes the headless test suite run in half a second. An Xcode project would put
  that behind a GUI and buy nothing: the bundle is twenty lines of `cp` either way.
- **The resource bundle must go in `Contents/Resources`**, not next to the binary — that is
  where `Bundle.module` searches. Getting it wrong gives an app that launches and immediately
  dies on a missing level file. Verified by running the bundle.
- **The signature is ad hoc**, so the app runs on the machine that built it and not elsewhere
  without an override. Notarising needs a Developer ID, which is a decision about the project
  rather than about the code. Left honestly undone rather than faked.
- **Shift is a modifier**, so it never arrives as a key-down in a local event monitor. It is
  sampled from `NSEvent.modifierFlags`, which also keeps it right across focus changes.

---

### What the screen actually shows ✅ *complete*

Two rendering faults, reported as one: *walls and gates at the left border are not drawn; the gate
can be heard opening but not seen, and cannot be walked past.*

- [x] **Neighbouring rooms are drawn.** `LevelBuilder` builds every room into one display list and
      lets the camera crop, and a 60 px cel in a 32 px cell means the left neighbour's last column
      owns the leftmost 28 px of every screen. `RoomRenderer.strips` now emits the bands that
      reach: left column 9, above row 2, below row 0 — in the reference's build order.
- [x] **The room sits at the top of the screen.** `LevelScene.roomTopY` was `roomHeight`, which
      fitted the 189 px grid above the status bar and dropped every room by 11 px: a black band
      across the top and the floor buried under the bar. It is `screenHeight`.

**Notes:**
- **The gate was never missing, it was off-screen.** A gate one room to the left has its back panel
  at `x = -32` and its 8 px front panel at `x = 0`; the port drew neither, so the Prince walked into
  something he could hear and not see. `Level.js#checkGates` looks like the code that hides gates,
  but `Gate.isVisible` only mutes their sound.
- **The seed of a wall drawn from the left room is the left room's**, `row * 10 + column + thatRoom`.
  Passing the drawn room's number would name a frame that exists and looks wrong.
- **Order matters where the overhangs collide.** `LevelBuilder` walks the map's bottom row first, so
  below precedes left and above comes last; the strips are emitted in that order.
- **Open question 4 is closed by this.** `UI_HEIGHT = 8` and the room's grid is *not* fitted above
  it — the cels' 3 px tail ends exactly on the bar.

---

### Walking through a gate that is standing open ✅ *complete*

Reported as: *first level, a gate to the left opens but the prince can not walk pass it.*

- [x] **A gate's collision rectangle shrinks as it rises.** `Gate` is the only tile class in the
      reference that overrides `Base.getBounds`, and the port was building `Base`'s flat 4 x 63
      strip for every tile alike. `screenBounds`/`screenBoundsAbs` now take the gate's position,
      and `checkBarrier` supplies it from `world.trob(x:y:room:)?.gate?.position`.

**Notes:**
- **`checkBarrier` treats every gate as a barrier, on purpose.** `Tile.Base.isBarrier` answers yes
  for a gate whatever its position; the open/closed test lives in `Gate.canCross`, which
  `nearBarrier` and `canStep` consult. So the *rectangle* is the only thing that can let an open
  gate through, and reading `Base`'s version made a raised gate as solid as a shut one.
- **The strip is pinned to the top of the cell.** `height = 63 - 10 + posY - 4` is 49 shut and 2
  fully raised, so a raised gate is a sliver against the ceiling and an actor at floor level has
  nothing left to intersect.
- **`Gate` is the only override.** `grep getBounds reference/PrinceJS/src/tiles/*.js` returns
  `Base` and `Gate` and nothing else, so the exit door, the loose board and the chopper all keep
  the plain rectangles.
- **The reproduction is a walk, not a unit test.** Level 1's room 5 row 0 has a raise button at
  (4,0), a gate at (5,0) and another button beyond it; the regression test drives the real
  `Simulation` and asserts he is past column 5 when the gate reaches -47.

---

### One keyboard for the process ✅ *complete*

Reported as: *on app start sometimes keys don't respond, sometimes they do.*

- [x] **One `KeyboardInput`, created once in `main.swift`.** A local event monitor that returns
      `nil` ends the monitor chain, and `KeyboardInput` returns `nil` for every key it is bound to
      so AppKit does not beep. The throwaway scene built for `--trace`/`--screenshot` made a
      second one, and whichever monitor AppKit called first took the arrows.
- [x] **The diagnostic scene is only built when a diagnostic flag asks for it.** The interactive
      run builds its own through `GameCoordinator`.
- [x] **Held keys are released when the app resigns active**, so a key held across a switch away
      does not leave the Prince walking on his own when the player comes back.

**Notes:**
- **`--trace` and `--screenshot` were the cause, and the app looked innocent.** Both instances
  were always constructed; what differed was whether the throwaway global was still alive when
  the keys arrived:

  | Build | Result |
  |---|---|
  | `swift run Prince` (debug) | the throwaway's monitor is first, swallows every arrow, game gets nothing |
  | `Prince of Persia.app` (release) | the throwaway was dropped early, so the real input works |

  "Sometimes" was the build configuration. Found by instrumenting the monitor, not by reading.
- **A local monitor is a process-wide side effect owned by a per-instance object**, which is the
  shape of the bug. `KeyboardInput.listening` now drops the swallow when another instance is
  alive — a courtesy is not worth somebody else's key.
- **No unit test covers this.** It needs a real event loop and a real key event; the guards are
  the single owner, the counter, and the note on the class. Both build configurations were run by
  hand, with a synthetic arrow from `osascript`.

---

## Verification commands

```bash
swift build                      # compile everything
swift test                       # headless simulation tests — the fast loop
swift run Prince                 # launch the game

# Diagnostics. --dump-frame is the one that caught the atlas origin bug: it renders a single
# atlas frame at 1:1 so the slice can be compared against the source PNG.
swift run Prince --trace --level 1
swift run Prince --screenshot out.png --level 1 --ticks 5
swift run Prince --screenshot out.png --level 1 --hold right --ticks 40
swift run Prince --dump-frame dungeon_1 --screenshot frame.png --atlas dungeon

# Audio. --trace labels every sound by filename, never by position.
swift run Prince --trace --level 1 --hold right --ticks 200 | grep sound:
swift run Prince --no-audio --level 1     # silent, for a screen recording

# keep PoPCore honest (Law 5)
grep -rE "import (SpriteKit|AppKit|GameplayKit|AVFoundation)" PrinceOfPersia/Sources/PoPCore/ \
  && echo "LAW 5 VIOLATED" || echo "core is clean"
```

---

## Session hygiene

- **Update the Status table and tick the task board before ending a session.** This file is how
  the next session knows where things stand.
- **Record new decisions in `ARCHITECTURE.md` §12** with a one-line rationale.
- **Resolve open questions in `ARCHITECTURE.md` §10 when you answer them** — move the answer
  into the relevant subsystem section and delete the question.
- **Any transcribed magic number gets a comment naming its source**, e.g.
  `// Fighter.js#checkFight — maxHurtDistance`.
- **When PrinceJS is ambiguous, read SDLPoP.** Never guess at behaviour.
