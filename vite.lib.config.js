import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath, URL } from 'node:url'

/**
 * Build da biblioteca de design system (src/ds) — separado do build do site.
 *
 * Produz dist-ds/, consumido pelo design-sync para publicar os componentes
 * no claude.ai/design. O build do site (vite.config.js → dist/) não é afetado.
 */
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist-ds',
    emptyOutDir: true,
    sourcemap: false,
    lib: {
      entry: fileURLToPath(new URL('./src/ds/index.js', import.meta.url)),
      name: 'PixelryDS',
      formats: ['es'],
      fileName: () => 'index.es.js',
      cssFileName: 'index',
    },
    rollupOptions: {
      // React vem do runtime do design-sync (_vendor/), não do bundle.
      external: ['react', 'react-dom', 'react/jsx-runtime'],
    },
  },
  define: {
    // O modal de leads lê estas variáveis; fora do site elas não existem e o
    // cliente Supabase fica nulo, que é o comportamento já previsto no código.
    'import.meta.env.VITE_SUPABASE_URL': 'undefined',
    'import.meta.env.VITE_SUPABASE_ANON_KEY': 'undefined',
    'import.meta.env.VITE_SUPER_ADMIN_EMAILS': 'undefined',
    'import.meta.env.VITE_MANAGER_EMAILS': 'undefined',
    'import.meta.env.VITE_WHATSAPP_NUMBER': 'undefined',
    'import.meta.env.VITE_CLIENT_WHATSAPP_NUMBER': 'undefined',
  },
})
