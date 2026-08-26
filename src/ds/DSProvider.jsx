import { MemoryRouter } from 'react-router-dom'

/**
 * Raiz do design system Pixelry. Faz duas coisas:
 *
 * 1. Estabelece a superfície do tema — o sistema é dark-first, e os tokens de
 *    texto (`--text`, `--text-dim`) só têm contraste sobre `--bg`. Sem esta
 *    base, variantes claras como o botão `secondary` ficam ilegíveis.
 * 2. Fornece o contexto de navegação exigido por quem usa `<Link>`
 *    (PillNav, CookieConsent), via MemoryRouter — em uma tela de design não
 *    há histórico real, então a URL não é tocada.
 *
 * Envolva a raiz de qualquer tela construída com este design system.
 */
export function DSProvider({
  children,
  initialPath = '/',
  padded = true,
  style,
}) {
  return (
    <MemoryRouter initialEntries={[initialPath]}>
      <div
        style={{
          background: 'var(--bg)',
          color: 'var(--text)',
          fontFamily: 'var(--font-body)',
          padding: padded ? 24 : 0,
          minHeight: '100%',
          ...style,
        }}
      >
        {children}
      </div>
    </MemoryRouter>
  )
}
