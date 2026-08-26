import { Section, Label, GradText, Button, GradLine } from 'pixelry'

const h2: React.CSSProperties = {
  fontFamily: 'var(--font-display)',
  fontSize: 34,
  fontWeight: 700,
  lineHeight: 1.15,
  letterSpacing: '-0.02em',
  margin: '0 0 24px',
  color: 'var(--text)',
}

const body: React.CSSProperties = {
  color: 'var(--text-dim)',
  fontSize: 16,
  lineHeight: 1.85,
  fontWeight: 300,
  margin: 0,
  maxWidth: '60ch',
}

/** Seção completa — é assim que as peças do design system se combinam. */
export const SecaoCompleta = () => (
  <Section id="diagnostico">
    <Label>O DIAGNÓSTICO</Label>
    <h2 style={h2}>
      Você tem clientes satisfeitos.{' '}
      <GradText>Mas ainda depende de indicação.</GradText>
    </h2>
    <p style={body}>
      Isso não é problema de mercado — é problema de sistema. Clínicas que
      atendem bem perdem pacientes todo dia porque o site não converte e
      nenhum dado diz de onde vem o lead.
    </p>
  </Section>
)

/** Seção centralizada, com CTA ao final. */
export const Centralizada = () => (
  <Section>
    <div style={{ textAlign: 'center' }}>
      <Label centered>SISTEMA E INVESTIMENTO</Label>
      <h2 style={{ ...h2, marginBottom: 16 }}>
        Três formas de estruturar.
      </h2>
      <p style={{ ...body, margin: '0 auto 32px' }}>
        Um único objetivo: agenda cheia.
      </p>
      <Button variant="primary">Ver planos</Button>
    </div>
  </Section>
)

/** Duas seções separadas pela régua de gradiente. */
export const ComSeparador = () => (
  <div>
    <Section>
      <Label>MANIFESTO</Label>
      <h2 style={{ ...h2, marginBottom: 0 }}>Não fazemos presença digital.</h2>
    </Section>
    <GradLine />
    <Section>
      <Label>PERFIL IDEAL</Label>
      <h2 style={{ ...h2, marginBottom: 0 }}>Para quem já é bom no que faz.</h2>
    </Section>
  </div>
)
