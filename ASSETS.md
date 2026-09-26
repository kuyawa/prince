# Assets, and what they are doing here

This repository contains two different kinds of thing, and they have two different owners.
This file is about the second one.

| | |
|---|---|
| **The Swift source** | The author's own work. MIT — see LICENSE. |
| **The game's assets** | **Ubisoft's.** Included under the terms below. |

---

## What the assets are

About 7.8 MB of the original game, in `PrinceOfPersia/Sources/PoPCore/Resources/`:

| Directory | Contents |
|---|---|
| `gfx/` | Sprite sheets — tiles, characters, the title screen, the sword |
| `anims/` | Animation tables: the opcode sequences and frame definitions |
| `maps/` | The fourteen levels, as tile grids, guard placements and event lists |
| `music/` | The soundtrack |
| `sfx/` | Thirty-three sound effects |
| `font/` | The status bar's bitmap font |
| `cutscenes/` | Frames for the cutscenes, which are not ported |

`build/Prince of Persia.app` embeds a compiled copy of all of it, and everything in
`screenshots/` plus `appicon.png` is derived from it.

## Why they are here

**A port of a game cannot ship without the game.** The simulation, the level data and the
artwork are one artefact: the port's whole claim is that it reproduces the original
faithfully, and that claim is unverifiable — and the thing unrunnable — without them.

## Where they came from

The assets were taken from [PrinceJS](https://github.com/oklemenz/PrinceJS), which had
already extracted them from the original game into a usable form. That project is released
under [The Unlicense](https://unlicense.org), which places *its code* in the public domain.
It does not, and cannot, do the same for the artwork it redistributes.

## The position

Written better than I could put it, by the person who made the game — from Jordan
Mechner's README accompanying his 2012 release of the Apple II source code:

> We extracted and posted the 6502 code because it was a piece of computer history that
> could be of interest to others, and because if we hadn't, it might have been lost for
> all time. We did this for fun, not profit. As the author and copyright holder of this
> source code, I personally have no problem with anyone studying it, modifying it,
> attempting to run it, etc. Please understand that this does NOT constitute a grant of
> rights of any kind in Prince of Persia, which is an ongoing Ubisoft game franchise.
> Ubisoft alone has the right to make and distribute Prince of Persia games.

So:

* **This is a preservation and study project.** It is not a product and it is not for
  sale. It exists to demonstrate a port, and to be read.
* **No rights in Prince of Persia are granted or claimed here.** The MIT licence covers
  the Swift source and nothing else.
* **If you are Ubisoft and you would like this taken down, it will be.** Open an issue on
  this repository and it will be removed — no argument, no delay.
* **If you want to use the code, take it.** That is what MIT is for. Take it without the
  assets and you have a Prince of Persia engine with no game in it, which is a perfectly
  reasonable thing to want.

## Building without the assets

There is no switch for this. `PoPCore` loads its data through `GameData`, which reads from
the SwiftPM resource bundle, and every level, animation and sound comes from there. Deleting
`Resources/` gives you a project that compiles and fails at the first level load.

If you want the engine alone, that is the seam to work at — and it is a clean one, because
`GameData` is the only thing in the whole port that touches the filesystem.

## The reference implementations

Three projects were read while writing this port, and `ARCHITECTURE.md` section 2 records
what each contributed. None of their code is present in this repository — `reference/` is
git-ignored — and nothing was transcribed from the GPL one.

| Project | Licence | Role |
|---|---|---|
| [PrinceJS](https://github.com/oklemenz/PrinceJS) | The Unlicense | The port source, and where the assets came from |
| [SDLPoP](https://github.com/NagyD/SDLPoP) | GPLv3 | Read as a behavioural oracle only. Never transcribed. |
| [POP-AppleII](https://github.com/jmechner/Prince-of-Persia-Apple-II) | Mechner's terms, above | Historical reference, not a port source |

