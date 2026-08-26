/**
 * Design system Pixelry — ponto de entrada da biblioteca.
 *
 * Expõe a linguagem visual (tokens, botões, tipografia, layout) e os
 * componentes genuinamente reutilizáveis. As seções da home — Hero, Planos,
 * Faq e afins — ficam de fora de propósito: são composições desta página,
 * com copy fixa, não peças de design system.
 */

// Fontes da marca — o site as carrega via <link>, mas telas geradas a partir
// do design system não têm esse HTML e precisam do @import.
import './fonts.css'

// Estilos globais: tokens (--purple, --cyan, --grad, --font-*), utilitários
// e as classes de botão que as primitivas envolvem.
import '../index.css'

export { DSProvider } from './DSProvider'
export { Button, Label, GradText, GradLine, Section } from './primitives'

// Ícone do WhatsApp usado nos CTAs de conversão.
export { WaIconHero as WhatsAppIcon } from '../components/common/WhatsApp'

// Componentes reutilizáveis do site, exportados como estão.
export { default as PillNav } from '../components/PillNav'
export { default as LeadCaptureModal } from '../components/LeadCaptureModal'
export { default as CookieConsent } from '../components/CookieConsent'
export { default as CaseModal } from '../components/CaseModal'
