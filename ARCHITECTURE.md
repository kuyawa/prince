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
    │   │   ├── Geometry.swift       ✅ M0 — the 32 x 63 / 320 x 189 constants
    │   │   ├── GameData.swift       ✅ M1 — bundle loading, level and table access
    │   │   ├── CoordinateSpace.swift ✅ M2 — x-units vs pixels; floor division that matches JS
    │   │   ├── Model/               ✅ M1 — LevelData, RoomData, Tile, TileKind, spawns, events
    │   │   ├── Anim/                ✅ M1 — AnimationTable, FrameDef, FrameCheck, SwordOffsetTable
    │   │   │                        ✅ M2 — Opcode, ActorClass, SequenceInterpreter (the VM)
    │   │   ├── Actor/               ✅ M2 — ActorState, ActorEffect
    │   │   │                        ✅ M3b — Intents, Behaviour (the control layer)
    │   │   │                        ✅ M6 — Combat, GuardBrain
    │   │   │                           ⬜ M6b — guards loaded from the level and drawn
    │   │   ├── Sim/                 ✅ M3 — LevelRuntime, TilePredicates, Physics, FallCycle,
    │   │   │                           LCG, Ticker
    │   │   │                        ✅ M6b — Simulation (the tick), actors in World
    │   │   │                        ✅ M5 — cross-room tile lookup, room wrapping
    │   │   │                        ✅ M7 — World, LevelState, Gate, Button, ExitDoor,
    │   │   │                           LooseBoard, TileChecks
    │   │   │                           ⬜ M7c — spikes, choppers, potions
    │   │   │                           ⬜ M3c — checkBarrier (blocks `bump`)
    │   │   ├── Combat/              ⬜ M6 — Swordfight resolution
    │   │   ├── Tiles/               ⬜ M7 — Gate, Button, Loose, Chopper, Potion, Spikes, ExitDoor
    │   │   └── Resources/           ✅ M0 — 7.8 MB of game data, bundled HERE (not PoPHost) so
    │   │                                PoPCoreTests reaches it by the same path the game uses
    │   │   ├── Render/              ✅ M4 — RenderDescription, RoomRenderer
    │   ├── PoPHost/                 ← SpriteKit + GameplayKit + AVFoundation
    │   │   ├── Render/              ✅ M4 — AtlasLoader, LevelScene
    │   │   ├── Input/               ✅ M4 — KeyboardInput → Intents
    │   │   ├── Flow/                GameFlow (GKStateMachine)
    │   │   └── Audio/               AudioEngine
    │   └── Prince/                  ← @main executable target
    └── Tests/PoPCoreTests/
```

### Package.swift sketch

```swift
// swift-tools-version: 6.2   // NOT 6.0 — that manifest has no .macOS(.v26)
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
- Each room holds exactly **30 tiles** — a 10 × 3 grid, row-major, with
  `tileNumber = y * 10 + x` and **y = 0 at the top**. Confirmed by `LevelBuilder.js#buildTile`
  and `Level.js#addTile`.
- **Rooms with `id == -1` carry no `tile` key at all** — 200 of the 476 room slots across the
  fourteen levels are gaps. A required `[Tile]` rejects valid data.
- `events[].next` is the event number to chain to, or `0` for none.

#### Event slots are positional and contain holes

```js
// LevelBuilder.js
this.level.events = json.events;          // assigned straight through

// Level.js#fireEvent — looked up BY INDEX
fireEvent: function (event, type, stuck) {
  if (!this.events[event]) { return; }    // the hole guard
  let x = (this.events[event].location - 1) % 10;
  ...
}
```

Seven of the fourteen levels contain `null` entries — level 6 has holes at indices
`1, 3, 4, 5, 7, 8` of 12; level 8 has one at index 5 of 14. **Compacting this array renumbers
every subsequent event and breaks the game with no error message.** The model preserves the
optionals; `LevelDecodeTests` asserts the exact hole positions.

#### `location` uses two different conventions

| Context | Conversion | Evidence |
|---|---|---|
| **Events** | `(location - 1) % 10`, `(location - 1) / 10` — 1-based, 1…30 | `Level.js:246` |
| **Actors** (Prince, guards) | `location % 10`, `location / 10` | `Fighter.js:7-8` |

These disagree by one within each row. Only events ever reach location 29 or 30, which is
consistent with the event reading. **Unresolved — see open question 8.** `RoomData` exposes
`tile(eventLocation:)` for the event convention and deliberately offers no conversion for the
actor one until M3 settles it.

### 6.2 Tile kinds — `reference/PrinceJS/src/Level.js`

`element` is the tile kind; `modifier` is the variant byte. Full table as of the port source:

```
 0 SPACE             8 BOTTOM_BIG_PILLAR  16 EXIT_LEFT          24 BALCONY_RIGHT
 1 FLOOR             9 TOP_BIG_PILLAR     17 EXIT_RIGHT         25 LATTICE_PILLAR
 2 SPIKES           10 POTION             18 CHOPPER            26 LATTICE_SUPPORT
 3 PILLAR           11 LOOSE_BOARD        19 TORCH              27 SMALL_LATTICE
 4 GATE             12 TAPESTRY_TOP       20 WALL               28 LATTICE_LEFT
 5 STUCK_BUTTON     13 MIRROR             21 SKELETON           29 LATTICE_RIGHT
 6 DROP_BUTTON      14 DEBRIS             22 SWORD              30 TORCH_WITH_DEBRIS
 7 TAPESTRY         15 RAISE_BUTTON       23 BALCONY_LEFT       31 DEBRIS_ONLY
                     (…the list runs to 32 NULL)
```

**There are 33 kinds, 0…32.** Only `0...29` appear in the shipped levels: `5` (STUCK_BUTTON)
is an SDLPoP-era addition that the original level set never uses, and `30`, `31`, `32` are
engine-defined but absent. `modifier` values observed: `0...18` and `20`.

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

| File | Sequences | Frame defs |
|---|---|---|
| `kid.json` | 75 | 241 |
| `shadow.json` | 51 | 241 |
| `fighter.json` | 23 | 36 |
| `princess.json` | 10 | 48 |
| `vizier.json` | 5 | 39 |
| `mouse.json` | 5 | 4 |
| `sword.json` | — | — |

**`framedef` entries can be comment-only.** `kid.json` has 19 entries carrying nothing but a
`comment`, `shadow.json` 13, `fighter.json` 1. Every numeric field — `fdx`, `fdy`, `fcheck`,
`fsword` — is therefore optional, and `fsword` is absent on most *complete* frames too
(214 of kid's 241). In JavaScript these read as `undefined`; that is only safe because no
sequence targets them, which `referencedFramesAreComplete` verifies rather than assumes.

**`sword.json` is not an animation table.** Its only key is `swordtab`: 50 `{id, dx, dy}`
sword-overlay offsets. Same extension, different schema — modelled as `SwordOffsetTable`.

**A dangling branch exists in the source data.** `shadow.json`'s `stepfall` conditionally
branches to `stepfloat` via `CMD_IFWTLESS` (247), but `shadow.json` defines no such sequence.
`kid.json` has the identical branch and does define it. The shadow's branch is never taken, so
the reference is dead — but M2 must not assume every named target resolves. Pinned by
`theOnlyDanglingSequenceReferenceIsShadowStepfloat`.

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

Everything else is `NOOP`.

#### The opcode table is per actor class

`Actor`'s constructor registers **all 256** byte values to `CMD_NOOP`, then overrides six.
`Fighter` adds three. `Kid` adds seven. `Enemy` and `Mouse` add none. A byte that is a real
opcode but is **not registered for the actor executing it is a silent no-op**.

| Class | Count | Opcodes |
|---|---|---|
| `Actor` | 6 | `FRAME`, `TAP`, `CHY`, `CHX`, `ABOUTFACE`, `GOTO` |
| `Fighter` | +3 | `DIE`, `SETFALL`, `ACT` |
| `Kid` | +7 | `NEXTLEVEL`, `EFFECT`, `JARD`, `JARU`, `IFWTLESS`, `DOWN`, `UP` |
| `Enemy` | — | overrides `TAP` only |
| `Mouse` | — | extends `Actor`, registers nothing |

**This is not a technicality — the shipped data crosses the classes:**

- `fighter.json`'s `impale` and `shadow.json`'s `standjump`, `runjump`, `softland`, `runjumpdown`,
  `softlandStandup` all contain `JARD` (244), which only `Kid` registers → no-op for a guard
- `shadow.json`'s `drinkpotion` contains `EFFECT` (243) → no-op for the shadow
- `mouse.json`'s `scurry` and `leave` contain `ACT` (249), which `Mouse` does not register → no-op

Modelling the tables as one flat union gives guards and shadows behaviour they have never had
in any version of this game. `ActorClass` in `Anim/Opcode.swift` encodes the chains, and
`SequenceVMTests` feeds the *same real data* to different classes and asserts the divergence.

A pleasant consequence: the dangling `shadow.json → stepfloat` reference M1 found is inert
**precisely because** `IFWTLESS` is a Kid-only opcode. Feeding that data to a Kid throws; to a
shadow it does nothing. That is asserted, not assumed.

#### The dispatch loop

`ACT` (249) turned out to be trivial — it stores `p1` in `actionCode` and zeroes both velocities
when `p1 == 1`. It is the *input* system that will be heavy, not this opcode.

`IFWTLESS` (247) is misnamed and ignores its own operand entirely: it simply swaps the current
fall for its floating variant (`stepfall` → `stepfloat`) when `isInFloat` is set.

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
collision extents, and it is stored as a hex string in JSON, so decode `"0xC4"` → `UInt8`.
The data uses a lowercase `0x` with uppercase digits; 50 distinct values appear, from `0x00`
to `0xEF`.

### 7.4 The dual coordinate space

Actors live in **two coordinate systems at once**, and they are not the systems the names
suggest.

> **`charX` is not a pixel.** A room is **140 x-units** wide and **189 pixels** tall.
> One tile column is **14 x-units**; one tile row is **63 pixels**. The renderer scales x by
> `320/140` to reach the screen.

| Axis | Unit | Per tile | Per room | Conversion |
|---|---|---|---|---|
| `charX` | x-units | 14 | 140 | `Utils.convertX`: `floor(x * 320 / 140)` |
| `charY` | pixels | 63 | 189 | used directly |

Every horizontal offset in the animation data — `CMD_CHX`, `charFdx`, `charFfoot` — is in
x-units. Every vertical one is in pixels.

- **Engine space:** `charX` (x-units), `charY` (pixels) — continuous position.
- **Tile space:** `charBlockX`, `charBlockY` — which tile the actor occupies, derived from the
  actor's **foot** rather than its origin.

```js
// Fighter.updateBlockXY — the foot, not the origin
let footX = this.charX + this.charFdx * this.charFace - this.charFfoot * this.charFace;
let footY = this.charY + this.charFdy;
this.charBlockX = Utils.convertXtoBlockX(footX);      // floor((footX - 7) / 14)
this.charBlockY = Math.min(Utils.convertYtoBlockY(footY), 2);   // floor(footY / 63), clamped
```

That is what `fcheck` bits 0–4 are for. The `min(…, 2)` is the engine's, not a safety net.

**JavaScript's `Math.floor` rounds toward negative infinity; Swift's `/` truncates toward zero.**
They disagree whenever an actor walks off the left edge of a room — `floor((0 - 7) / 14)` is `-1`,
which is exactly what drives the room transition. `CoordinateSpace.floorDivide` exists for this
and is tested against the negative cases.

Room traversal mutates the *block* coordinate and offsets the pixel coordinate by a whole room
(`Kid.js`: `charY += 189; charBlockY = 2;` on room-up).

### 7.4.1 The level grid, room links and tile lookup

`LevelRuntime` rebuilds the runtime view of a level from the decoded data, walking the room
array the way `LevelBuilder.js` does (`index = y * width + x`, skipping `id == -1`) and then
deriving `links` from grid adjacency. **Links are never stored in the data.**

`LevelBuilder.getRoomId` returns **`-1`** both for off-grid coordinates and for a gap in the
layout, and the reference guards with `<= 0`. Reproduced literally — the difference between
`-1` and `0` matters when a link is read directly, as `CMD_UP` (253) does.

**Tile classification lives in `Sim/TilePredicates.swift`.** `Base.js`'s predicates are
membership tests against fixed sets, and they do **not** partition the kinds:

| Predicate | Count of 33 | Note |
|---|---|---|
| `isWalkable` | 25 | a **negated** membership test — true for potions, exits and torches |
| `isSpace` | 7 | includes `topBigPillar`, which is *not* walkable |
| `isBarrier` | 5 | |
| `isSafeWalkable` | 23 | |

Two traps: `topBigPillar` is space but not walkable; `tapestryTop` is space **and** a barrier but
not jump space; and `tapestry`/`tapestryTop` are barriers to walking but **not** to falling, so
you drop straight past a hanging. `TilePredicateTests` checks all 33 kinds against a bitmask
table generated by running the **JavaScript** predicates, so it is a differential test rather
than a restatement of the Swift.

Rendering position, from `updateCharPosition()`:

```js
let tempx = this.charX + this.charFdx * this.charFace;
if ((this.charFood && this.faceL()) || (!this.charFood && this.faceR())) {
  tempx += 0.5;                       // half-pixel parity correction
}
this.x = this.baseX + PrinceJS.Utils.convertX(tempx);
this.y = this.baseY + this.charY + this.charFdy;
```

**Resolved (M2): everything is `Int`, in the engine's own units.**

`updateVelocity` adds integer velocities, `updateAcceleration` adds an integer `GRAVITY` of 3
(`TOP_SPEED` 33), and every opcode operand is an integer. Nothing fractional ever exists in the
simulation, so the model is `Int` and there is no accumulator to get wrong.

The `+0.5` above is a **render-time** parity correction and nothing else. It belongs to
`CoordinateSpace.screenX(fromX:)`, which takes a `Double` so the caller can apply it, and it
never touches `ActorState`.

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

**As built (M4).** Positions are room-local, **y-down**, in original pixels — the engine's own
space, not the screen's. Sprites carry an explicit `SpriteAnchor` because the reference anchors
tiles at top-left (`addTile`) and actors at bottom-left (`Actor`'s `anchor.setTo(0, 1)`).

Which frame a tile draws is **game logic and lives in `PoPCore.RoomRenderer`**, not in the host.
Three rules there are easy to get wrong:

- **A mirror draws as floor.** `Tile.Mirror` hands `TILE_FLOOR` to `Base`, so there is no
  `dungeon_13` or `palace_13` frame in either atlas. Asking for one renders *nothing*, silently.
- **Space and floor tiles draw a second sprite**: `<element>_<modifier>`, a child of the back
  sprite. That child is what distinguishes the floor variants — without it, every floor looks
  identical.
- **Dungeon walls are named for their shape**, four patterns × 53 seeds:
  `<left>W<right>_<tileNumber + roomId>`, where a side is `W` only if that neighbour is a wall.

The single line that converts is `SK y = roomHeight − engineY`; the room's top is anchored at
`roomTopY = 189` in the 320 × 200 screen, leaving the bottom 11 px (open question 4).

#### A trap worth naming

**`SKTexture(rect:in:)` measures from the bottom-left; TexturePacker measures from the
top-left.** Getting this wrong does not throw or crash — it silently samples the wrong part of
the sheet, and the room renders as plausible-looking textured noise. It was found by adding a
`--dump-frame` diagnostic that renders one atlas frame at 1:1 and comparing it against the same
region cropped straight out of the PNG. If the renderer is ever reworked, keep that diagnostic.

### 7.9.1 Window scale

Window scale is a **presentation-only** setting (`WindowScale`, in `PoPHost`). It is the
one value in this project that is genuinely free to change:

- **CLI:** `swift run Prince --scale 4` → 1280 × 800
- **Runtime:** the **View** menu, **Cmd-1** through **Cmd-N**
- **Default:** 2× (640 × 400), mirroring `SCALE_FACTOR` from PrinceJS `Boot.js`

Because `PoPCore` works exclusively in the original 320 × 200 pixel units and the renderer
scales at the last possible moment, changing this **cannot** affect gameplay, timing or
collision. If a future change makes the scale leak into `PoPCore`, that is a Law 8
violation, not a feature request.

Two constraints:

1. **Integer multiples only.** A fractional scale lands the 32 × 63 tile grid on
   non-integer device pixels and the art shimmers.
2. **Only scales that fit the display are offered** (`WindowScale.fitting`, measured
   against `NSScreen.main.visibleFrame`). A window taller than the screen is a bug,
   so the CLI is clamped the same way the menu is.

### 7.9.2 The interactive tile layer (trobs)

`LevelRuntime` is the decoded level and never changes. `LevelState` is everything that does —
gate positions, button presses, whether the exit opened. `World` pairs them and is what satisfies
`TileWorld`, so the movement code and the VM ask one object for everything.

The split matters: the level data stays cheap to share and `Sendable`, and a test can reset the
world without reloading anything.

#### A button's modifier is an event *index*

```js
Button.prototype.trigger = function (stuck) {
  this.onPushed.dispatch(this.modifier, this.element, stuck);   // -> Level.fireEvent
};

Level.prototype.fireEvent = function (event, type, stuck) {
  if (!this.events[event]) { return; }        // indexed directly, holes included
  let x = (this.events[event].location - 1) % 10;
  ...
};
```

**The modifier indexes the events array; the `number` field on each entry is a separate label.**
Level 1 confirms it: room 5's three buttons carry modifiers 8, 9 and 11, and events at those
indices all sit in room 5 — which is exactly where the gates they raise are. Under the other
reading one of them would have pointed at room 8.

Level 1 also **uses chaining**: `events[9].next` is 1, so the raise button at x=4 opens the gate
at (9,0) *and* the one at (5,0). A single-room puzzle that exercises both mechanisms.

#### The gate

`modifier` seeds **both** position and phase, which is how a level starts with a gate already
open — room 5 has one of each:

| modifier | phase | position | meaning |
|---|---|---|---|
| 0 | `closed` | 0 | shut |
| 1 | `open` | −46 | already raised |

`canCross(height)` is `|position| > height`. Motion is fixed-step: 47 pixels up, one per tick; a
50-tick wait at the top; then down one pixel every fourth tick — or ten a tick when dropped.

**`closedFast` is what makes a slammed gate stay shut.** A raise button re-fires with `stuck`
while it is still held, and `raise(stuck:)` returns early when `closedFast && stuck`. A *fresh*
press still works. That one flag is the difference between a gate you can hold open and one you
cannot.

#### Rendering a rising gate

The reference crops the texture: `crop(new Rectangle(0, -posY, width, height + posY))`, and Phaser
redraws the remainder at the sprite's origin — which both removes the top rows and slides the art
up. That maps onto `SKTexture(rect:in:)` for free, because SK measures from the **bottom-left**:
cutting rows off the top leaves the origin untouched and only shortens the rectangle. No y
arithmetic, and no crop node.

`SpriteInstance.clipTop` carries the amount, and the host resolves it because only the host knows
a frame's pixel height.

#### The collapsing floor

`Level.floorStartFall` does not push the Prince anywhere. It **replaces the tile with
`TILE_SPACE`**:

```js
floorStartFall: function (tile) {
  let space = new PrinceJS.Tile.Base(this.game, PrinceJS.Level.TILE_SPACE, 0, tile.type);
  this.addTile(tile.roomX, tile.roomY, tile.room, space);
  ...
}
```

**The hole is the mechanism.** On the next tick `checkFloor` finds space under him and starts
him falling, exactly as it would over any other gap — no special case anywhere. `LevelState`
mirrors this with an `overrides` map, and `World.tile` consults it before the level.

A board shakes for eight frames and then gives way. If it was only *nudged* rather than stood on,
it settles back at frame 3 instead — which is the entire reason `shake(fall:)` takes a flag.

#### The exit door

`heightOpen = 8 + type`, so 8 pixels remain in a dungeon and 9 in a palace. It raises a pixel a
tick and drops fifteen. `fireEvent` reaches it exactly as it reaches a gate: a raise button calls
`raise`, a drop button calls `drop`, and the two-tile-wide door is handled by redirecting an
`EXIT_LEFT` target to the `EXIT_RIGHT` beside it.

**The port tracks `visibleHeight` directly rather than reproducing the reference's bookkeeping.**
The reference terminates its raise with `door.height === this.heightOpen`, which works only because
Phaser's `crop()` rewrites the sprite's `height` from the crop rectangle. The intent is
unambiguous, and modelling it directly is clearer than reproducing a rendering library's side
effect.

#### Jumping

`Kid.jump` is not one verb but **five tile probes routing into the ledge system**, ending in
`jumpup`, `highjump`, `jumphanglong`, `jumpbackhang` or `climbstairs`. The last is how a level
is finished: standing on an open exit and pressing up runs the stairs sequence, whose
`NEXTLEVEL` opcode is already wired.

**The two mirror branches are omitted.** They need `bump`, whose physics depend on the same
screen-space bounds `checkBarrier` owes (open question 11). Each condition is still evaluated and
returns without changing the action, so control flow matches the reference — only the bump itself
is missing, and only in rooms containing a mirror.

#### What is not here

Spikes, choppers and potions use the same `Trob` shape and are the remaining M7 work.
`STUCK_BUTTON` is modelled but unused — M1 found the original levels never place one.

### 7.9.3 Sword fighting

#### The animation *is* the state machine

Every combat verb is gated on `frameID`. A strike is legal only on frames 157–158, 165, 170–171,
7–8, 20–21 or 15; a step only on 158, 171, 8 or 20–21; a block only on 8, 20–21, 18 or 15.
Pressing the key on any other frame does nothing at all.

That is why combat feels deliberate rather than mashable, and it is the single most important
thing to preserve. **Nothing about it is timing-independent**, so "responsiveness" improvements
would silently change the game.

#### `die` zeroes the health

```js
Fighter.prototype.die = function (action) {
  let damage = this.health;
  this.health -= damage;          // -> 0
  this.action = action || "dropdead";
  this.alive = false;
};
```

and `damageLife` calls `die` at **one** health rather than decrementing to zero. Both matter,
because `stabbed` picks between `stabkill` and `stabbed` by testing `health === 0` *after* the
damage has been applied. Modelled as `health -= 1` down to zero, a fatal blow is
indistinguishable from a wound.

#### The guard's mind

Every choice is a fixed threshold against a random number:

```js
if (this.strikeProbability > this.game.rnd.between(0, 254)) { this.strike(); }
```

The twelve columns of those tables are the twelve difficulty levels the level editor exposes, and
the values are hand-tuned. They are transcribed verbatim in `GuardBrain`; **there is nothing here
to improve.** `applyStrength` scales them by the player's chosen difficulty, using `ceil`.

Guard health is `EXTRA_STRENGTH[skill] + STRENGTH[levelNumber]` — note the second table is
indexed by **level**, not skill, which is easy to get backwards.

**Omitted:** `canReachOpponent` is simplified to a distance test. The reference walks a tile path
between the fighters measured from `centerX` — the same Phaser sprite geometry `checkBarrier`
still owes (open question 11). A guard may therefore engage through a thin barrier the original
would have stopped at.

### 7.9.4 Actors in the world

`Simulation` owns the tick. It lives in `PoPCore`, not in the scene, because it is game logic:
a duel can be driven headlessly, and `LevelScene` shrinks to keyboard sampling, a fixed timestep,
and drawing.

`World` holds the actors and the generator. **Index 0 is always the Prince.** Combat has to name
an opponent, and the reference uses a direct object reference; in a value-type simulation an index
is the equivalent, and pinning the Prince at zero keeps the common case cheap.

**Actor order.** The reference creates the guards *before* the Prince (`Game.js` builds every
`Enemy`, then `this.kid`), and updates them in that order. The port keeps the Prince at index 0
for lookup but still ticks the guards first, because the order decides which of two simultaneous
events lands first and matching costs nothing.

**Opponents are simplified.** The reference sets `this.opponent` when a fight begins and the two
reference each other. Here a guard always faces the Prince, and the Prince faces the nearest living
guard in his room — the same pairing in every non-combat case, differing only when three or more
fighters converge.

#### Which table an actor reads

`Enemy`'s constructor passes an `animKey` to `Fighter`:

```js
PrinceJS.Fighter.call(this, game, level, location, direction, room, key,
                       key === "shadow" ? "shadow" : "fighter");
```

So every guard, fat guard, skeleton and Jaffar reads `fighter.json`; only the shadow reads
`shadow.json`; and each draws from a **sprite atlas named for its own `charName`**. A plain
`"guard"` becomes `"guard-<colour>"` at construction, so a level's `colors` field selects the
sheet.

#### One gap worth knowing

**`shadow.json` and `vizier.json` have no frame 0** — their frames start at 1. `ActorState`
begins at `charFrame = 0`, so a shadow's very first frame is not a real sprite. It is never
displayed in practice, because the first `CMD_FRAME` replaces it before anything is drawn, and
`makeNode` returns nil for a missing texture exactly as Phaser renders nothing for a missing
frame. Levels 4, 5, 6 and 12 contain shadows; level 13 Jaffar.

### 7.9.5 Level chaining

`CMD_NEXTLEVEL` (241) fires `onLevelFinished`, then `onNextLevel` after a delay:

```js
Kid.prototype.CMD_NEXTLEVEL = function (data) {
  PrinceJS.maxHealth = this.maxHealth;
  let waitTime = 0;
  if (PrinceJS.currentLevel === 4) { this.game.sound.play("TheShadow"); waitTime = 9000; }
  else if (![13,14].includes(PrinceJS.currentLevel)) {
    this.game.sound.play("Prince"); waitTime = 13000;
  }
  ...
};
```

That wait exists purely to let the "Prince" theme finish — thirteen seconds, or nine on level 4 for
the shadow. **With no audio yet it is dead time, so the hand-off is immediate.**

The mechanism stays in `PoPCore`: the sequence's opcode becomes an `ActorEffect`, the scene turns
it into a callback, and `PoPHost.GameCoordinator` decides what a "next level" is. Nothing in the
simulation knows that levels are numbered.

Health carries: `PrinceJS.maxHealth = this.maxHealth`, and the current health is passed onward.
The Princess is rescued at the end of level 14, and the run stops rather than loading a
nonexistent 15 — `nextLevel(after:)` is a pure function so that decision is testable without a
window.

### 7.9.6 The hourglass and the status bar

The clock is a real mechanic, not decoration: sixty minutes, and the tension in Prince of Persia
comes substantially from it.

**The reference reads the wall clock.** `getDeltaTime` subtracts `startTime` from `new Date()`.
The port counts simulated ticks instead — identical under a fixed timestep, but it does not drift
when frames are dropped, and it keeps a run reproducible from a seed, which a clock read cannot.

#### Two readouts that are not the same quantity

```js
getDeltaTime: function () {
  let diff = (PrinceJS.endTime || new Date()).getTime() - PrinceJS.startTime.getTime();
  let minutes = Math.floor(diff / 60000);
  let seconds = Math.floor(diff / 1000) % 60;      // the FIELD, not the total
  return { minutes, seconds };
},
getRemainingMinutes: () => Math.min(60, Math.max(0, 60 - deltaTime.minutes)),
getRemainingSeconds: () => Math.min(60, Math.max(0, 60 - deltaTime.seconds)),
```

`seconds` is the seconds **field**, so `remainingSeconds` counts down *within the current minute*
and resets to 60 each time one rolls over. It is what the bar shows during the final minute —
which is why the display jumps from "5 MINUTES LEFT" to "59 SECONDS LEFT" and never shows
anything in between.

#### The bar

The bottom `UI_HEIGHT` (8) pixels of the 200-pixel screen — the same 11-pixel gap below the
189-tall room that open question 4 flags.

| Element | Position |
|---|---|
| Prince's lives | `x = i * 7`, `y = barTop + 2`, frame `kid-live` or `kid-emptylive` |
| Opponent's lives | `x = 320 - i * 7 + 1`, right-aligned, frame `<baseCharName>-live`, tinted |
| Text | centred on `(160, barTop + 3)` |

The opponent's pips are tinted from `Enemy.COLOR` by the level's `colors` field.

**Text is laid out in `PoPCore` and drawn in the host.** `BitmapFont` parses the BMFont XML
(`prince.fnt`, 96 glyphs, a 256x256 page) and emits final glyph positions in the render
description, so the host has nothing to measure — the same split as every other sprite.

Note the pen advances by `xadvance`, not glyph width: a space is a 1x1 glyph with an advance of
four, so it moves the pen without drawing anything.

### 7.9.7 Sound

The reference plays sound as a **global side effect**: `this.game.sound.play("Footsteps")`, called
from inside `Kid.TAP`, `Fighter.strike`, `Gate.update`, `Button.push`. There are forty-odd such call
sites scattered across the model, and none of them returns anything.

That is the one place the reference's shape cannot be copied literally, because `PoPCore` may not
import AVFoundation (Law 5) and a headless test must not open an audio device. The port keeps the
*call sites* exactly where the reference has them and changes only the *transport*:

```swift
// PoPCore
public enum ActorEffect: Sendable, Equatable {
    case sound(SoundEffect)      // wherever the reference calls game.sound.play
    ...
}
```

An opcode or a verb appends `.sound(...)` to an `inout [ActorEffect]`; `Simulation.tick` drains that
array after each actor step; `LevelScene` turns it into an `onSound` callback; `AudioPlayer` decides
what comes out of the speakers. **The simulation never learns that speakers exist.**

The `effects` sink is threaded through `Combat`, `GuardBrain` and `TileChecks` as an explicit
`inout` parameter rather than stored on the actor. That is deliberate: a `pendingSounds` array on
`ActorState` would leak into `Equatable` and would make an actor that was never ticked indistinguishable
from one whose sounds were never drained.

#### Where the sounds come from

| Producer | Channel | Note |
|---|---|---|
| `TAP` opcode | `ActorEffect.tap(p1)` -> `.sound` | `p1`: 1 footsteps, 2 soft bump, 3 hard bump |
| `Combat.engarde` / `turnengarde` | `.unsheatheSword` | not a `strike` — drawing and swinging differ |
| `Combat.strike` / `stab` | `.stabAir`, `.stabOpponent`, `.swordClash` | `checkFight` decides which lands |
| `FallCycle.land` | soft / medium / `freeFallLand` / spiked | by `fallingBlocks` and the landing tile |
| `Fighter.updateFallingBlocks` | `.fallingFloorLands` | exactly at five floors, kid only |
| `Button.push` | `.floorButton` | via `World.floorButtonSound(at:)`, not the armed/stuck kind |
| `LevelState.update()` | returns `[SoundEffect]` | gates, exit doors and loose boards, in one pass |

Mechanisms are the interesting case. They are not actors, so they do not go through the opcode path.
`Gate.update()`, `ExitDoor.update()` and `LooseBoard.update()` each return `SoundEffect?`, `Trob.update()`
forwards it, and `LevelState.update()` collects the whole tick's worth into an array that `World`
appends to the effect list. One pass, no second traversal, and the sound is produced by the same call
that moves the sprite — which is what makes it impossible for the two to drift apart.

#### Three things the reference gets away with that a port cannot

1. **`Loose.shake` picks its variant with `Utils.random(3)`** — a non-deterministic call from inside
   a tile update. There is no sound difference worth threading a generator through a tile for, so the
   port always plays the first. Recorded here so it is a decision and not an oversight.

2. **`Gate.update` re-plays `GateRising` on every even position.** With several gates moving at once
   the reference genuinely does stack the sample. The port keeps the call site faithful and lets
   `AudioPlayer` collapse it: three voices per effect, chosen least-recently-used.

3. **`FallingFloorLands` is not a landing sound.** It plays in mid-air five floors down — it is the
   Prince's own cry — and only for `charName == "kid"`. The name is a trap.

#### The host end

`AudioPlayer` is the only file in the project that imports AVFoundation, and it is `@MainActor`.
Effects are decoded lazily and cached in a three-voice round-robin per effect, because `AVAudioPlayer`
is single-shot: calling `play()` on a player that is already playing restarts it, and footsteps land
two or three ticks apart. Music is one looping player, and `playMusic` ignores a request for the track
already playing — the reference does the same, and levels 2 and up re-issue the Danger cue.

**A missing or corrupt file disables that one effect and logs once.** Audio is presentation (Law 8);
an asset problem must never be able to stop the game running. `--mute` and `--no-audio` are launch
flags, and `--trace` prints each tick's sounds by filename, never positionally.

**Music is a one-shot, and that is not a style choice.** Phaser’s `SoundManager.play` passes
`loop` straight through and defaults it to false, so every cue in the reference plays once: level
1’s Danger theme plays over the opening and stops, and the Victory fanfare on taking the sword
plays once and stops. The port looped them, which was audible within seconds of launching.

Two details fall out of that. A cue **re-issued after it has finished plays again** — which is what
makes restarting a level work — while a cue for the track that is *still sounding* is ignored,
because the reference would stack a second copy on top of the first. And `setPaused` resumes only
what the host itself paused, tracked with a flag rather than inferred from `currentTime`: a paused
player cannot progress, so the flag is the honest test, and a position check breaks the
pause-immediately-after-start case where the position is still zero.
`Game.update` plays the Danger theme once, on level 1, 800 ms in, and only if the map's
`prince.danger` is not `false`. The other Danger cues in the reference belong to the shadow
encounters on levels 5 and 6, which are not ported.
### 7.9.8 Hazards and pickups

Spikes, potions and the sword. Choppers are M7c-2.

#### What the level data actually contains

A census of all fourteen levels settles several questions before any code is written:

| Tile | Modifiers seen | Count |
|---|---|---|
| spikes | only `0` | 100 |
| chopper | only `0` | 36 |
| loose board | only `0` | 148 |
| sword | only `0` | 2 |
| potion | `1`–`5` | 47 |

Two consequences. First, `Spikes`’ modifier remapping (3–5 collapse to 5, 6 becomes 4, above 6
mirrors to `9 - m`) is **dead code in practice**, and the `modifier === 0` guard in `LevelBuilder`
that decides which fields become trobs excludes nothing. Both are ported anyway — a custom map
could use them — but no shipped level tests them.

Second, `POTION_SPECIAL` is 6 and **no level contains one**. The reference’s special-potion path
— read a modifier out of room 8 tile 0, then fire an event a second after drinking — is
unreachable. `Potion.isSpecial` is modelled so the data is honest; the event plumbing is not
built, because there is nothing to test it against.

#### Spikes

Five frames up, sixteen ticks out, four frames down. **The retraction skips frame 3**: `step` is
decremented, and *then* an extra decrement fires if it landed on 3. So frame 3 appears on the way
up and never on the way down. That asymmetry is the reference’s and is easy to “fix” by
accident.

Two things in `checkSpikes`/`checkFloor` look like mistakes and are not:

1. **`inSpikeDistance` returns `true` unconditionally.** `Fighter` defines it that way and `Kid`
   never overrides it, so the geometry test the name promises does not exist. Ported as written.

2. **A running Prince only dies on a field that is *not* fully out.** That reads backwards until
   you notice `checkSpikes` runs earlier in the same tick and raises the field one column ahead
   when he is within five units of his tile edge. So the field is still rising when he steps onto
   it, and the `FULL_OUT` exclusion only matters for a field somebody else raised.

`checkSpikeFloor` is a separate function rather than a case inside `FallCycle.checkFloorStanding`,
because raising a field mutates world state while the falling branch only reads. The action-code
and `fcharfcheck` guards are duplicated on purpose: the two branches are mutually exclusive, so
exactly one can fire for a given tile.

Level 1 room 6 is the cleanest test in the game, and it is deliberate design:

```
row 0:  T  F  rb .  P  F  F  T  F  P       walk right, press the button at (2,0)
row 1:  W  W  W  .  W  W  W  W  W  W       step off the edge at (3,0)
row 2:  W  W  W  S  S  W  W  W  W  W       fall two rows onto the spikes
```

#### Potions

Five effects, keyed on the modifier: `1` heals a point, `2` raises the ceiling and fills to it
(capped at ten), `3` turns on the float, `4` flips the screen, `5` costs a point.

**The bottle goes immediately; the effect lands twelve ticks later.** The reference wraps the
whole switch in `Utils.delayed(..., 1000)`, which is what makes the drink animation readable. The
port counts ticks — 1000 ms at 1/12 s — rather than reading a wall clock.

The float is a real mechanic, not a visual: `updateAcceleration` uses gravity 1 and a top speed of
4 instead of 3 and 33, and `land` reads `this.inFloat ? 0 : this.fallingBlocks`, so a floating
Prince walks away from any drop. The reference also nudges ledge-swing and edge-grab distances
while floating; those live in the ledge system, which is not ported.

#### Two things the sound channel had to grow

**`game.sound.play` does not distinguish effects from music.** Phaser plays whatever key is in the
audio cache, and three calls in the game name a *music* file: `Victory` when the sword is taken,
and `Potion1`/`Potion2` when a life potion lands. Hence `ActorEffect.music(MusicTrack)` alongside
`ActorEffect.sound`.

**`Preloader` does not load `Float`.** `Kid.floatFall` calls `sound.play("Float")` and Phaser
quietly does nothing, because `assets/music/16_Float.mp3` was never registered. The port’s eight
tracks are the complete set; “missing” music is the reference’s own gap.

#### The main course lives in the `general` atlas

A potion draws its bottle from the level’s atlas and its bubbles from `general` —
`game.make.sprite(25, yy, "general", "bubble_3_green")`. That is the one sprite in the game that
belongs to neither a tile nor an actor, so `SpriteInstance` grew an explicit `atlas` field rather
than the host guessing by trying every loaded sheet.

#### The pickup key

`updateBehaviour`’s standing branch tests **up, then down, then the pickup key**. Holding down
therefore crouches and never reaches an item; the item is taken by the action key *alone*. Getting
this backwards produces a Prince who crouches forever on top of a sword, which is exactly what
the first attempt did.

`tryPickup` then repositions him with two different formulae — facing right a whole column forward
and one unit for a potion, facing left the same `charBlockX++` (which moves him the *other* way)
and three units back. Both land him over the item by different routes. Reproduced as written;
`gotSword` and `drinkPotion` below depend on where it leaves him.
### 7.9.9 Choppers, and the cel-geometry problem

Choppers are the last hazard, and they are the one that forced a decision the rest of the port had
been able to avoid.

#### `activateChopper` takes a starting column

```js
activateChopper: function (x, y, room) {
  do { tile = this.getTileAt(++x, y, room); }
  while (x < 9 && tile.element !== TILE_CHOPPER);
  if (tile.element === TILE_CHOPPER) { this.delegate.handleChop(tile); }
}
```

**The two callers pass different starting columns, and that is the whole design.**
`Fighter.checkChoppers` passes `-1`, so an actor walking into a row wakes its *leftmost* blade.
`Chopper.onChopped` passes `this.roomX`, so a blade reaching its cut wakes the **next one along**.
A row therefore runs as a wave travelling right, staggered three ticks apart.

Reading the scan as "always the leftmost" is the obvious mistake, and it is invisible on levels
with one chopper per row. On level 3's room 16 — three blades side by side — it makes blades four
and five decorative and the row walkable. The port had it wrong for one build.

#### Sprite geometry, and why the simulation needs the atlas

`Fighter.chopDistance` is `tile.centerX - this.centerX - 16`, tested against a 6-pixel window. Both
centres are **Phaser sprite centres**, and a Phaser sprite is as wide as its current frame:

```js
// phaser.js, PIXI.Sprite
Object.defineProperty(PIXI.Sprite.prototype, "width", {
  get: function () { return this.scale.x * this.texture.frame.width; }
});
```

A dungeon tile cel is a constant 60 x 79 — packed at the cell origin, so it overhangs its 32-pixel
cell by 14 on each side, which is the `- 13` in `addTile` seen from the other end. The Prince’s cels
run from 11 px standing to 49 px mid-strike, so **half his width swings further than the window is
wide**.

So `SpriteMetrics` reads the cel sizes out of the atlas JSON. That is the same data `GameData`
already reads for the frame-existence tests, it needs no Apple framework, and it is available to a
headless test. One table unblocks `checkBarrier` too, whose `intersectsAbs` builds its rectangle
from `x, width, 63` — which is open question 11, still open but no longer blocked.

**One deliberate deviation.** `checkChoppers` runs *before* `updateCharPosition` in `updateActor`, so
the reference measures the sprite as the previous tick left it — last tick’s frame and last tick’s
screen x. Reproducing that would mean keeping a shadow copy of Phaser’s transform purely to
reproduce an artefact of its update order, and the DOS original had no such lag. The port measures
the live state.

#### What the numbers mean in play

Each blade owns a band about twelve screen pixels wide, and a running Prince covers about eleven
pixels a tick. A blade is only lethal on three ticks out of fifteen. So the blades are dodgeable at
a run and lethal if you mistime it — which is what makes level 3’s room 16 a puzzle rather than a
wall. The port reproduces that; it is worth knowing it is not a bug when the Prince runs through.

#### Emptiness is the failure mode

There is **no `dungeon_chopper_0`**. `Chopper.update` increments `step` before it names a frame, so
the first frame drawn is 1; the constructor starts the children on frame 5, and steps past 5 leave
them there. Frame 5 is therefore both the resting pose and the end of the cut. A renderer that asks
for frame 0 draws nothing at all, and nothing-at-all looks exactly like an empty ceiling.

### 7.9.10 `checkBarrier`, and the closing of open question 11

The last stub in the port, and the one that had been stubbed longest. `checkBarrier` decides where
a Prince stops at a wall, a gate, a tapestry or a mirror, and turns the contact into a bump.

#### Why it looked impossible

```js
// tiles/Base.js
getBounds: function () {
  bounds.width = 4;
  bounds.x = this.roomX * 32 + 40;      // forty pixels into a thirty-two pixel cell
  bounds.y = this.roomY * 63;
  return bounds;
},
getBoundsAbs: function () { return new Phaser.Rectangle(this.x, this.y, this.width, 63); },
```

`roomX * 32 + 40` looks like a units error — it lands eight pixels into the *next* cell. It is not
an error, and it is not the only rectangle: `getBoundsAbs` uses the tile’s own origin, which
carries the 13-pixel cel overhang, and the full cel width. `getCharBounds` reads frame data and
`getCharBoundsAbs` reads the live sprite, and they disagree by a few pixels.

None of it has an engine-unit equivalent, because it is not physics. It is **screen-space
collision over cel sizes**, and cel sizes are in the atlas JSON. `SpriteMetrics` is the whole
answer: transcribe the arithmetic, measure the cels, done.

#### The four rectangles, and which asks for which

| Rectangle | Built from | Used when |
|---|---|---|
| `Tile.screenBounds` | `column * 32 + 40`, 4 x 63 | always, first |
| `Tile.screenBoundsAbs` | tile origin (overhang included), cel width x 63 | second, only unarmed |
| `ActorState.charBounds` | frame data, face-dependent x shift | always, first |
| `ActorState.charBoundsAbs` | live sprite position, half-pixel included | second, only unarmed |

A rectangle with **no area never intersects anything** — which is how a tile whose cel is missing
from the atlas stops colliding instead of colliding with the whole room. And because Phaser tests
separation with strict comparisons, two rectangles that merely **share an edge do intersect**. Both
are the reference’s, and the second is the one that is easy to read backwards.

#### One thing the geometry forced

`Behaviour.step`’s mirror and gate branches call `setBump`, and `setBump` ends the tick with
`processCommand`. So a behaviour verb may run the sequence — which is why `Behaviour.update` now
takes the interpreter. The reference’s own shape is that a verb *may* call `processCommand`, not
that it always does; the port had been assuming the latter because nothing had needed the former
yet.

#### What this closes

Open question 11 is closed. `checkBarrier` is implemented, the `step` verb’s chopper and mirror
branches are in, and the two stubs in `Behaviour` that said "needs `checkBarrier`" are gone.

**And it took `canReachOpponent` with it.** That was the last *simplification* in the port — a
distance test standing in for `checkPathToOpponent`, which walks the columns between the two
fighters asking a question about each. It measured from `centerX`, so it was blocked on the same
geometry, and it is now the real thing: two passes, one asking whether the corridor is clear and one
asking whether a fighter could stand his way along it, with the `below` variant letting the path
drop a row through a gap.

What it leaves is the ledge system — `tryGrabEdge`, `checkLedgeSwing`, the `jumphang*` verbs —
which now has everything it needs and has simply not been written.

### 7.9.11 Ledges

The last subsystem, and the one that had been waiting longest: everything it needed — hanging
states, the `jump` decision tree, screen-space geometry — existed before any of it was written.

#### The grab window is *when*, not just *where*

```js
let isInDistance =
  this.distanceToEdge() <= 10 + (["stepfall"].includes(this.action) ? 3 : 0) &&
  (this.distanceToTopFloor() >= -50 ||
   (["jumpfall", "freefall"].includes(this.action) && this.distanceToFloor() > -3));
```

`distanceToTopFloor` is `convertBlockYtoY(charBlockY - 1) - charY - charFdy`, which is **negative**
for a Prince below the floor of the row above. Standing on row 1 it reads `-63`, well outside the
`-50` the grab allows; the window opens only while his feet are still within fifty pixels of the
ledge he is trying to catch. So a fall has a grab window of a few ticks, and missing it means
missing it.

That is why a `stepfall` gets three extra units of reach: it is the slowest fall, and the reference
is compensating for how few ticks it spends in the window.

#### Two chances, in order

The ledge **in front** (`charBlockX + face`, reach 30) is tried first, then the one he is already
under (`charBlockX`, reach 20). The first is the ordinary case; the second is what catches a Prince
who has drifted past the edge and is falling down its face. `inGrabDistance` is asymmetric — offset
`+2` facing left, `-5` facing right — because the arm is drawn on one side of the body.

The tapestry exclusion is the odd one and is not a mistake: facing left you cannot catch a tapestry,
because a tapestry is a thing you stand *behind*, and catching one from the left would draw him in
front of it.

#### The one place `charX` is fractional

```js
checkLedgeSwing: function () {
  if (this.ledgeSwing >= 4) { this.charX += (this.inFloat ? 2.0 : 1.5) * this.charFace; }
}
```

**1.5.** `charX` is an integer everywhere else in the engine; here it is not, and the fraction
persists across ticks. The port keeps `charX` an `Int` and carries the half in
`ActorState.ledgeSwingHalves`, which reproduces the accumulated whole units exactly — four ticks
give +1, +2, +1, +2 — and loses only a sub-unit fraction, and only to comparisons that read `charX`
directly rather than through `convertX`.

This is the swing-to-momentum mechanic: work the ledge four times, let go, and the drop carries you
sideways. The float potion widens the drift from 1.5 to 2.

#### `grabWait` and the half-second

`grab` sets `grabWait` for 500 ms, which stops an action key held *through* the grab from pulling
him straight back up on the next tick. The port counts six ticks rather than reading a clock, the
same substitution the potion delay uses.

#### Verified in play

Level 1 room 12, walking right off the ledge at column 4 with the action key held: he falls, catches
the ledge at tick 18, and the loose board above him shakes — because column 2's row 0 *is* a loose
board. That is the level-1 opening, which the port could not previously play.
### 7.9.12 The `action` setter, and the bug it hid

The most consequential single fix in the port, and it was found by chasing something cosmetic.

```js
Object.defineProperty(PrinceJS.Actor.prototype, "action", {
  get: function () { return this._action; },
  set: function (value) { this._action = value; this._seqpointer = 0; },
});
});
```

**Assigning `action` rewinds the sequence cursor.** The port had it as a stored property, with
`beginAction` resetting the cursor by hand. That is equivalent everywhere except the one place that
assigned `action` *without* going through `beginAction`: `startFall`.

So a fall started from a `stand` resumed the `stepfall` sequence from wherever `stand` had left the
cursor — skipping the `ACT 3` at its head. The cascade from that one skipped instruction:

1. `actionCode` stayed 0, because `ACT` is what sets it.
2. `checkFloor` therefore took its *standing* branch, whose guard is `actionCode in {0,1,5,7}`.
3. That branch found space under him, called `startFall` again — every tick of the fall.
4. `startFall` does `fallingBlocks = Math.min(0, fallingBlocks)`, so the count was zeroed every
   tick and a two-floor drop never reached the `fallingBlocks === 2` that makes a medium landing.

**What that cost, silently:** gravity never applied during a `stepfall` (it needs `actionCode` 4,
and freefall did set it — which is why falls still looked roughly right), medium landings never
happened, and no fall ever did damage.

The fix is to make the setter do the reset, exactly as the reference does, rather than to patch
`startFall`. `GOTO` is the single opcode that deliberately bypasses the setter — going through it
would restart every jump from the top of its target and loop forever — and it now has its own
entry point saying so.

#### The lesson worth keeping

A stored property that *looks* like the reference’s but does not carry its side effect is worse
than a missing feature, because it works almost everywhere. This one survived from M2 to M6d.

### 7.9.13 The splash, and the order of two statements

```js
showSplash: function () {
  if (this.charName === "skeleton") { return; }
  if (["dropdead", "falldead", "impale", "halve"].includes(this.action)) { return; }
  this.splash.visible = true;
  this.splashTimer = 2;
}
```

Those four actions draw their own gore — impaling and halving in particular — so the pool stands
down for them. Which means the *order* of the calls is load-bearing: `damageLife` calls
`showSplash()` **before** it sets the action, so the blow that causes a death animation still shows
a pool. Set the action first and the last hit of every fight loses its splash. `CMD_DIE` is the same.

`die` itself does **not** show one — only the `DIE` opcode, `stabbed` and `damageLife` do. Putting
it in `die` is the obvious mistake, and it makes a spike death bleed onto the spikes.

The splash is a *child* of the actor sprite, anchored bottom-left and offset `(-6, -15)`, so it
inherits the actor’s flip and a mirror-image Prince bleeds on the other side. `-5` instead of `-15`
for a hit taken while crouching, which is what the medium landing uses.

#### And the medium landing was wrong

`Kid.land` calls `damageLife(true)` for a two-floor drop. The port had inlined a bare
`health -= 1`, which is not the same thing: `damageLife` calls `die` at one health. A Prince with a
single life left was landing, dropping to zero health, and **carrying on alive**.

### 7.9.14 The hourglass running out

`Interface.showRegularRemainingTime` raises `timeUp` at zero minutes, and `Game.timeUp` sends the
player to level 16 — a cutscene, which is not ported (open question 5). The port emits
`ActorEffect.timeUp` and the host ends the run, which is the part of the reference’s behaviour that
survives the cutscenes being missing. The scene stops ticking, so the last frame stays on screen.

Two arithmetic notes. Sixty minutes is **43,200 ticks** of 1/12 s, not 3,600 — getting that wrong
empties the hourglass after five minutes. And the final minute reads `remainingMinutes == 1`, not 0:
the countdown reaches zero only on the same tick that expires it, which is exactly why the bar
switches to a seconds readout for that minute.
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

### 7.10.1 The control layer

`Behaviour` is the port of `Kid.updateBehaviour` (`Kid.js:237-490`) plus the movement verbs
it dispatches to (`Kid.js:1223-1700`).

**It does not run the sequence.** In the reference `updateBehaviour` is called from
`updateActor` immediately before `processCommand`, so a verb only assigns `action` — which
restarts the sequence from index 0 — and the caller then executes it. That is
`ActorState.beginAction`, and the distinction from plain assignment is load-bearing:
`CMD_GOTO` assigns `_action` **directly** and must *not* reset the cursor, or every sequence
would loop from the top. Getting this wrong is the single easiest way to make the control
layer silently resume mid-sequence, and it bit the reference tracer during M3b.

#### Two traps in the verbs

**`step` builds its action name from the distance:** `"step" + min(px, 14)`. That is why the
animation table carries `step1` through `step14` as fourteen separate sequences. The Prince's
final resting position at a ledge depends on which one runs, so `px` is not cosmetic.

**`runstop` only fires on frames 7 and 11** of the run cycle. Releasing the key at any other
frame does nothing, which is why the Prince cannot stop instantly.

#### Implemented vs deferred

| Verb | Status |
|---|---|
| `turn`, `standjump`, `startrun`, `runturn`, `turnrun`, `runjump` | ✅ |
| `rdiveroll`, `standup`, `crawl`, `runstop`, `stoop`, `step` | ✅ |
| `nearBarrier`, `canCrossGate`, `distanceToEdge` | ✅ |
| `jump` | ❌ not a verb — see below |
| `checkBarrier` | ✅ §7.9.10 — transcribed, not re-derived |
| `tryGrabEdge`, `grab`, `climbup`, `climbdown`, hang states | ❌ need `checkBarrier` |
| `advance`, `retreat`, `block`, `strike`, `fastsheathe`, `tryEngarde` | ❌ combat (M6) |

**`jump()` is not a verb.** It is a decision tree over five tile probes (`tile`, `tileT`,
`tileTF`, `tileTR`, `tileR`) that routes into the entire ledge system — `checkJump`,
`checkClimbable`, `jumphanglong`, `jumpbackhang`, `jumpup`, `highjump`, `climbstairs` — and
into `tile.open` for exit doors. It cannot be done before the hanging states are.

**`checkBarrier` reads Phaser sprite bounds**, and `Tile.Base#getBounds` computes
`x = roomX * 32 + 40` — mixing screen pixels with engine units. Untangling that faithfully,
without changing when the Prince bumps, is its own piece of work.

#### The gate hook

`nearBarrier` calls `canCrossGate` with `walk` and `turn` both **false**, which short-circuits
the `(!walk || centreX …)` clause. That is a happy accident of the reference: it means the
locomotion path needs no screen-space geometry at all. The remaining gate test is
`tile.canCross(height)`, surfaced as `TileWorld.gateBlocks` — which correctly answers "yes,
blocking" until M7 wires the animated state, because gates begin closed.

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

### 7.13 Distribution

`Scripts/make-app.sh` assembles `Prince.app`: the release binary, an `Info.plist`, the SwiftPM
resource bundle, an icon, and an ad-hoc signature. About 9 MB, and `swift build` is the only
prerequisite.

#### Why SwiftPM and not an Xcode project

The architecture document originally said "Xcode project for a signed `.app` bundle". That is the
wrong shape for this codebase, and the reason is the test loop. The risky part of this port is the
*simulation* — a few hundred headless tests running in half a second — and SwiftPM is what makes that half a
second. An Xcode project would put the fast loop behind a GUI, and the bundle is twenty lines of
`cp` either way, so the project would buy nothing that the script does not.

#### Closing the window quits

AppKit does not terminate when the last window closes. The default is right for an app with
documents to keep open or a window to reopen, and wrong for this one: there is a single window, no
document, and nothing to come back to. So `AppDelegate` answers
`applicationShouldTerminateAfterLastWindowClosed` with `true`. Without it, closing the window leaves
a game running invisibly behind its own Dock icon.

`NSApplication.delegate` is a **weak** reference, so the delegate is held by a top-level `let` in
`main.swift` — which is a global, and lives as long as the process. A delegate assigned inline and
not stored is deallocated immediately and never called.

A Window menu with Close and Minimise came with it. Not for its own sake: without a menu item
carrying Cmd-W there is no way to close the window except the red button, and the delegate above
would be almost unreachable.
#### Why the signature is ad hoc

`codesign --sign -` is a local, verified-at-launch signature that satisfies the *system*. It is not
notarised, so the app will not run on another Mac without the usual override. Signing properly needs
a Developer ID, which needs an Apple Developer account, which is a decision about the project rather
than about the code. Left honestly undone rather than faked.

#### The one thing that had to be right

`Bundle.module` finds the SwiftPM resource bundle by searching, among others,
`Bundle.main.resourceURL`. In an app bundle the executable is in `Contents/MacOS`, so the resource
bundle has to land in `Contents/Resources` — **not** next to the binary. Getting that wrong gives
an app that launches and immediately dies on a missing level file. The script puts it in the right
place and the build was verified by running the bundle: level 3 loads and ticks.

#### The icon

`Scripts/make-app.sh` prefers a designed `appicon.png` at the repo root and scales it through the ten
sizes `iconutil` wants. Two notes on it.

**The master is 1024 × 1024 and has no alpha channel.** macOS does not mask app icons the way iOS
does, so a fully opaque square renders as a fully opaque square in the Dock and in Finder. That is a
legitimate style — plenty of apps ship full-bleed icons — but it is a *choice*, and the alternative
is to round the corners in the artwork and let the transparency through.

**The fallback is the game’s own `cover.png`**, centre-cropped, kept so the script still works in a
checkout that does not have the artwork.

### 7.14 Key bindings

The original shipped a key-configuration screen. This does the same job the way a modern Mac game
does it: a JSON file at
`~/Library/Application Support/PrinceOfPersia/keys.json`, written from the defaults on first launch
and editable afterwards. An **Options** menu opens it, and offers a reset.

Two decisions worth stating.

**Application Support, not the bundle.** A `.app` is signed and read-only, and the entire point of
the file is that it can be edited.

**Loading never fails.** `KeyBindings.load` falls back to the standard bindings for a missing file,
an unreadable one, or a typo in the JSON. A game that refuses to start because a configuration file
is malformed is worse than one running with the defaults.

The interesting part of the implementation is that `intents(pressed:shiftHeld:)` is a **pure
function on a value type**, with no AppKit in it. That is what makes rebinding testable — a test
hands it a set of key codes and asserts what the simulation would see — and it is the same split
Law 6 asks for between the keyboard and the simulation. `KeyboardInput` does nothing but supply the
two inputs.

Shift has a wrinkle: it is a *modifier*, so it does not arrive as a key-down in a local event
monitor and cannot be read from the pressed-key set. It is sampled from `NSEvent.modifierFlags`
instead, which also keeps it correct across focus changes. `shiftIsAction` can be turned off for a
player who binds the action to a letter.
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
| **M9** | Polish: app bundle, icon, keybinding config, distribution decision | A double-clickable `.app` — **done:** `Scripts/make-app.sh` |

**M2 is the milestone that de-risks everything.** If the VM is right, the rest is content and
plumbing. If it is wrong, nothing downstream will ever feel correct.

---

## 10. Open questions

1. **Combat tick rate** — global 1/10 s switch, or per-actor? Verify in `SDLPoP/src/seg000.c`.
2. ~~**Gameplay RNG**~~ — **RESOLVED, and it cost nothing.** SDLPoP's `prandom` is:
   ```c
   word prandom(word max) {
     random_seed = random_seed * 214013 + 2531011;
     return (random_seed >> 16) % (max + 1);
   }
   ```
   — **the same MSVC linear congruential generator already ported in M3** for wall patterns. The
   guard AI now draws from it, so fights are reproducible from a seed. PrinceJS cannot do this:
   its guard decisions come from Phaser's `rnd`, seeded from the clock.
3. ~~**Coordinate representation**~~ — **RESOLVED in M2.** `Int` throughout, in the engine's
   own units: `charX` in x-units (140/room), `charY` in pixels (189/room). The `+0.5` is
   render-only. See §7.4.
4. **Screen geometry** — room is 320 × 189 inside a 320 × 200 screen. How is the remaining
   11 px reconciled with `UI_HEIGHT = 8`? Check SDLPoP at M4.
5. **Level chain and cutscenes** — how the 14 levels, 12a/12b split, princess level and the
   shadow sequence are ordered. Read `Cutscene.js` and `Game.js` before M8.
6. **SDLPoP-only extensions** — fake tiles, added tile+modifier combos. Opt-in extras, off by
   default. Never let them leak into the faithful core.
7. **Assets** — stay Ubisoft's. Keep them swappable; replacing them must remain a content job.
8. ~~**Actor `location` convention**~~ — **RESOLVED in M3. Actors use `location % 10` /
   `location / 10`; only events use `location - 1`.**

   SDLPoP confirms it in three independent places, all authoritative:
   - `seg003.c:665` `pos_guards`: `x_bump[(guard_tile % 10) + FIRST_ONSCREEN_COLUMN]`
   - `seg003.c:138` `do_startpos` (the Prince): `Char.curr_col = x % SCREEN_TILECOUNTX`
   - `seg005.c:1142` (teleport landing): `Char.curr_col = dest_tilepos % 10`

   This was not academic: **all 55 actor spawns across the fourteen levels disagree** between
   the two conventions, so every guard and the Prince would have been one column off. SDLPoP
   also corroborates the coordinate units independently — `types.h` defines
   `TILE_SIZEX 14` ("a tile is 32 pixels wide in screen space") and `TILE_MIDX 7`, which
   match `x-unitsPerTileColumn` and `convertBlockXtoX` exactly.
9. ~~**Sword offset indexing**~~ — **RESOLVED while reading `Fighter.updateSwordFrame`:**
   ```js
   let stab = this.swordAnims.swordtab[framedef.fsword - 1];
   this.swordFrame = stab.id;
   ```
   `fsword` is a **1-based positional** index into the array; the `id` field is the sprite frame
   name, not the key. Use `SwordOffsetTable.offset(at: fsword - 1)` in M7. (`offset(id:)` remains
   for reading the data, but nothing indexes by it.)
10. ~~**Room-edge tile resolution**~~ — **RESOLVED in M5.** `LevelRuntime.tile(x:y:room:)`
   now follows `Level.js#getRoomX`/`#getRoomY` exactly, and `RoomRowTransitionTests` pins the
   behaviour against a reference trace that crosses two rooms.

   This was worth doing: the M3b turning trace showed the Prince refusing to run because he
   saw off-map wall where the neighbour had open floor.
13. **Two different cross-room lookups exist, and they are not equivalent.**
   `Level.getTileAt` chains: it applies X, and only if that failed does it apply Y and then X
   again. `LevelBuilder.getTileObjectAt` applies all four offsets independently, against the
   *original* room's grid position, so a corner lookup crosses both axes at once.
   `LevelRuntime.tile` implements the `Level.getTileAt` form, which is what the simulation
   uses; the renderer's wall-shape probe only varies x, where the two agree. If a future
   feature needs corner resolution, it needs the second form, not a tweak to the first.
12. **Palace wall colour overlays** — dungeons pick pre-drawn wall-shape frames, but a
   *palace* wall is composited at runtime: `LevelBuilder` fills a `bitmapData` with
   `wallColor[wallPattern[roomId][…]]` and adds a `W_<seed>` child. `wallPattern` is generated by
   the LCG (which is ported and tested), but the six-rectangle composite is not. Palace walls
   currently draw their shape child without the colour, so they look flatter than the original.
   Level 4 is the first palace level.
11. ~~**`checkBarrier`'s bounds geometry**~~ — **RESOLVED in M3c, and the premise was wrong.**
   The question assumed there *was* an engine-unit equivalent to find. There is not, because
   `checkBarrier` is not physics: it is screen-space collision over cel sizes, and the cels are in
   the atlas JSON. `SpriteMetrics` reads them, and the four rectangles are transcribed —
   `(roomX * 32 + 40, roomY * 63, 4, 63)` and all. See §7.9.10.

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
| M0 | `swift-tools-version: 6.2`, `.macOS(.v26)` | 6.0's manifest has no `.v26` platform case; 6.2 verified building on Swift 6.3.3 |
| M0 | Window scale is a runtime switch, not a compile-time constant | Guaranteed free to change by Law 8; `--scale N` and a View menu, capped to the display |
| M9 | Closing the last window quits the app | There is one window and no document, so leaving the process alive means an invisible game behind a Dock icon |
| M9 | A Window menu with Close and Minimise | Without a Cmd-W menu item the close button is the only way to close the window, and the quit-on-close rule would rarely be reached |
| M9 | The `.app` is assembled by a script, not an Xcode project | The risky part is the simulation, and SwiftPM is what makes its tests run in half a second. The bundle is twenty lines of `cp` either way |
| M9 | The resource bundle goes in `Contents/Resources`, not next to the binary | That is where `Bundle.module` searches. Getting it wrong gives an app that launches and dies on a missing level file |
| M9 | The signature is ad hoc, and that is documented rather than worked around | A Developer ID needs an account, which is a decision about the project rather than about the code |
| M9 | Key bindings live in Application Support, not the bundle | A signed `.app` is read-only, and the point of the file is that it can be edited |
| M9 | `KeyBindings.load` never throws and never fails | A game that will not start because a config file has a typo in it is worse than one running with the defaults |
| M9 | The binding decision is a pure method on a value type | It makes rebinding testable without a window, and it is the same split Law 6 asks for |
| M6d | `ActorState.action` is a computed property whose setter rewinds `sequencePointer` | That is what the reference’s `action` setter does. As a stored property it worked everywhere except `startFall`, which skipped a `stepfall`’s `ACT 3` and cascaded into `actionCode`, `checkFloor` and `fallingBlocks` |
| M6d | `GOTO` assigns through `assignActionDirectly` | The one opcode that bypasses the setter; going through it would restart every jump from the top and loop |
| M6d | `Splash.show` is called before the action changes | `showSplash` refuses the four self-bloodying death animations, so the order decides whether a killing blow bleeds |
| M6d | `die` does not show a splash | Only the `DIE` opcode, `stabbed` and `damageLife` do. Putting it in `die` makes a spike death bleed onto the spikes |
| M6d | The medium landing calls `damageLife`, not a bare `health -= 1` | `damageLife` calls `die` at one health; the inlined version left a Prince at zero health and alive |
| M6d | `timeUp` ends the run rather than going to level 16 | Level 16 is a cutscene, and cutscenes are not ported. The effect and the handling are both real; only the destination differs |
| Ledge | `tryGrabEdge` is two probes, front (reach 30) then overhead (reach 20) | The second catches a Prince who has drifted past the edge and is falling down its face |
| Ledge | `charX` stays `Int`; the fractional swing is carried in `ledgeSwingHalves` | `checkLedgeSwing` adds 1.5 a tick, the only fractional `charX` in the engine. Carrying the half reproduces the whole units exactly |
| Ledge | `grabWait` counts six ticks rather than reading a clock | The same substitution as the potion delay: 500 ms at 1/12 s |
| M3c | `canReachOpponent` is the real path walk, not a distance test | `SpriteMetrics` unblocked it along with `checkBarrier`. A guard can no longer engage through a wall the original would have stopped at |
| M3c | `checkPathToOpponent` keeps the reference’s `+ 10` widening for a cross-room opponent | It is what lets a guard at a doorway reach into the next room; without it guards never notice a Prince in the next room |
| M3c | `checkBarrier` is transcribed screen geometry over cel sizes, not a physics model | Every rectangle in it comes from measured cels; trying to re-derive it in engine units was the mistake that kept open question 11 open |
| M3c | `Behaviour.update` takes the interpreter | Two of its verbs call `setBump`, which ends the tick with `processCommand`. The reference lets a verb run the sequence; it does not require it |
| M3c | `ScreenRect` lives in `PoPCore/Sim`, not `Render` | It is collision, not drawing. The Render layer happens to use the same cel sizes |
| M7c-2 | `Level.activateChopper` takes a starting column, and the two callers differ | `checkChoppers` passes `-1` for the leftmost blade; `onChopped` passes its own column for the next one along. Reading it as always-leftmost makes a multi-blade row walkable |
| M7c-2 | `SpriteMetrics` reads cel sizes from the atlas JSON into `PoPCore` | `chopDistance` and `checkBarrier` both measure Phaser sprite centres, and a sprite is as wide as its current frame. The table is data, not a framework, and a headless test can reach it |
| M7c-2 | `chopDistance` measures the live state, not the previous tick’s sprite | The reference reads a transform that `updateCharPosition` left stale. That lag is a Phaser artefact; the DOS original had none |
| M7c-2 | `Chopper.frameIndex` is 5 when idle, never 0 | There is no frame 0 in the atlas: `update` increments before naming a frame |
| M7c | Spikes, potions and swords are trobs, driven by actors rather than by buttons | The reference raises a field from inside the actor’s own check; a button-driven model would miss the case where two actors disturb the same field |
| M7c | `checkSpikeFloor` is separate from `FallCycle.checkFloorStanding` | Raising a field mutates the world; the falling branch only reads. The guard duplication is deliberate and the branches are mutually exclusive |
| M7c | Potion effects are queued as `PendingPotion` on `World` and applied twelve ticks later | The reference delays them 1000 ms so the drink animation reads; twelve ticks is that second without a clock |
| M7c | `ActorEffect.music` exists alongside `.sound` | Phaser’s `sound.play` plays music keys too, and three call sites name a music file |
| M7c | `SpriteInstance` carries an optional `atlas` | A potion’s bubbles live in `general`, which belongs to no tile and no actor; guessing by trying every sheet would collide sooner or later |
| M7c | `World.apply` is handed only the effects it has not seen | It was being handed the whole accumulated array once per stage, which is invisible for an idempotent effect and wrong for a counting one |
| M7c | The special-potion event path is not built | `POTION_SPECIAL` is 6 and no shipped level contains one; there is nothing to test it against |
| M8b | Music plays once and does not loop | Phaser’s `SoundManager.play` defaults `loop` to false, so every cue in the reference is a one-shot. Looping them was audible within seconds of launching |
| M8b | Sound reaches the host as `ActorEffect.sound`, not as a callback from the model | The reference plays sound by global side effect; the effect channel keeps `PoPCore` free of AVFoundation (Law 5) and a headless test silent |
| M8b | The effects sink is an explicit `inout` parameter, not a `pendingSounds` array on `ActorState` | A field would leak into `Equatable` and would make "never ticked" indistinguishable from "no sounds" |
| M8b | `Gate`/`ExitDoor`/`LooseBoard.update()` return `SoundEffect?` | The sound is produced by the same call that moves the sprite, so the two cannot drift apart |
| M8b | `AVAudioPlayer` with three voices per effect, not `AVAudioEngine` | The bank is mp3 and the overlap is bounded at three; an engine is a mixing graph for a problem that does not exist here |
| M8b | `Loose.shake` always plays the first of the three shake variants | The reference picks with `Utils.random(3)`; the three are the same shake at different trims, and a generator in a tile update is not worth the cosmetic difference |
| M8b | A failed asset disables one effect and logs once | Audio is presentation (Law 8); it must never be able to stop the game running |
| M8 | The clock counts simulated ticks rather than reading a wall clock | Identical under a fixed timestep, but no drift on dropped frames and reproducible from a seed |
| M8 | Text layout lives in `PoPCore`; the host only draws positioned glyphs | Same split as sprite rendering — the host has nothing to measure |
| M6c | Level chaining lives in `PoPHost`, the trigger in `PoPCore` | The simulation emits an effect; only the host knows levels are numbered |
| M6c | The next-level decision is a `nonisolated` pure function | It is the one part of the coordinator that can be tested without a window |
| M6c | Added a `PoPHostTests` target | Host policy — chaining, window scale, atlas slicing — otherwise accumulates in the scene where nothing can reach it |
| M6b | `Simulation` owns the tick, in `PoPCore` rather than the scene | It is game logic; keeping it here means a duel runs headlessly and the scene has no rules in it |
| M6b | The Prince is fixed at actor index 0 | Combat must name an opponent; an index is the value-type equivalent of the reference's object reference |
| M6b | Actors are copied out of the array between steps | Assigning through `world.actors[i]` while handing `world` to a function is an exclusivity violation; the copy is the honest fix |
| M6 | Guard AI uses the LCG already ported for wall patterns | SDLPoP's `prandom` is the same generator; PrinceJS's is clock-seeded and not replayable |
| M6 | `damageLife` calls `die` at one health rather than reaching zero | The reference picks `stabkill` vs `stabbed` by testing `health === 0` after damage |
| M6 | Combat verbs stay frame-gated, with no responsiveness smoothing | The animation is the state machine; loosening it would change how the game plays |
| M7b | A collapsing board is modelled as a `TILE_SPACE` override | That is literally what `floorStartFall` does; nothing special-cases the Prince falling |
| M7b | `ExitDoor` tracks `visibleHeight` rather than Phaser's crop bookkeeping | The reference's terminator works only via a rendering library's side effect; the intent is unambiguous |
| M7b | Behaviour gained an effects channel, with the old signature kept | Climbing past a board and revealing an exit door change the world, and reaching into the level from Behaviour would break the layering |
| M7 | `LevelRuntime` immutable + `LevelState` mutable, paired by `World` | Keeps level data cheap to share and `Sendable`, and lets a test reset the world without reloading |
| M7 | A button's `modifier` is an event **index**, not the entry's `number` | Level 1's room-5 buttons (modifiers 8, 9, 11) all resolve to room-5 events; the other reading points one of them at room 8 |
| M7 | `Gate.actorPassageHeight` is a constant, not the live sprite height | The reference reads a frame-varying Phaser sprite (38–42); the DOS original used fixed cels, so a constant is arguably closer |
| M7 | A rising gate is a top-clip, resolved by the host | Matches Phaser's crop exactly, and needs no y arithmetic because `SKTexture(rect:in:)` measures from the bottom-left |
| M5 | `updateBlockPosition` takes the world, so room wrapping happens inside the VM | `CMD_FRAME` is the only caller of `updateBlockXY` in the reference; keeping it there preserves the ordering |
| M5 | `charX` stays room-local across a transition | The reference shifts it by a whole room (140 x-units) and moves `baseX` by 320 px, so the two unit systems never mix |
| M5 | Kid and Fighter keep separate `checkRoomChange` thresholds | The Kid fires at 189, the Fighter at 192. Tidying them into one would change when the Prince drops out of a room |
| M4 | Frame selection lives in `PoPCore`, not the host | Which frame a tile draws, and whether it draws over an actor, is game logic |
| M4 | `RenderDescription` positions are room-local, y-down, integer | The engine's own space; the host does the single flip and never sees engine units mixed with screen ones |
| M4 | Added a `--dump-frame` diagnostic | Caught the `SKTexture(rect:in:)` bottom-left origin, which fails silently rather than loudly |
| M4 | `checkFloor`'s standing branch implemented; `isInFallDistance` still stubbed | Without the standing branch the Prince stands in mid-air at level 1's spawn. The stub only affects running actions |
| M3b | `Behaviour` sets an action; it never runs the sequence | The reference calls `updateBehaviour` then `processCommand`; merging them would run two dispatches per tick |
| M3b | Gate state surfaced as `TileWorld.gateBlocks`, defaulting to blocking | Gates begin closed, so this is correct until M7 animates them |
| M3b | `jump` deferred rather than approximated | It is a decision tree into the ledge system, not a verb; a guess would be untestable |
| M3 | Actor `location` is `% 10` / `/ 10`; events use `location - 1` | Confirmed in SDLPoP ×3 (`pos_guards`, `do_startpos`, teleport). All 55 actor spawns would have been one column off |
| M3 | `Fighter.checkRoomChange` keeps its `192` threshold | The room is 189 tall; the reference's value is reproduced rather than tidied |
| M3 | `LevelRuntime` is a value type and `ActorWorldQuery` is `Sendable` | The world is immutable within a tick, so the simulation can hold it cheaply |
| M3 | Ticker absorbs float drift with a small epsilon | 120 frames of 1/60 sum to just under 2.0; without it 10 Hz reports 19 ticks instead of 20 |
| M2 | Opcode tables are per actor class, not one flat union | `fighter.json` uses `JARD`, `shadow.json` uses `EFFECT`/`IFWTLESS`, `mouse.json` uses `ACT` — all silent no-ops in the reference |
| M2 | Simulation is `Int` in engine units; `+0.5` is render-only | `updateVelocity` and `GRAVITY` are integral; nothing fractional exists to represent |
| M2 | Added a 4096-instruction budget to the dispatch loop | The reference hangs on a bad `GOTO`; unreachable on valid data (longest sequence is ~80 instructions) |
| M2 | `Fighter`'s `location % 10` reproduced verbatim, isolated in one initialiser | Open question 8 is unresolved; fidelity to the port source beats a guess |
| M1 | Events modelled as `[EventTrigger?]`, holes preserved | `fireEvent` addresses events by index; compacting silently renumbers them |
| M1 | `FrameDef` numeric fields are optional | 33 comment-only `framedef` entries exist across the shipped tables |
| M1 | `guard.reverse` / `prince.reverse` are `Int?`, not `Bool?` | The data stores `-1`; a `Bool` would decode cleanly and drop every reversal |
| M1 | Rooms with `id == -1` decode to an empty `tiles` array | 200 of 476 room slots carry no `tile` key at all |
| M1 | Game assets bundled in `PoPCore`, not `PoPHost` | The data layer must be exercisable headlessly by `PoPCoreTests` |
| M1 | `sword.json` is `SwordOffsetTable`, not an `AnimationTable` | Same extension, different schema (`swordtab` only) |
| M0 | Exclude `maps/custom/` and `assets/web/` from the bundle | 212 third-party levels and 18 MB of website graphics are not part of the game |
