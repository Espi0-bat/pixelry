import { GradText } from 'pixelry'

const h1: React.CSSProperties = {
  fontFamily: 'var(--font-display)',
  fontSize: 42,
  fontWeight: 700,
  lineHeight: 1.15,
  letterSpacing: '-0.025em',
  margin: 0,
  color: 'var(--text)',
}

/** O uso canônico: destacar o trecho do título que carrega a mensagem. */
export const EmTitulo = () => (
  <h1 style={h1}>
    Sua clínica atende bem.{' '}
    <GradText>Só que a agenda ainda tem buracos.</GradText>
  </h1>
)

/** Título inteiro em gradiente, como no Manifesto. */
export const TituloInteiro = () => (
  <h2 style={{ ...h1, fontSize: 34 }}>
    <GradText>Construímos o sistema que gera clientes.</GradText>
  </h2>
)

/** O gradiente acompanha o tamanho do texto em que é aplicado. */
export const Escalas = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
    <span style={{ ...h1, fontSize: 46 }}><GradText>agenda cheia</GradText></span>
    <span style={{ ...h1, fontSize: 30 }}><GradText>agenda cheia</GradText></span>
    <span style={{ ...h1, fontSize: 19 }}><GradText>agenda cheia</GradText></span>
  </div>
)
