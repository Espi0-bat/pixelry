/**
 * Gera HTML estático das rotas públicas depois do build.
 *
 * Por que isso existe: o site era uma SPA pura e o dist/index.html saía com
 * <div id="root"></div> literalmente vazio. Qualquer leitor que não executa
 * JavaScript — crawler de busca, preview de link do WhatsApp/LinkedIn, boa
 * parte das ferramentas de auditoria — recebia uma página em branco.
 *
 * O JS continua assumindo a página normalmente: o main.jsx hidrata o HTML
 * pré-renderizado em vez de recriá-lo do zero.
 *
 * Roda depois de `vite build` e `vite build --ssr`. Ver package.json.
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { dirname, resolve, join } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const raiz = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const DIST = join(raiz, 'dist')
const SSR_ENTRY = join(raiz, 'dist-ssr', 'entry-server.js')

// Só rotas públicas. /admin e /portal exigem sessão e estão bloqueadas no
// robots.txt — pré-renderizar as duas só publicaria a casca da tela de login.
const ROTAS = ['/', '/privacidade', '/termos']

const SITE = 'https://www.pixelry.com.br'

// Prioridade e frequência por rota; o resto do sitemap sai daqui.
const SEO = {
  '/':            { changefreq: 'weekly', priority: '1.0' },
  '/privacidade': { changefreq: 'yearly', priority: '0.5' },
  '/termos':      { changefreq: 'yearly', priority: '0.5' },
}

/**
 * O sitemap sai da mesma lista que o prerender, e não de um arquivo à parte em
 * public/. Eram duas fontes da verdade: o sitemap versionado ficou com lastmod
 * de junho enquanto o site seguia mudando. Gerado no build, ele não tem como
 * divergir das rotas que realmente existem.
 */
function gerarSitemap() {
  const hoje = new Date().toISOString().slice(0, 10)
  const urls = ROTAS.map((rota) => {
    const { changefreq, priority } = SEO[rota] ?? { changefreq: 'monthly', priority: '0.5' }
    return [
      '  <url>',
      `    <loc>${SITE}${rota}</loc>`,
      `    <lastmod>${hoje}</lastmod>`,
      `    <changefreq>${changefreq}</changefreq>`,
      `    <priority>${priority}</priority>`,
      '  </url>',
    ].join('\n')
  }).join('\n')

  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls}
</urlset>
`
  writeFileSync(join(DIST, 'sitemap.xml'), xml)
  console.log(`  sitemap.xml   → ${ROTAS.length} URLs, lastmod ${hoje}`)
}

/**
 * Cada rota vira dois arquivos. Hosts estáticos discordam sobre como resolver
 * um caminho sem barra final: uns servem `privacidade.html`, outros redirecionam
 * para `/privacidade/` e servem o index do diretório. Gravar os dois cobre os
 * dois casos — e o custo é ~10 kB por rota.
 *
 * Se `/privacidade` cair no index.html da home, o servidor manda o HTML da home
 * enquanto o router do cliente monta a página de privacidade: a hidratação falha
 * e o React descarta o HTML servido. Foi exatamente o que aconteceu no
 * `vite preview` antes desta mudança.
 */
const destinos = (rota) =>
  rota === '/'
    ? [join(DIST, 'index.html')]
    : [join(DIST, `${rota.slice(1)}.html`), join(DIST, rota.slice(1), 'index.html')]

/**
 * O config/supabase.js chama createClient no escopo do módulo, e o cliente
 * realtime exige um WebSocket global — que o Node só tem nativo a partir da
 * v22. Aqui nada chega a conectar: sem effects não há sessão nem canal, o
 * construtor só precisa existir no momento em que o cliente é criado.
 * Stub em vez de subir o Node ou instalar `ws` só para o build.
 */
function stubWebSocket() {
  if (typeof globalThis.WebSocket !== 'undefined') return
  globalThis.WebSocket = class WebSocketStubDeBuild {
    constructor() {
      throw new Error('WebSocket não está disponível durante o prerender.')
    }
  }
}

/**
 * Só as rotas legais definem head próprio via Helmet; a home usa o que já
 * está estático no index.html. Numa rota sem <Helmet>, o provider ainda
 * devolve `<title data-rh="true"></title>` — vazio. Trocar por isso apagaria
 * o título bom da home, então exigimos conteúdo de verdade antes de trocar.
 *
 * A troca usa função como replacement: assim `$&` e afins dentro do texto do
 * Helmet entram literais em vez de virarem referência de captura.
 */
const temTexto = (tag) => Boolean(tag) && tag.replace(/<[^>]*>/g, '').trim().length > 0

function trocarTitulo(html, tag) {
  if (!temTexto(tag)) return html
  return html.replace(/<title>[\s\S]*?<\/title>/, () => tag)
}

function trocarDescricao(html, tag) {
  if (!tag || !tag.trim()) return html
  return html.replace(/<meta\s+name="description"[^>]*>/, () => tag)
}

function main() {
  const template = join(DIST, 'index.html')
  if (!existsSync(template)) {
    throw new Error('dist/index.html não existe — rode `vite build` antes.')
  }
  if (!existsSync(SSR_ENTRY)) {
    throw new Error('dist-ssr/entry-server.js não existe — rode o build de SSR antes.')
  }

  stubWebSocket()

  return import(pathToFileURL(SSR_ENTRY).href).then(async ({ render }) => {
    const base = readFileSync(template, 'utf8')

    if (!base.includes('<div id="root"></div>')) {
      throw new Error('Não achei <div id="root"></div> no template — o index.html mudou?')
    }

    for (const rota of ROTAS) {
      const { html, helmet } = await render(rota)

      let saida = base.replace('<div id="root"></div>', `<div id="root">${html}</div>`)

      // As rotas legais definem o próprio <title>/<meta> via react-helmet-async.
      // A home usa o que já está estático no index.html.
      if (helmet) {
        saida = trocarTitulo(saida, helmet.title?.toString())
        saida = trocarDescricao(saida, helmet.meta?.toString())
      }

      const arquivos = destinos(rota)
      for (const arquivo of arquivos) {
        mkdirSync(dirname(arquivo), { recursive: true })
        writeFileSync(arquivo, saida)
      }

      const kb = (Buffer.byteLength(html) / 1024).toFixed(1)
      const nomes = arquivos.map((a) => a.replace(DIST + '/', '')).join('  +  ')
      console.log(`  ${rota.padEnd(14)} → ${nomes}  (${kb} kB de HTML)`)
    }

    gerarSitemap()
  })
}

console.log('\nprerender — gerando HTML estático das rotas públicas')
main()
  .then(() => console.log('prerender concluído\n'))
  .catch((err) => {
    console.error('\nprerender falhou:', err.message)
    process.exit(1)
  })
