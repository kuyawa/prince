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
| **Current milestone** | **M3 — movement and tile queries** *(in progress)* |
| **Last completed** | **M3a — world, physics, tiles.** 92 tests pass. Open question 8 **closed** |
| **Blocked on** | nothing. M3b remaining: `checkBarrier`, `updateBehaviour`, cross-room tile lookup |
| **Open questions** | 9, listed in `ARCHITECTURE.md` §10 |
| **Next action** | M3b: `checkBarrier` (120 lines) and `updateBehaviour` (254 lines, the input layer) |

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

**Still open (M3b) — these are bigger than the plan assumed:**
- [ ] `checkBarrier` — `Kid.js:600-719`, **120 lines**: bumping, ledge grabs, `grab`, `bumpFall`
- [ ] `updateBehaviour` — `Kid.js:237-490`, **254 lines**: the entire input/control layer
- [ ] `checkButton`, `checkSpikes`, `checkChoppers` — need the trob (interactive tile) layer
- [ ] Cross-room tile resolution (`Level.js#getRoomX`/`#getRoomY`) — open question 10
- [ ] Kid's own `checkRoomChange` (the screen-edge version) distinct from Fighter's
- [ ] Preserve the **call order** from `Enemy.js#updateActor` — the order is behaviour
- [ ] `LCG` (MSVC `rand()`, bit-exact, `UInt32` wrapping) + tests against the reference formula
- [ ] `Ticker`: fixed timestep accumulator, clamped catch-up, 12 Hz / 10 Hz
- [ ] Headless trace: Prince walks, jumps, falls, lands correctly

### M4 — Rendering
- [ ] `AtlasLoader`: TexturePacker JSON → `SKTexture(rect:in:)` (**not** `SKTextureAtlas`)
- [ ] `RenderDescription` / `SpriteInstance` as the sim→render contract (§7.9)
- [ ] Room draw: background, foreground, wall-pattern generation via the LCG
- [ ] Room camera, integer scaling, nearest-neighbour filtering
- [ ] Level 1 on screen, Prince walking around it

### M5 — Level graph and transitions
- [ ] `RoomGraph`: room grid from `size`, `id == -1` holes, derived `links` (§6.1)
- [ ] Room transitions (`CMD_UP`/`CMD_DOWN`, `Kid.js` `charY += 189` offset)
- [ ] Prince spawn from `prince{}`; level load from `guards{}` and `events{}`
- [ ] Level 1 traversable end to end

### M6 — Combat and guards
- [ ] `Guard` with skill tables from `Enemy.js` — transcribe all twelve columns verbatim
- [ ] `applyStrength` scaling; guard health formula; colour tinting
- [ ] `Swordfight`: distance thresholds `minHurtDistance`/`maxHurtDistance`, frame-ID gates
- [ ] `Autocontrol` protocol: player input vs guard tables vs demo playback
- [ ] Confirm the combat tick rate (open question 1) against `SDLPoP/src/seg000.c`
- [ ] **Optional oracle:** install SDL2, build SDLPoP, record a replay, diff a route

### M7 — Hazards and mechanisms
- [ ] Gates, raise/drop/stuck buttons, loose boards, choppers, potions, spikes, exit door
- [ ] Event triggers and `events[].next` chaining
- [ ] Level 1 completable start to finish

### M8 — Audio, UI, flow
- [ ] `AVAudioEngine` with the mp3 bank; `CMD_TAP` sound hooks
- [ ] Health pips, timer, `Space` to reveal remaining time, BMFont text
- [ ] `GameFlow` `GKStateMachine`
- [ ] Title, cutscenes (`Cutscene.js`), ending
- [ ] The full 14-level chain

### M9 — Polish
- [ ] Xcode project for a signed `.app` bundle, icon, Info.plist
- [ ] Keybinding configuration
- [ ] Decide on distribution (see licensing in `ARCHITECTURE.md` §2)

---

## Verification commands

```bash
swift build                      # compile everything
swift test                       # headless simulation tests — the fast loop
swift run Prince                 # launch the game

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
