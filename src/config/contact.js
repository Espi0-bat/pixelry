const DEFAULT_WHATSAPP_NUMBER = '5561991410161'
const DEFAULT_CLIENT_WHATSAPP_NUMBER = '5561991410161'

export const WHATSAPP_NUMBER =
  import.meta.env.VITE_WHATSAPP_NUMBER || DEFAULT_WHATSAPP_NUMBER

export const CLIENT_WHATSAPP_NUMBER =
  import.meta.env.VITE_CLIENT_WHATSAPP_NUMBER || DEFAULT_CLIENT_WHATSAPP_NUMBER

export function buildWhatsAppLink(message, number = WHATSAPP_NUMBER) {
  return `https://wa.me/${number}?text=${encodeURIComponent(message)}`
}
