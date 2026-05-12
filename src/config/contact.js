const DEFAULT_WHATSAPP_NUMBER = '556193720900'
const DEFAULT_CLIENT_WHATSAPP_NUMBER = '5561992150965'

export const WHATSAPP_NUMBER =
  import.meta.env.VITE_WHATSAPP_NUMBER || DEFAULT_WHATSAPP_NUMBER

export const CLIENT_WHATSAPP_NUMBER =
  import.meta.env.VITE_CLIENT_WHATSAPP_NUMBER || DEFAULT_CLIENT_WHATSAPP_NUMBER

export function buildWhatsAppLink(message, number = WHATSAPP_NUMBER) {
  return `https://wa.me/${number}?text=${encodeURIComponent(message)}`
}
