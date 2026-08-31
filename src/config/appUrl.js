// URL pública da aplicação — usada como destino dos e-mails de recuperação de senha.
// Em produção: defina VITE_APP_URL (ex: https://www.pixelry.com.br).
// Sem a env, cai para a origem atual do navegador (funciona em dev e prod).
export const APP_URL = (
  import.meta.env.VITE_APP_URL ||
  (typeof window !== 'undefined' ? window.location.origin : '')
).replace(/\/$/, '')

// Destino do link de recuperação. Cai na raiz — o App detecta o evento
// PASSWORD_RECOVERY e abre a tela de nova senha por cima de qualquer rota.
export const PASSWORD_RESET_REDIRECT = `${APP_URL}/`
