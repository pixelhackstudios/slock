# slock-web

The Slock website: https://pixelhackstudios.github.io/slock/

Vite + React + Tailwind CSS 4, with GSAP and Lenis for motion. Same stack and design language as
[chickenbutt.dev](https://www.chickenbutt.dev/): Bungee headlines, Geist body text and the cool ink
neutrals, with Slock's own colors (jelly red, gold pellet, Slorm green, pellet blue) as accents.

## Work on it

```bash
cd slock-web
npm install
npm run dev
```

Then open http://localhost:5173/slock/.

## Publishing

Every push to `main` that touches `slock-web/` rebuilds the site and publishes it to GitHub Pages
(see `.github/workflows/pages.yml`). Nothing built is committed.

- The download buttons ask GitHub for the newest release, so a new release needs no site change.
- The gameplay screenshots come straight from `../docs/screenshots`, the same files the main README uses.
- The teaser in `public/media/` is a 720p web copy of the render made by `tools/trailer/`.
