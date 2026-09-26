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
| **Current milestone** | **M0 — not started** |
| **Last completed** | — |
| **Blocked on** | nothing |
| **Open questions** | 7, listed in `ARCHITECTURE.md` §10 |
| **Next action** | Create the SwiftPM package skeleton (`ARCHITECTURE.md` §5) |

---

## Task board

Tick these off as they land. Full "done when" criteria are in `ARCHITECTURE.md` §9.

### M0 — Skeleton
- [ ] `git init`; add `.gitignore` containing `reference/`, `.build/`, `.DS_Store`, `*.xcodeproj`
- [ ] Create `PrinceOfPersia/Package.swift` with targets `PoPCore`, `PoPHost`, `Prince`, `PoPCoreTests`
- [ ] `swift-tools-version: 6.0`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`
- [ ] Copy game assets from `reference/PrinceJS/assets/` into the package's resources
      (`gfx`, `maps`, `anims`, `sfx`, `music`, `font`, `cutscenes`)
- [ ] Empty `SKScene` in a 640 × 400 window, `scaleMode = .aspectFit`, `filteringMode = .nearest`
- [ ] Confirm: `swift test` passes and `swift run Prince` opens the window

### M1 — Data layer
- [ ] `LevelData`, `RoomData`, `Tile`, `GuardSpawn`, `EventTrigger`, `PrinceSpawn` as `Codable` + `Sendable`
- [ ] `TileKind` enum from `reference/PrinceJS/src/Level.js` (29 values, §6.2)
- [ ] `AnimationTable` + `FrameDef` decoding, including `fcheck` hex-string → `UInt8`
- [ ] `FrameCheck` bitfield decode (bits 0–4 foot, 5 thin, 6 check, 7 parity — §7.3)
- [ ] Decode tests: every level JSON parses; each room has exactly 30 tiles; bit tests pass

### M2 — Sequence VM ⚠️ *the milestone that de-risks everything*
- [ ] `Opcode` enum, full 256-entry table with `NOOP` default (§7.2)
- [ ] Transcribe opcode bodies from `Actor.js` / `Fighter.js` / `Kid.js` / `Enemy.js`
- [ ] `ActorState`: `charX/Y`, `charBlockX/Y`, `charFace`, `charFrame`, `action`, `_seqpointer`
- [ ] `SequenceProgram.tick()` implementing the `while processing` loop — runs until a frame is emitted
- [ ] Settle the coordinate representation (open question 3) and record it in `ARCHITECTURE.md`
- [ ] Tests: `startrun`, `stand`, `runjump` step to expected frame/position with **no renderer**

### M3 — Movement and tile queries
- [ ] `TileQuery`: `checkFloor`, `checkBarrier`, `checkButton`, `checkSpikes`, `checkChoppers`, `checkRoomChange`
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
