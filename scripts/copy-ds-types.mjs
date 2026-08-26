import { copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

// Vite em modo lib não emite tipos; as declarações são escritas à mão em
// src/ds/index.d.ts e copiadas para dist-ds/ ao lado do bundle.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const src = resolve(root, 'src/ds/index.d.ts')
const outDir = resolve(root, 'dist-ds')
const dest = resolve(outDir, 'index.es.d.ts')

if (!existsSync(src)) {
  console.error(`✗ tipos não encontrados: ${src}`)
  process.exit(1)
}

mkdirSync(outDir, { recursive: true })
copyFileSync(src, dest)
console.log(`✓ tipos copiados → dist-ds/index.es.d.ts`)
