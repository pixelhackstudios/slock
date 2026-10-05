# Slock's website

https://pixelhackstudios.github.io/slock/ — one page that shows the game, made from the game itself: the maze, pellets,
pickups and Swurms are the game's own models and textures, exported from the real game code, and Slock slides by the
game's rules (mouse, or a phone's tilt). Scrolling moves the camera from shot to shot.

Built with [Vite](https://vite.dev), [three.js](https://threejs.org) and [Lenis](https://lenis.darkroom.engineering).
GitHub builds and publishes it whenever `website/` changes on `main` (`.github/workflows/pages.yml`).

## Run it on your computer

You need [Node.js](https://nodejs.org) 22 or newer.

```
cd website
npm install
npm run dev
```

Then open the address it prints (http://localhost:5173/slock/).

## Where things are

| | |
|---|---|
| `index.html`, `src/styles.css` | The page: its words and its look |
| `src/main.js` | Scrolling, the mouse and phone tilt, the download buttons (`src/downloads.js`) |
| `src/director.js` | Where the camera looks for each part of the page |
| `src/world/` | The game's world in three.js: the look (`look.js`, ported from the game's materials and shaders), the sections, Slock and how it moves (`slock.js`), the Swurms, and the autopilot that plays when nobody's steering |
| `public/world/` | Exported from the game (don't edit by hand; see below) |
| `public/media/` | The film of a run, recorded in the game |

## After changing the game

When the maze kit, textures or pickups change, export the world again (from the repository root, with Godot 4.7):

```
godot --path . --script website/tools/export_world.gd -- 20261005 6
cd website && npm run world
```

The first line writes the first six sections of the course with seed 20261005 into `public/world/`, the second
compresses them (run it once after each export: compressing twice loses a little detail).

To record the film again (Godot's movie maker, about ten minutes):

```
godot --path . --write-movie run.avi --fixed-fps 30 --script website/tools/record_run.gd
ffmpeg -ss 0.1 -i run.avi -vf "scale=1280:720:flags=lanczos,format=yuv420p" -c:v libx264 -preset slower -tune animation \
  -b:v 1500k -pass 1 -an -f null /dev/null
ffmpeg -ss 0.1 -i run.avi -vf "scale=1280:720:flags=lanczos,format=yuv420p" -c:v libx264 -preset slower -tune animation \
  -b:v 1500k -maxrate 3000k -bufsize 4000k -pass 2 -movflags +faststart -c:a aac -b:a 96k \
  -af "loudnorm=I=-18:TP=-2:LRA=11" website/public/media/run.mp4
```

and pick a frame for `public/media/run.jpg` (the picture shown before it plays).
