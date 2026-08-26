import type {
  ReactNode,
  CSSProperties,
  AnchorHTMLAttributes,
  ButtonHTMLAttributes,
  HTMLAttributes,
} from 'react'

/** Variantes visuais de botão do design system. */
export type ButtonVariant =
  | 'primary'
  | 'whatsapp'
  | 'hero'
  | 'secondary'
  | 'clientArea'

export interface ButtonProps
  extends Omit<ButtonHTMLAttributes<HTMLButtonElement> & AnchorHTMLAttributes<HTMLAnchorElement>, 'children'> {
  /** Variante visual. Padrão: `primary`. */
  variant?: ButtonVariant
  /** Quando presente, renderiza `<a>` no lugar de `<button>`. */
  href?: string
  /** Ícone opcional renderizado antes do texto (ex.: `<WhatsAppIcon />`). */
  icon?: ReactNode
  children?: ReactNode
  className?: string
}

/**
 * Botão da Pixelry, em cinco variantes.
 *
 * `primary` é o CTA em gradiente roxo→ciano. `whatsapp` é o CTA sólido de
 * conversão. `hero` é o verde de alto contraste usado só na dobra principal.
 * `secondary` é o link discreto em mono. `clientArea` é o secundário com
 * contorno, usado para acesso ao portal.
 */
export declare function Button(props: ButtonProps): JSX.Element

export interface LabelProps extends HTMLAttributes<HTMLSpanElement> {
  children?: ReactNode
  /** Centraliza o rótulo — use em seções de cabeçalho centralizado. */
  centered?: boolean
  className?: string
}

/**
 * Rótulo de seção — texto em mono maiúsculo precedido por um traço ciano.
 * É o "eyebrow" que abre toda seção do site.
 */
export declare function Label(props: LabelProps): JSX.Element

export interface GradTextProps extends HTMLAttributes<HTMLSpanElement> {
  children?: ReactNode
  className?: string
}

/**
 * Aplica o gradiente roxo→ciano ao texto. Use dentro de um título para
 * destacar o trecho que carrega a mensagem.
 */
export declare function GradText(props: GradTextProps): JSX.Element

export interface GradLineProps extends HTMLAttributes<HTMLDivElement> {
  className?: string
}

/** Régua horizontal de 1px com o gradiente da marca. Separa blocos de seção. */
export declare function GradLine(props: GradLineProps): JSX.Element

export interface SectionProps extends HTMLAttributes<HTMLElement> {
  children?: ReactNode
  /** Âncora da seção, usada pela navegação (ex.: `planos`). */
  id?: string
  className?: string
}

/**
 * Invólucro de seção com a largura e o respiro padrão do site
 * (máx. 1200px, padding responsivo via `--section-pad`).
 */
export declare function Section(props: SectionProps): JSX.Element

export interface DSProviderProps {
  children?: ReactNode
  /** Rota inicial do MemoryRouter. Padrão: `/`. */
  initialPath?: string
  /** Respiro interno da superfície. Passe `false` para telas full-bleed. */
  padded?: boolean
  style?: CSSProperties
}

/**
 * Raiz do design system. Estabelece a superfície escura do tema — sem ela os
 * tokens de texto não têm contraste — e fornece o contexto de navegação
 * exigido por `PillNav` e `CookieConsent`.
 *
 * Envolva a raiz de qualquer tela construída com este design system.
 */
export declare function DSProvider(props: DSProviderProps): JSX.Element

/** Ícone do WhatsApp usado nos CTAs de conversão. Herda `currentColor`. */
export declare function WhatsAppIcon(): JSX.Element

export interface PillNavItem {
  /** Texto exibido na pílula. */
  label: string
  /** Destino. Caminhos internos viram `<Link>`; URLs externas viram `<a>`. */
  href: string
}

export interface PillNavProps {
  /** URL da imagem de logo exibida no círculo à esquerda. */
  logo?: string
  logoAlt?: string
  /** Itens de navegação, na ordem de exibição. */
  items?: PillNavItem[]
  /** `href` do item atualmente ativo. */
  activeHref?: string
  className?: string
  /** Curva de animação GSAP. Padrão: `power3.easeOut`. */
  ease?: string
  /** Cor de fundo da barra e do círculo do logo. Padrão: `#fff`. */
  baseColor?: string
  /** Cor de fundo de cada pílula. Padrão: `#120F17`. */
  pillColor?: string
  /** Cor do texto da pílula em hover. Padrão: `#120F17`. */
  hoveredPillTextColor?: string
  /** Cor do texto da pílula em repouso. Padrão: igual a `baseColor`. */
  pillTextColor?: string
  onMobileMenuClick?: () => void
  /** Anima a entrada no primeiro render. Padrão: `true`. */
  initialLoadAnimation?: boolean
}

/**
 * Navegação em pílulas com animação GSAP e menu mobile.
 * Requer `DSProvider` acima na árvore quando os itens apontam para rotas internas.
 */
export declare function PillNav(props: PillNavProps): JSX.Element

export interface LeadCaptureModalProps {
  isOpen: boolean
  onClose: () => void
  /** Link do WhatsApp aberto após o envio; recebe os campos de qualificação. */
  waLink?: string
  /** Origem do lead, gravada junto do registro (ex.: `hero_cta`). */
  source?: string
}

/**
 * Modal de captação de leads: nome, e-mail, contato e três campos de
 * qualificação (segmento, faturamento, investimento). Ao enviar, grava o
 * lead e encaminha para o WhatsApp com os dados anexados.
 */
export declare function LeadCaptureModal(props: LeadCaptureModalProps): JSX.Element | null

/**
 * Faixa de consentimento de cookies, com detalhamento por categoria.
 * Requer `DSProvider` acima na árvore (link para a política de privacidade).
 */
export declare function CookieConsent(): JSX.Element | null

export interface CaseData {
  title?: string
  description?: string
  /** URL da imagem de capa. */
  image?: string
  /** Link para o projeto publicado. */
  link?: string
  tags?: string[]
}

export interface CaseModalProps {
  isOpen: boolean
  onClose: () => void
  caseData?: CaseData
}

/** Modal de detalhe de case, com capa, tags, descrição e link para o projeto. */
export declare function CaseModal(props: CaseModalProps): JSX.Element | null
