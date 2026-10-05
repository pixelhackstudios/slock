# Slock

**A Pixelhack Studios Production, in association with Scott O'Nanski.**

Tilt the world to slide a jelly block through an endless, procedurally generated maze.

**[Visit the Slock website](https://pixelhackstudios.github.io/slock/)** to watch the teaser and try tilting a corridor.

## ▶ Download & play

**[Get the latest build from the Releases page](https://github.com/pixelhackstudios/slock/releases)**. It's free, and there's nothing to install.

| | |
|---|---|
| **Windows** | Download `Slock-Windows.zip`, extract it, run `Slock.exe` |
| **Mac** | Download `Slock-Mac.zip`, extract it, then **right-click `Slock.app` → Open** (it isn't signed by Apple yet, so a normal double-click is blocked the first time) |
| **Linux** | Download `Slock-Linux.tar.gz`, extract it, run `Slock/Slock.x86_64` |

Slock is in early development. If it doesn't start or something breaks, please [open an issue](https://github.com/pixelhackstudios/slock/issues).

![Slock gameplay](docs/screenshots/gameplay.jpg)

| | |
|---|---|
| ![Power mode: the Swurms turn blue and edible](docs/screenshots/power-mode.jpg) | ![A side room full of gold pellets](docs/screenshots/side-room.jpg) |
| ![The course climbs away into the void](docs/screenshots/overview.jpg) | ![Deeper sections have smaller blocks and denser mazes](docs/screenshots/deep-section.jpg) |

## How to play

You are **Slock**, a red jelly block. You don't move Slock — you **tilt the world** and Slock slides downhill.
Eat every blue pellet in a section (or find its key) to open its gate, go through, and keep climbing before the clock runs out.
Make the top ten and your name goes on the leaderboard (it's kept on your computer).

### Controls

| | |
|---|---|
| **Mouse** (or gamepad left stick) | Tilt the world |
| **Left click** | Aim a slug — left click again to fire |
| **Right click** | Cancel aiming (keeps the slug) |
| **Esc** | Pause |
| **R** | Restart |
| **Q** | Quit (from the title or pause screen) |

### Moving

- Tilt gently to **creep**; tilt hard to **slide**. Level the board and Slock stops. The dial in the corner shows
  your tilt: inside its small ring is level.
- Slock runs along the corridors and turns into side openings when you tilt toward them — but come in too fast and you'll slide right past.
- **Holes and open edges are deadly.** Fall off and the run is over.

### The clock

You start with **35 seconds**. Keep it topped up:

| | |
|---|---|
| Blue pellet | +1 second |
| Gold pellet (side rooms) | +2 seconds |
| Clock (side rooms) | +20 seconds |
| Getting through a gate | Bonus time |

### Swurms

Green jelly worms that crawl out of the pen in the middle of each section, **one at a time**. There's one more of them in every new section.

- **Touch one and it steals a third of your time**, and you bounce apart.
- **Grab a big gold power pellet** and they turn **blue** for 10 seconds (+5 seconds on your clock). Blue Swurms are slow — **eat them** for **+10 seconds**, plus all the time they stole from you.

### Slugs

Slugs are a store you build up. You start with **3**, unspent slugs carry over, slug pickups add to the store, and each gate adds **4, then 5, then 6...** on top of whatever you're carrying.

1. **Left click** — the game freezes and you're in aim mode. **Right click** backs out without using the slug.
2. **Tilt** to aim. The one thing you'll hit glows **red**: a Swurm, or an inner wall block, up to **4 tiles** away.
3. **Left click** again to fire. A Swurm is destroyed (+10 seconds plus its stolen time) or a wall block is blasted open.

Outer walls can't be broken. A missed shot is still a used slug.

### Powerups

Each section has three powerups scattered at random, and they work the moment you touch them. Ten seconds after you take one, a new one appears somewhere you've already cleared.

| | |
|---|---|
| Three blue dots | A quarter of the section's pellets vanish (at most one per section) |
| Steel block | **Slock of Steel** for 10 seconds: push into an inner wall to smash it, and Swurms you hit are smashed too |
| Three slugs | +3 slugs |
| One big slug | One extra slug |
| Green patch | Every hole is filled in and every gap in the outer walls is closed off, in the section and its side room (at most one per section) |

### Gates and sections

- The gate at the far end opens when you've **eaten every blue pellet** in the section — or found its **key**. Gold and power pellets only add time.
- Once you're through, the way back seals behind you.
- Every section has **smaller blocks** (so more of them), more Swurms and more holes. Slock shrinks to fit.
- Some sections have a **side room** down a ramp off the left wall: gold pellets, and a clock or the gate's key.

## Play from source, or build it

Slock is made with **[Godot 4.7](https://godotengine.org/download)** — free and open source, nothing to sign up for.
The standard build is all you need (not the .NET one: the game is written in GDScript).

1. Open Godot, click **Import**, and choose this folder's `project.godot`.
2. Press **F5** (or the ▶ button) to play.

To make a build you can share, use **Project → Export** and pick **Linux**, **Windows** or **Mac** (the presets are
included; Godot offers to download its export templates the first time). Put builds in `Builds/`, which git ignores.

### Where things are

| | |
|---|---|
| `scripts/` | The game, in GDScript: `main.gd` runs a run, `section.gd` builds each section from the layout `maze_gen.gd` generates (out of the maze kit's pieces), `slock.gd` is the block you tilt |
| `textures/`, `models/`, `sounds/` | The art the game uses: the maze kit and the pickups are in `models/`, the maze's textures in `textures/maze/` |
| `art-work/` | Source art, and the scripts that turn it into the above: `models.py` builds every model and the maze's textures in [Blender](https://www.blender.org) (`blender -b --python art-work/models.py`), `sounds.py` makes sound effects. The top of each says how to run it |
| `slock-web/` | The website |

## Contributing

1. **Fork** this repo on GitHub, then clone your fork.
2. Make your changes on a new branch and push them to your fork.
3. Open a **pull request** here describing what you changed and why.

## Licence

Code: [MIT](LICENSE). Art: [CC BY 4.0](LICENSE-ART.md). Please credit Pixelhack Studios (Scott O'Nanski) — https://www.pixelhackstudios.com

## Support

Slock is free. If you enjoy it and want to help keep it going, you can [buy me a coffee](https://buymeacoffee.com/d0qtanhk43) ☕
