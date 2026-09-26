# Architecture — Prince of Persia for macOS in Swift

**Status:** design settled, no code written yet.
**Target:** macOS 26 / Swift 6.3 / Xcode 26.6, Apple silicon.
**Goal:** a pixel-faithful, native-Swift Prince of Persia (1989, DOS lineage).

---

## 1. The one-line thesis

> **Port the *game* exactly. Rewrite the *engine* completely.**

Prince of Persia's behaviour lives in a small data-driven virtual machine. Its host
(rendering, input, audio, scene flow) lives in Phaser 2.6.2 — a dead 2017 engine welded
into the logic. These two halves have **opposite** correct answers for "should I port this
or rewrite it", and almost every way this project fails is a failure to keep them apart.

---

## 2. Ground truth

Three references are cloned under `reference/`. They do **not** have equal authority.

| Path | What it is | Role |
|---|---|---|
| `reference/PrinceJS` | JS/Phaser reimplementation of the DOS version. ~8.2k LOC. **The Unlicense (public domain).** Ships all assets pre-extracted as PNG + JSON. | **PRIMARY PORT SOURCE** |
| `reference/SDLPoP` | C port built from a disassembly of `PRINCE.EXE`. ~32k LOC. GPLv3. Actively maintained (Dec 2025). Needs original DOS data files. | **BEHAVIOURAL ORACLE** |
| `reference/POP-AppleII` | Mechner's original 6502 assembly (1985–89), plus original sprite data and level files. | **HISTORICAL REFERENCE ONLY** |

### Why PrinceJS is the port source

- **8.2k LOC vs 32k LOC.**
- JS objects + GC map to Swift classes + ARC nearly 1:1. SDLPoP's C deliberately preserves
  the DOS memory model — segment files `seg000.c`…`seg009.c`, global byte arrays,
  `word`/`dword` typedefs, near/far pointers. Porting that imports 1989 into your type system.
- **Public domain.** SDLPoP is GPLv3; porting its code makes your app GPLv3.
- **Assets already extracted.** `assets/gfx/*.png` + TexturePacker JSON, `assets/maps/*.json`,
  `assets/anims/*.json`, music, sfx, font, cutscenes. SDLPoP requires writing a
  `PRINCE.EXE`/`.DAT` binary decoder in Swift before anything renders — a sub-project
  hiding inside `options.c` and `seg009.c`.

### Why SDLPoP is still essential

It is the tiebreaker when Swift and PrinceJS disagree, and its `doc/` folder is the best
existing documentation of the game's internals:

- `reference/SDLPoP/doc/internals_sequence-table.txt` — autocontrol vs control vs anim, chtabs, frame units
- `reference/SDLPoP/doc/tiles.md` — every tile+modifier combination
- `reference/SDLPoP/doc/replay_format.txt` — replay format, for differential testing

### Why the Apple II source is not a port source

It is 6502 assembly. It is a historical artifact. Read `MOVER.S` and `SEQDATA.S` to
understand *why* the sequence table has the shape it does; do not translate them.

### Licensing

- **Code:** PrinceJS is public domain (Unlicense). Port freely.
- **Assets:** sprites, levels, music and the *name* remain Ubisoft's. Mechner says so
  explicitly in `reference/POP-AppleII/README.md`.
- **This is a personal/learning project.** Keep assets swappable (they already are — levels
  and atlases are plain JSON/PNG) so replacing them later is a content job, not a code job.

---

## 3. The core insight: PoP is a virtual machine, not a platformer

This is the fact that determines the entire architecture. **Read this section twice.**

The Prince is not *simulated*. He is *interpreted*.

- There is **no gravity constant and no velocity accumulator**. A jump is not integrated
  from forces — it is a sequence program that assigns frame-relative offsets.
- Collision is **not a general solver**. It is a fixed list of bespoke tile predicates called
  in a specific order, and that order is itself part of the behaviour.
- A guard's "AI" is **not a state machine or behaviour tree**. It is a hand-tuned
  **probability table** compared against random values, plus timers.

```js
// reference/PrinceJS/src/Enemy.js — the twelve columns are the twelve difficulty levels
Enemy.STRIKE_PROBABILITY  = [61, 100, 61, 61, 61, 40, 100, 150, 0, 48, 32, 48];
Enemy.BLOCK_PROBABILITY   = [0, 150, 150, 200, 200, 255, 200, 250, 0, 255, 255, 255];
Enemy.ADVANCE_PROBABILITY = [255, 200, 200, 200, 255, 255, 200, 0, 0, 255, 100, 100];
Enemy.REFRAC_TIMER        = [16, 16, 16, 16, 8, 8, 8, 8, 0, 8, 0, 0];
```

### Consequence: reject ECS as the top-level architecture

ECS earns its keep with many heterogeneous entities and cache-friendly iteration over
homogeneous component arrays. PoP has **at most ~8 actors on screen**. There is no
performance argument, so the only question is whether ECS clarifies the design — and it does
not, because it **inverts the control flow the game depends on**.

In ECS, systems own behaviour and entities own data. In PoP, an actor's opcodes **reach out
and mutate the world** — open a gate, trigger a room transition, kill an opponent, change the
music. Force the sequence VM into ECS and you get one `SequenceSystem` containing all the
logic: ECS in name only, plus indirection.

**Instead:** a data-driven actor + sequence interpreter, with lightweight Swift protocol
composition where composition genuinely earns its keep (`Autocontrol`, `Renderable`,
`Swordfighter`). Composition, not an entity registry.

### Consequence: reject Glide Engine

Checked 2026: `cocoatoucher/Glide`, 505 stars, last real code commit **July 2023** (the Dec
2024 push was a README edit), `swift-tools-version:5.5`, `swiftLanguageVersions: [.v5]`.

Adopting it pins the project to **Swift 5 language mode** — the exact opposite of "latest
Swift". And its value proposition is a *physics-driven* side-scroller: `PhysicsComponent`
with gravity, jump velocity and contact-side resolution. PoP has none of that, so you would
fight your engine from day one. **Read it for its contact-side collision patterns; do not
depend on it.**

---

## 4. The Laws

Non-negotiable. Violating any of these is how this project dies.

1. **Do not "optimise" the simulation.** Exact fidelity is the specification. Every offset,
   threshold and probability in the reference is a behavioural contract with 1989.
2. **No ECS, no behaviour trees, no `GKRuleSystem`.** The sequence VM is the architecture.
3. **Never use `GKRandomSource` or `Math.random`-equivalents.** Use the bit-exact LCG (§7.7).
   Replay determinism depends on it.
4. **Fixed timestep.** 1/12 s normally, 1/10 s while fighting. Never drive the sim from vsync.
5. **`PoPCore` must not import SpriteKit, AppKit, GameplayKit or AVFoundation.** Enforced by test.
6. **The simulation never touches the keyboard.** It consumes `Intents` values (§7.10).
7. **One `actor` per character is forbidden.** Actor hops have no guaranteed ordering and
   destroy reproducibility. The sim is single-threaded and ordered.
8. **Presentation is disposable.** The sim emits a render description; the host draws it.

---

## 5. Module layout

```
Prince/                              ← workspace root
├── ARCHITECTURE.md                  ← this file
├── PROMPT.md                        ← kickoff prompt + task board
├── reference/                       ← research clones (git-ignore this)
└── PrinceOfPersia/                  ← the Swift package
    ├── Package.swift
    ├── Sources/
    │   ├── PoPCore/                 ← NO SpriteKit. The faithful port. Headlessly testable.
    │   │   ├── Model/               LevelData, RoomData, Tile, TileKind, spawns, events
    │   │   ├── Anim/                AnimationTable, FrameDef, Opcode, SequenceProgram (the VM)
    │   │   ├── Actor/               ActorState, FrameCheck, Fighter, Prince, Guard
    │   │   ├── Sim/                 World, RoomGraph, TileQuery, LCG, Ticker
    │   │   ├── Combat/              Swordfight resolution
    │   │   └── Tiles/               Gate, Button, Loose, Chopper, Potion, Spikes, ExitDoor
    │   ├── PoPHost/                 ← SpriteKit + GameplayKit + AVFoundation
    │   │   ├── Render/              AtlasLoader, RenderDescription, LevelScene, SpriteMap
    │   │   ├── Input/               KeyboardInput → Intents
    │   │   ├── Flow/                GameFlow (GKStateMachine)
    │   │   └── Audio/               AudioEngine
    │   └── Prince/                  ← @main executable target
    └── Tests/PoPCoreTests/
```

### Package.swift sketch

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrinceOfPersia",
    platforms: [.macOS(.v26)],          // Swift 6.3 toolchain on macOS 26.6; drop to .v15 for an older floor
    products: [.executable(name: "Prince", targets: ["Prince"])],
    targets: [
        .target(name: "PoPCore"),                                   // zero dependencies, by design
        .target(name: "PoPHost", dependencies: ["PoPCore"]),
        .executableTarget(name: "Prince", dependencies: ["PoPHost"]),
        .testTarget(name: "PoPCoreTests", dependencies: ["PoPCore"]),
    ],
    swiftLanguageModes: [.v6]
)
```

**Why SwiftPM rather than an Xcode project to start:** `swift test` gives a sub-second
headless test loop over the simulation, which is where all the risk lives. Asset loading goes
through `Bundle.module`. Add an Xcode project later *only* when you need a signed `.app`
bundle, asset catalog and notarisation.

---

## 6. Data model

All of it is already extracted in `reference/PrinceJS/assets/`. Decode with `Codable` into
immutable `Sendable` structs.

### 6.1 Level — `assets/maps/level<N>.json`

```jsonc
{
  "number": 1,
  "name": "Cell",
  "size":   { "width": 9, "height": 3 },     // room grid, in rooms
  "type":   0,                                // 0 = dungeon, 1 = palace
  "room":   [ { "id": 22, "tile": [ { "element": 20, "modifier": 0 }, ... 30 tiles ] } ],
  "guards": [ { "room": 21, "location": 7, "skill": 0, "colors": 2,
                "type": "guard", "direction": -1 } ],
  "events": [ { "number": 1, "room": 12, "location": 10, "next": 0 } ],
  "prince": { "location": 1, "offset": -7, "turn": false, "room": 1, "direction": 1 }
}
```

Key facts:

- `room[].id` is the **room number**, or `-1` for "no room here".
- Rooms are written row-major. `reference/PrinceJS/src/LevelBuilder.js` walks
  `index = y * width + x` and derives neighbours:
  `links.left/right/up/down = getRoomId(x±1, y±1)`. **Links are computed, never stored.**
- Each room holds exactly **30 tiles** — a 10 × 3 grid, row-major.
- `location` is a tile index `0..29` within a room. `location 10` = column 0, row 1.
- `events[].next` is the event number to chain to, or `0` for none.

### 6.2 Tile kinds — `reference/PrinceJS/src/Level.js`

`element` is the tile kind; `modifier` is the variant byte. Full table as of the port source:

```
 0 SPACE            8 BOTTOM_BIG_PILLAR   16 EXIT_LEFT        24 BALCONY_RIGHT
 1 FLOOR            9 TOP_BIG_PILLAR      17 EXIT_RIGHT       25 LATTICE_PILLAR
 2 SPIKES          10 POTION              18 CHOPPER          26 LATTICE_SUPPORT
 3 PILLAR          11 LOOSE_BOARD         19 TORCH            27 SMALL_LATTICE
 4 GATE            12 TAPESTRY_TOP        20 WALL             28 LATTICE_LEFT
 5 STUCK_BUTTON    13 MIRROR              21 SKELETON
 6 DROP_BUTTON     14 DEBRIS              22 SWORD
 7 TAPESTRY        15 RAISE_BUTTON        23 BALCONY_LEFT
```

SDLPoP's `doc/tiles.md` documents the tile+modifier combinations the original engine
supports, including which are SDLPoP-only additions. **The original set is the target**;
SDLPoP-only combos are opt-in extras.

### 6.3 Animation tables — `assets/anims/*.json`

```jsonc
{
  "sequence": {
    "startrun": [ { "cmd": 249, "p1": 1 }, { "cmd": 0, "p1": 1 },
                  { "cmd": 0, "p1": 2 },   { "cmd": 251, "p1": 8 },
                  { "cmd": 0, "p1": 5 },   { "cmd": 255, "p1": "running", "p2": 1 } ]
  },
  "framedef": [ { "fdx": 2, "fdy": 1, "fcheck": "0x00", "fsword": 13 } ]
}
```

Files: `kid.json`, `fighter.json`, `shadow.json`, `vizier.json`, `princess.json`,
`mouse.json`, `sword.json`. `kid.json` alone has **75 sequences**.

### 6.4 Atlases — `assets/gfx/*.png` + `*.json`

TexturePacker format, 46 files. Frame keys are `<charname>-<frameIndex>`, e.g. `kid-102`.

```jsonc
{ "frames": { "kid-0": { "frame": {"x":101,"y":67,"w":11,"h":24},
                         "rotated": false, "trimmed": false,
                         "spriteSourceSize": {...}, "sourceSize": {...},
                         "pivot": {"x":0.5,"y":0.5} } },
  "meta": { "image": "kid.png", "size": {"w":123,"h":2021}, "scale": "1" } }
```

Map to `SKTexture(rect:in:)` over a single `SKTexture` per atlas — **not** `SKTextureAtlas`,
which expects Xcode's `.atlas` layout, not TexturePacker JSON.

### 6.5 Other assets

| Path | Format | Notes |
|---|---|---|
| `assets/music/*.mp3` | MP3 | 12+ tracks; original MIDI-derived |
| `assets/sfx/*.mp3` | MP3 | ~40 numbered effects |
| `assets/font/prince.fnt` + `prince_0.png` | BMFont | bitmap font for the UI |
| `assets/cutscenes/scene*.json` | JSON | intro/ending sequences |

---

## 7. Subsystem specifications

### 7.1 Geometry constants

Straight from `reference/PrinceJS/src/Boot.js`:

```
BLOCK_WIDTH  = 32      SCREEN_WIDTH  = 320      SCALE_FACTOR = 2
BLOCK_HEIGHT = 63      SCREEN_HEIGHT = 200      UI_HEIGHT    = 8
ROOM_WIDTH   = 320     ROOM_HEIGHT   = 189      (= 63 × 3)
```

**Tiles are 32 × 63 — not square.** This is the most common early bug in a PoP port. A room is
10 × 3 tiles = 320 × 189 px inside a 320 × 200 screen; the bottom 11 px are UI in the original sense.
Confirm the reconciliation against SDLPoP when the status bar is built.

### 7.2 The sequence VM — the heart of the port

From `reference/PrinceJS/src/Actor.js`:

```js
PrinceJS.Actor.prototype.processCommand = function () {
  this.processing = true;
  while (this.processing) {
    let data = this.anims.sequence[this._action][this._seqpointer];
    this.commands[data.cmd](data);
    this._seqpointer++;
  }
};
```

**The loop runs until a `CMD_FRAME` opcode sets `processing = false`.** Non-frame opcodes —
`GOTO`, `CHX`, `CHY`, `TAP`, `ABOUTFACE` — execute *instantly and consecutively* within a
single tick. One tick produces exactly one rendered frame.

All 256 opcodes are pre-registered to `CMD_NOOP`, then overridden. Full table:

| Opcode | Dec | Name | Reg. by | Semantics |
|---|---|---|---|---|
| `0x00` | 0 | `FRAME` | Actor | `charFrame = p1`; reload framedef; **stop the loop** (emits a frame) |
| `0xf1` | 241 | `NEXTLEVEL` | Kid | advance to next level |
| `0xf2` | 242 | `TAP` | Actor (no-op) | sound hook; overridden by Kid and Enemy |
| `0xf3` | 243 | `EFFECT` | Kid | see reference |
| `0xf4` | 244 | `JARD` | Kid | jump/transition room down |
| `0xf5` | 245 | `JARU` | Kid | jump/transition room up |
| `0xf6` | 246 | `DIE` | Fighter | enter death sequence |
| `0xf7` | 247 | `IFWTLESS` | Kid | conditional branch |
| `0xf8` | 248 | `SETFALL` | Fighter | see reference |
| `0xf9` | 249 | `ACT` | Fighter | actor command: input / autocontrol dispatch |
| `0xfa` | 250 | `CHY` | Actor | `charY += p1` |
| `0xfb` | 251 | `CHX` | Actor | `charX += p1 * charFace` |
| `0xfc` | 252 | `DOWN` | Kid | room transition down |
| `0xfd` | 253 | `UP` | Kid | room transition up |
| `0xfe` | 254 | `ABOUTFACE` | Actor | flip facing |
| `0xff` | 255 | `GOTO` | Actor | `_action = p1`; `_seqpointer = p2 - 1` |

Everything else is `NOOP`. Semantics marked "see reference" are **not yet transcribed** — read the
body in `Fighter.js` / `Kid.js` before implementing. Do not guess.

Swift shape: `enum Opcode: UInt8`, a `SequenceProgram` holding the table and a cursor, and a
dispatch `switch` (or a `[UInt8: (inout ActorState, Operand) -> Void]` table mirroring
`registerCommand`). `ACT` (249) is the heaviest — it is the input/autocontrol entry point and
appears as the first operand of nearly every sequence.

### 7.3 Frame definitions and the `fcheck` bitfield

```js
// reference/PrinceJS/src/Actor.js — updateCharFrame()
let fcheck    = parseInt(framedef.fcheck, 16);
this.charFfoot  = fcheck & 0x1f;            // bits 0–4
this.charFthin  = (fcheck & 0x20) === 0x20; // bit 5  thin/edge collision
this.charFcheck = (fcheck & 0x40) === 0x40; // bit 6  check-active flag
this.charFood   = (fcheck & 0x80) === 0x80; // bit 7  half-pixel parity
```

`fdx`/`fdy` are the per-frame draw offsets *within* the sequence; `fsword` is the sword
overlay offset. **Preserve this bitfield exactly** — `fcheck` drives foot placement and
collision extents, and it is stored as a hex string in JSON, so decode `"0x44"` → `UInt8`.

### 7.4 The dual coordinate space

Actors live in **two coordinate systems at once**, and keeping them in sync is a real bug source:

- **Pixel space:** `charX`, `charY` — continuous position.
- **Tile space:** `charBlockX`, `charBlockY` — which tile the actor occupies.

Room traversal mutates the *block* coordinate and offsets the pixel coordinate by a whole room
(`Kid.js`: `charY += 189; charBlockY = 2;` on room-up).

Rendering position, from `updateCharPosition()`:

```js
let tempx = this.charX + this.charFdx * this.charFace;
if ((this.charFood && this.faceL()) || (!this.charFood && this.faceR())) {
  tempx += 0.5;                       // half-pixel parity correction
}
this.x = this.baseX + PrinceJS.Utils.convertX(tempx);
this.y = this.baseY + this.charY + this.charFdy;
```

**Open design question:** simulate in integer pixel space and scale at render time, or in
half-point `CGFloat` space? The `0.5` correction suggests the original used a sub-pixel
accumulator. Decide in M2 and document the choice — do not let it drift.

### 7.5 Combat

Combat is **distance thresholds plus animation-frame identity checks**. From `Fighter.js`:

```js
case "strike":
  if (this.charBlockY !== this.opponent.charBlockY) { ... }   // must share a row
  let minHurtDistance = this.opponent.swordDrawn ? 12 : 8;
  let maxHurtDistance = 29 + (this.opponent.baseCharName === "fatguard" ? 2 : 0);
  if (distance > min && distance < max) { this.opponent.stabbed(); }
  else { this.opponent.blocked = true; this.action = "blockedstrike"; }
```

Plus `frameID(150)`, `frameID(0)` gate checks and `opponentDistance()`. There is no hitbox
geometry — **the numbers are the design.** Copy them verbatim and cite the line in a comment.

### 7.6 Guard AI

Probability tables per §3, scaled by the player's chosen `strength`:

```js
applyStrength(value) = PrinceJS.strength < 100
                     ? Math.ceil((value * PrinceJS.strength) / 100)
                     : value;
```

Plus per-skill timers (`refracTimer`, `blockTimer`, `strikeTimer`) and a skill index derived
from the level. Guard health: `Enemy.EXTRA_STRENGTH[skill] + Enemy.STRENGTH[level.number]`.
Colours come from the level's `guards[].colors` field.

### 7.7 Determinism and the RNG

`reference/PrinceJS/src/LevelBuilder.js` — this is the **MSVC `rand()` LCG**, the exact
algorithm from the DOS CRT:

```js
this.seed = room;                                          // seeded from the room number
this.seed = ((this.seed * 214013 + 2531011) & 0xffffffff) >>> 0;
return (this.seed >>> 16) % (max + 1);
```

Port this **bit-exactly** with `UInt32` and explicit `&*`/`&+` wrapping arithmetic. It is used
for wall-pattern generation.

**Fidelity risk to resolve:** PrinceJS uses this seeded LCG for wall generation but
`Math.random()` (`Utils.random`) elsewhere, including gameplay. So PrinceJS is only
*partially* replay-deterministic. SDLPoP has a first-class `seed=` option and recordable
replays. **Open question:** adopt SDLPoP's gameplay RNG so replays are reproducible end to
end, even if that means diverging from PrinceJS. Leaning yes — reproducibility is worth more
than matching a source that is itself non-deterministic.

### 7.8 Time and ticks

- Tick duration is **1/12 s** normally and **1/10 s while fighting**
  (source: `reference/SDLPoP/doc/internals_sequence-table.txt`, which defines *frame* as
  "1/12 seconds (1/10 s when fighting)").
- **Open question:** confirm whether this is a global tick-rate switch or a per-actor one.
  Check `reference/SDLPoP/src/seg000.c`. Assume global until disproven.

Implementation: a fixed-timestep accumulator driven by `SKScene.update(_:)`:

```swift
accumulator += min(dt, maxFrameTime)          // clamp to avoid spiral-of-death
while accumulator >= tickDuration {
    world.tick(intents: input.sample())       // deterministic, ordered
    accumulator -= tickDuration
}
```

Cap catch-up steps per rendered frame (5 is plenty). **Cost of getting this wrong:** on a
120 Hz ProMotion display, a vsync-driven sim runs the entire game ten times too fast.

### 7.9 The simulation/presentation boundary

The single most valuable boundary in the codebase.

```swift
// PoPCore produces this. It knows nothing about SpriteKit.
public struct SpriteInstance: Sendable {
    public var texture: TextureID     // e.g. .kid(frame: 102)
    public var position: CGPoint      // room-relative pixels
    public var z: Int
    public var flipped: Bool
    public var alpha: Double
}

public struct RenderDescription: Sendable {
    public var room: Int
    public var sprites: [SpriteInstance]
    public var levelTimeRemaining: Int
    public var health: Int
}
```

`PoPCore` emits one of these per tick; `PoPHost` draws it. This is what makes the simulation
testable without a window, and what would let you swap SpriteKit for Metal later without
touching game logic.

### 7.10 Input

The sim must never read the keyboard (Law 6). `PoPHost` samples the keyboard into a value type:

```swift
public struct Intents: OptionSet, Sendable {
    public let rawValue: UInt8
    public static let left   = Intents(rawValue: 1 << 0)
    public static let right  = Intents(rawValue: 1 << 1)
    public static let up     = Intents(rawValue: 1 << 2)
    public static let down   = Intents(rawValue: 1 << 3)
    public static let action = Intents(rawValue: 1 << 4)   // shift: drink, grab, strike
}
```

Original mapping: arrows for movement, **Shift** for drink-potion / grab-ledge / sword-strike,
**Space** to show remaining time, **Enter** to continue. Because `Intents` is a value, replay,
demo playback and scripted tests are all the same code path.

### 7.11 Game flow

`GKStateMachine` for top-level states only — this is a genuine, contained win:

```
Title → Cutscene → Playing → Dying → LevelTransition → GameOver / Victory
```

Do **not** push actor or combat state into GameplayKit. See Law 2.

### 7.12 Concurrency (Swift 6)

The temptation is to make everything concurrent. Don't.

- **Data types** (`LevelData`, `AnimationTable`, `SpriteInstance`): `Sendable` immutable structs.
  Load once, share freely.
- **The simulation** (`World`): a non-`Sendable` class confined to `@MainActor`. No `async`
  inside it — a deterministic sim wants synchronous, ordered stepping.
- **Concurrency belongs at the edges:** `async` decode of JSON and atlases off-main, audio,
  save I/O, and the asset-loading screen.
- **Forbidden:** one `actor` per character (Law 7).

---

## 8. Testing and fidelity verification

The simulation is the risk. Make it testable without a window and you can refactor freely.

1. **Decode tests** — every level and animation JSON round-trips; tile counts are exactly 30
   per room; `fcheck` hex strings decode to the right bits.
2. **VM tests** — a single `tick()` on `startrun` runs opcodes until the first `CMD_FRAME`;
   assert the resulting `charFrame`, `charX`, `action`, `_seqpointer`. Write these *from the
   reference implementation*, not from intuition.
3. **LCG tests** — assert a known seed sequence against values computed from the reference
   formula. This is a pure function; it must be bit-exact.
4. **Golden trace tests** — run N ticks with a scripted `Intents` program, hash the world
   state, snapshot it. Any behaviour change fails the build. This is the safety net that makes
   faithful porting survivable.
5. **Architecture test** — assert `PoPCore` does not link SpriteKit/AppKit/GameplayKit/
   AVFoundation (Law 5). In SwiftPM, enforce by having `PoPCore` declare *zero* target
   dependencies and checking the built module's imports.
6. **Differential testing against SDLPoP** (later, M6+) — SDLPoP can record replays
   (`doc/replay_format.txt`) and has a `--screenshot` mode. Build it natively once SDL2 is
   installed, walk a recorded route in both, and compare.

Use **Swift Testing** (`import Testing`, `@Test`), not XCTest — it is the default on Swift 6.3.

---

## 9. Milestones

Each milestone is independently verifiable. **Do not start the next one until the current
one's "done when" passes.**

| # | Milestone | Done when |
|---|---|---|
| **M0** | Package skeleton, `PoPCore`/`PoPHost`/`Prince` targets, empty window | `swift test` green; `swift run Prince` opens a 640×400 window |
| **M1** | Data layer: decode levels, anims, atlases; `TileKind`; `FrameCheck` | Level 1 decodes; all rooms have 30 tiles; `fcheck` bit tests pass |
| **M2** | Sequence VM: `Opcode`, `SequenceProgram`, `ActorState`, coordinate model | `startrun` / `stand` / `runjump` step correctly in unit tests with no renderer |
| **M3** | Movement + tile queries: floor, barrier, foot, room edges | Prince walks, jumps and falls correctly in a headless trace |
| **M4** | Rendering: room draw, camera, tile sprites, atlas loading | Level 1 renders on screen and the Prince walks around it |
| **M5** | Room graph, transitions, prince spawn, level load | You can traverse level 1's rooms and reach the exit |
| **M6** | Combat + guards: probability tables, swordfight, deaths | A guard can be fought, blocked, killed; the Prince can die |
| **M7** | Hazards and mechanisms: gates, buttons, loose boards, choppers, potions, spikes, exit door | Level 1 is completable start to finish |
| **M8** | Audio, UI (health, timer), menus, cutscenes, full level chain | The game is playable from title to level 2 |
| **M9** | Polish: app bundle, icon, keybinding config, distribution decision | A double-clickable `.app` |

**M2 is the milestone that de-risks everything.** If the VM is right, the rest is content and
plumbing. If it is wrong, nothing downstream will ever feel correct.

---

## 10. Open questions

1. **Combat tick rate** — global 1/10 s switch, or per-actor? Verify in `SDLPoP/src/seg000.c`.
2. **Gameplay RNG** — adopt SDLPoP's seedable RNG (reproducible replays) or mirror PrinceJS's
   partial `Math.random()`? Recommendation: adopt SDLPoP's.
3. **Coordinate representation** — integer pixels plus a half-pixel accumulator, or `CGFloat`
   half-points? Decide in M2, write it down here, never revisit.
4. **Screen geometry** — room is 320 × 189 inside a 320 × 200 screen. How is the remaining
   11 px reconciled with `UI_HEIGHT = 8`? Check SDLPoP at M4.
5. **Level chain and cutscenes** — how the 14 levels, 12a/12b split, princess level and the
   shadow sequence are ordered. Read `Cutscene.js` and `Game.js` before M8.
6. **SDLPoP-only extensions** — fake tiles, added tile+modifier combos. Opt-in extras, off by
   default. Never let them leak into the faithful core.
7. **Assets** — stay Ubisoft's. Keep them swappable; replacing them must remain a content job.

---

## 11. Reference lookup table

Where to look when you have a question. Keep this table current.

| Question | File |
|---|---|
| What does an opcode do? | `reference/PrinceJS/src/Actor.js`, `Fighter.js`, `Kid.js`, `Enemy.js` |
| What are the animation sequences? | `reference/PrinceJS/assets/anims/*.json` |
| What are the geometry constants? | `reference/PrinceJS/src/Boot.js` |
| How are rooms laid out and linked? | `reference/PrinceJS/src/LevelBuilder.js` |
| What are the tile kinds? | `reference/PrinceJS/src/Level.js` |
| What tile+modifier combos exist? | `reference/SDLPoP/doc/tiles.md` |
| autocontrol vs control vs anim; chtabs | `reference/SDLPoP/doc/internals_sequence-table.txt` |
| Exact combat numbers | `reference/PrinceJS/src/Fighter.js` |
| Guard difficulty tables | `reference/PrinceJS/src/Enemy.js` |
| The RNG | `reference/PrinceJS/src/LevelBuilder.js` |
| Replay format | `reference/SDLPoP/doc/replay_format.txt` |
| Why the sequence table looks like this | `reference/POP-AppleII/01 POP Source/Source/SEQDATA.S` |

---

## 12. Decision log

| Date | Decision | Rationale |
|---|---|---|
| — | Port PrinceJS, not SDLPoP | 4× smaller, public domain, assets pre-extracted, no DOS binary decoder needed |
| — | SDLPoP as behavioural oracle | Actively maintained; best internals docs in existence |
| — | Reject ECS as top-level architecture | PoP is a sequence VM that mutates the world; ECS inverts the control flow |
| — | Reject Glide Engine | Swift 5 mode only, dormant since 2023, physics model PoP does not use |
| — | Reject `GKRuleSystem` for guard AI | AI is hand-tuned probability tables; rules would destroy the tuning |
| — | Reject `GKRandomSource` | Must be bit-exact LCG for replay determinism |
| — | SwiftPM first, Xcode project later | Sub-second headless test loop over the risky part |
| — | Sim single-threaded, `@MainActor` | Actor hops have no ordering guarantee; determinism wins |
