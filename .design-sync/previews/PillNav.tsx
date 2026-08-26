import { PillNav } from 'pixelry'

// Marca em gradiente como data-URI: o preview não carrega assets do repo,
// e o slot do logo precisa de conteúdo para mostrar o círculo corretamente.
const LOGO =
  'data:image/svg+xml,' +
  encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
       <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
         <stop offset="0" stop-color="#8040F5"/><stop offset="1" stop-color="#00D8FF"/>
       </linearGradient></defs>
       <rect width="64" height="64" rx="14" fill="url(#g)"/>
       <path d="M22 44V20h13a9 9 0 0 1 0 18h-6" stroke="#070710" stroke-width="5"
             fill="none" stroke-linecap="round" stroke-linejoin="round"/>
     </svg>`
  )

const ITEMS = [
  { label: 'Início', href: '/' },
  { label: 'Serviços', href: '/#servicos' },
  { label: 'Planos', href: '/#planos' },
  { label: 'FAQ', href: '/#faq' },
]

/** A navegação como aparece no site, com as cores da marca. */
export const Navegacao = () => (
  <PillNav
    logo={LOGO}
    logoAlt="PIXELRY"
    items={ITEMS}
    activeHref="/"
    baseColor="#101022"
    pillColor="#070710"
    hoveredPillTextColor="#00D8FF"
    pillTextColor="#f0f0fa"
    initialLoadAnimation={false}
  />
)

// Nota: não há célula para `activeHref`. O indicador de item ativo é um ponto
// de 12px na cor `baseColor`, que contra a superfície escura do tema fica
// indistinguível — a célula seria idêntica a `Navegacao`. A prop funciona
// normalmente; ela só não se traduz em diferença visível num card estático.

/** Conjunto reduzido de itens, para cabeçalhos mais enxutos. */
export const MenosItens = () => (
  <PillNav
    logo={LOGO}
    logoAlt="PIXELRY"
    items={[
      { label: 'Início', href: '/' },
      { label: 'Planos', href: '/#planos' },
    ]}
    activeHref="/"
    baseColor="#101022"
    pillColor="#070710"
    hoveredPillTextColor="#00D8FF"
    pillTextColor="#f0f0fa"
    initialLoadAnimation={false}
  />
)
