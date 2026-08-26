import { Label } from 'pixelry'

/** Rótulos reais usados nas seções do site. */
export const Rotulos = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 22, alignItems: 'flex-start' }}>
    <Label>O DIAGNÓSTICO</Label>
    <Label>PIXELRY CORE</Label>
    <Label>SISTEMA E INVESTIMENTO</Label>
    <Label>PERFIL IDEAL</Label>
  </div>
)

/** Variante centralizada, para seções de cabeçalho centrado. */
export const Centralizado = () => (
  <div style={{ textAlign: 'center' }}>
    <Label centered>MÓDULOS OPCIONAIS</Label>
  </div>
)

/** Abrindo uma seção, que é como o rótulo sempre aparece. */
export const AbrindoUmaSecao = () => (
  <div>
    <Label>A TRANSFORMAÇÃO</Label>
    <h2
      style={{
        fontFamily: 'var(--font-display)',
        fontSize: 34,
        fontWeight: 700,
        letterSpacing: '-0.02em',
        lineHeight: 1.15,
        margin: 0,
        color: 'var(--text)',
      }}
    >
      Arraste e veja a diferença.
    </h2>
  </div>
)
