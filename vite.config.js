import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Change '/pixelry/' to match your GitHub repo name
// e.g. if repo is https://github.com/user/pixelry → base: '/pixelry/'
export default defineConfig({
  plugins: [react()],
  base: '/pixelry/',
})
