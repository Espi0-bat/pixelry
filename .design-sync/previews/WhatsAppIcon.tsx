import { WhatsAppIcon, Button } from 'pixelry'

// O ícone herda `currentColor` e o tamanho do contexto — sozinho, sem cor
// definida, ele não pinta nada. Todos os cenários abaixo dão esse contexto.

/** O uso real: dentro dos CTAs de conversão. */
export const NosBotoes = () => (
  <div style={{ display: 'flex', flexDirection: 'column', gap: 16, alignItems: 'flex-start' }}>
    <Button variant="whatsapp"><WhatsAppIcon />Iniciar diagnóstico gratuito</Button>
    <Button variant="hero"><WhatsAppIcon />Agendar Diagnóstico</Button>
  </div>
)

/** Herda a cor do texto ao redor. */
export const HerdandoCor = () => (
  <div style={{ display: 'flex', gap: 28, alignItems: 'center' }}>
    <span style={{ color: '#25D366', width: 32, display: 'inline-flex' }}><WhatsAppIcon /></span>
    <span style={{ color: 'var(--cyan)', width: 32, display: 'inline-flex' }}><WhatsAppIcon /></span>
    <span style={{ color: 'var(--purple-text)', width: 32, display: 'inline-flex' }}><WhatsAppIcon /></span>
    <span style={{ color: 'var(--text)', width: 32, display: 'inline-flex' }}><WhatsAppIcon /></span>
  </div>
)

/** Botão flutuante de contato, como no canto da página. */
export const BotaoFlutuante = () => (
  <span
    style={{
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: 64,
      height: 64,
      borderRadius: '50%',
      background: '#25D366',
      color: '#fff',
      boxShadow: '0 4px 24px rgba(37,211,102,0.4)',
    }}
  >
    <span style={{ width: 32, display: 'inline-flex' }}><WhatsAppIcon /></span>
  </span>
)
