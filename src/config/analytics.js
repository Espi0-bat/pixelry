/**
 * Medição de tráfego — GA4 e Meta Pixel.
 *
 * Três regras que o código garante, não a boa vontade de quem usa:
 *
 * 1. Os IDs são públicos (aparecem em qualquer página) e ficam no código,
 *    como o WhatsApp em config/contact.js, mas só medem no domínio do site:
 *    localhost, prévias e o CookieConsent exportado pelo design system não
 *    sujam os dados. VITE_GA4_ID e VITE_META_PIXEL_ID apontam outro ambiente
 *    para outra conta e, definidos, valem em qualquer domínio.
 * 2. Nada carrega antes do consentimento. O banner de cookies guarda
 *    { essential, analytics, marketing } em `pixelry_cookie_consent`; o GA4
 *    depende de `analytics` e o Meta Pixel de `marketing`. Quem fecha o banner
 *    sem escolher não é medido.
 * 3. /admin e /portal ficam de fora: são tela interna, não audiência.
 *
 * A troca de rota da SPA não tem código aqui: o GA4 (medição aprimorada) e o
 * Meta Pixel já contam sozinhos as mudanças de histórico. Um page_view manual
 * por cima dobrava a contagem do GA4.
 */

const GA4_ID = import.meta.env.VITE_GA4_ID || 'G-95HP1S4K2N'
const META_ID = import.meta.env.VITE_META_PIXEL_ID || '439363224095353'
const IDS_DO_AMBIENTE = Boolean(import.meta.env.VITE_GA4_ID || import.meta.env.VITE_META_PIXEL_ID)
const DOMINIOS_DO_SITE = ['www.pixelry.com.br', 'pixelry.com.br']

export const CHAVE_CONSENTIMENTO = 'pixelry_cookie_consent'

let ga4Pronto = false
let metaPronto = false

export function lerConsentimento() {
  try {
    const bruto = localStorage.getItem(CHAVE_CONSENTIMENTO)
    if (!bruto) return null
    const valor = JSON.parse(bruto)
    return {
      analytics: valor?.analytics === true,
      marketing: valor?.marketing === true,
    }
  } catch (_) {
    return null
  }
}

function rotaInterna(caminho = window.location.pathname) {
  return caminho.startsWith('/admin') || caminho.startsWith('/portal')
}

function injetarScript(src) {
  const script = document.createElement('script')
  script.async = true
  script.src = src
  document.head.appendChild(script)
}

function carregarGA4() {
  if (ga4Pronto || !GA4_ID) return
  ga4Pronto = true
  window.dataLayer = window.dataLayer || []
  // gtag empilha `arguments` cru; precisa ser função comum, não arrow.
  window.gtag = function gtag() { window.dataLayer.push(arguments) }
  injetarScript(`https://www.googletagmanager.com/gtag/js?id=${GA4_ID}`)
  window.gtag('js', new Date())
  window.gtag('config', GA4_ID)
}

function carregarMeta() {
  if (metaPronto || !META_ID) return
  metaPronto = true
  // Fila oficial do fbevents: o script real procura `queue`, `callMethod` e
  // `push` neste formato quando termina de carregar.
  const fbq = function fbq() {
    fbq.callMethod ? fbq.callMethod.apply(fbq, arguments) : fbq.queue.push(arguments)
  }
  fbq.push = fbq
  fbq.loaded = true
  fbq.version = '2.0'
  fbq.queue = []
  window.fbq = window.fbq || fbq
  window._fbq = window._fbq || window.fbq
  injetarScript('https://connect.facebook.net/pt_BR/fbevents.js')
  window.fbq('init', META_ID)
  window.fbq('track', 'PageView')
}

/** Chamada no carregamento e sempre que o consentimento muda. */
export function iniciarMedicao() {
  if (typeof window === 'undefined') return
  if (!IDS_DO_AMBIENTE && !DOMINIOS_DO_SITE.includes(window.location.hostname)) return
  if (rotaInterna()) return
  const consentimento = lerConsentimento()
  if (!consentimento) return
  if (consentimento.analytics) carregarGA4()
  if (consentimento.marketing) carregarMeta()
}

/**
 * Cadastro gravado com sucesso. O `source` vai junto para cruzar com o ranking
 * de origem do painel (ex.: lp_clinicas_respostas_respostas).
 */
export function registrarLead(source) {
  if (ga4Pronto && window.gtag) window.gtag('event', 'generate_lead', { source })
  if (metaPronto && window.fbq) window.fbq('track', 'Lead', { source })
}
