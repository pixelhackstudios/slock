import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// Served from GitHub Pages at /slock/. Screenshots are imported straight from ../docs/screenshots
// (the README uses the same files), so the dev server may read one level up.
export default defineConfig({
  base: '/slock/',
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      '@shots': fileURLToPath(new URL('../docs/screenshots', import.meta.url)),
    },
  },
  server: { fs: { allow: ['..'] } },
})
