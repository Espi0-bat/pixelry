import { Button, WhatsAppIcon } from 'pixelry'

/** As cinco variantes lado a lado, na hierarquia em que aparecem na página. */
export const Variantes = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 20, alignItems: 'flex-start' }}>
    <Button variant="primary">Ver planos</Button>
    <Button variant="whatsapp"><WhatsAppIcon />Iniciar diagnóstico gratuito</Button>
    <Button variant="hero"><WhatsAppIcon />Agendar Diagnóstico</Button>
    <Button variant="secondary">Ver serviços ↓</Button>
    <Button variant="clientArea">Área do Cliente</Button>
  </div>
)

/** O CTA principal de conversão, como aparece no fim da página. */
export const CtaDeConversao = () => (
  <Button variant="whatsapp">
    <WhatsAppIcon />
    Iniciar diagnóstico gratuito
  </Button>
)

/** Renderizado como âncora quando recebe `href`. */
export const ComoLink = () => (
  <div style={{ display: 'flex', gap: 16, alignItems: 'center', flexWrap: 'wrap' }}>
    <Button variant="primary" href="#planos">Conhecer os planos</Button>
    <Button variant="secondary" href="#servicos">Ver serviços ↓</Button>
  </div>
)

/** Estado desabilitado — usado enquanto um envio está em andamento. */
export const Desabilitado = () => (
  <div style={{ display: 'flex', gap: 16, alignItems: 'center', flexWrap: 'wrap' }}>
    <Button variant="primary" disabled>Enviando…</Button>
    <Button variant="whatsapp" disabled>Enviando…</Button>
  </div>
)
