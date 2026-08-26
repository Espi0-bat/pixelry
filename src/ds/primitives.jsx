/**
 * Primitivas do design system Pixelry.
 *
 * Cada uma é um invólucro fino sobre as classes globais já definidas em
 * src/index.css — o estilo continua vivendo lá, estas peças só dão a elas
 * uma API de componente. Nenhum estilo é reimplementado aqui.
 */

const VARIANT_CLASS = {
  primary:    'btn-primary',
  whatsapp:   'btn-whatsapp',
  hero:       'btn-hero-cta',
  secondary:  'btn-secondary',
  clientArea: 'btn-secondary btn-client-area',
}

/**
 * Botão da Pixelry, em cinco variantes.
 *
 * `primary` é o CTA em gradiente roxo→ciano. `whatsapp` é o CTA sólido de
 * conversão. `hero` é o verde de alto contraste usado só na dobra principal.
 * `secondary` é o link discreto em mono. `clientArea` é o secundário com
 * contorno, usado para acesso ao portal.
 *
 * Renderiza `<button>` por padrão; passe `href` para virar âncora.
 */
export function Button({
  variant = 'primary',
  href,
  icon,
  children,
  className = '',
  ...rest
}) {
  const cls = [VARIANT_CLASS[variant] || VARIANT_CLASS.primary, className]
    .filter(Boolean).join(' ')

  const content = <>{icon}{children}</>

  if (href) {
    return <a href={href} className={cls} {...rest}>{content}</a>
  }
  return <button type="button" className={cls} {...rest}>{content}</button>
}

/**
 * Rótulo de seção — texto em mono maiúsculo precedido por um traço ciano.
 * É o "eyebrow" que abre toda seção do site.
 */
export function Label({ children, centered = false, className = '', ...rest }) {
  return (
    <span
      className={['label', className].filter(Boolean).join(' ')}
      style={centered ? { justifyContent: 'center' } : undefined}
      {...rest}
    >
      {children}
    </span>
  )
}

/**
 * Aplica o gradiente roxo→ciano ao texto. Use dentro de um título para
 * destacar o trecho que carrega a mensagem.
 */
export function GradText({ children, className = '', ...rest }) {
  return (
    <span className={['grad-text', className].filter(Boolean).join(' ')} {...rest}>
      {children}
    </span>
  )
}

/** Régua horizontal de 1px com o gradiente da marca. Separa blocos de seção. */
export function GradLine({ className = '', ...rest }) {
  return <div className={['grad-line', className].filter(Boolean).join(' ')} {...rest} />
}

/**
 * Invólucro de seção com a largura e o respiro padrão do site
 * (máx. 1200px, padding responsivo via --section-pad).
 */
export function Section({ children, id, className = '', ...rest }) {
  return (
    <section id={id} {...rest}>
      <div className={['section-wrap', className].filter(Boolean).join(' ')}>
        {children}
      </div>
    </section>
  )
}
