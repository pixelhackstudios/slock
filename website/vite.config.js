import { defineConfig } from 'vite'

// Served from https://pixelhackstudios.github.io/slock/
export default defineConfig({
  base: '/slock/',
  // three.js is most of the script, and it's needed up front.
  build: { target: 'es2022', assetsInlineLimit: 0, chunkSizeWarningLimit: 800 },
})
