// Fixo de propósito: nenhuma variável do deploy troca o contato do site.
export const WHATSAPP_NUMBER = '5561991410161'
export const CLIENT_WHATSAPP_NUMBER = WHATSAPP_NUMBER

export function buildWhatsAppLink(message, number = WHATSAPP_NUMBER) {
  return `https://wa.me/${number}?text=${encodeURIComponent(message)}`
}
