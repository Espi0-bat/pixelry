const RESEND_API_URL = 'https://api.resend.com/emails'

export async function sendEmail(to: string, subject: string, html: string): Promise<void> {
  const apiKey = Deno.env.get('RESEND_API_KEY')
  if (!apiKey) {
    console.warn('[resend] RESEND_API_KEY não configurado — email não enviado')
    return
  }

  const from = Deno.env.get('FROM_EMAIL') ?? 'noreply@pixelry.com.br'

  const res = await fetch(RESEND_API_URL, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from, to, subject, html }),
  })

  if (!res.ok) {
    const body = await res.text()
    console.error('[resend] Falha ao enviar email:', res.status, body)
  }
}

function formatBRL(amount: number): string {
  return amount.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' })
}

function formatDate(date: string | null | undefined): string {
  if (!date) return '—'
  const [y, m, d] = date.split('-')
  return `${d}/${m}/${y}`
}

function baseLayout(content: string): string {
  return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Pixelry</title>
</head>
<body style="margin:0;padding:0;background:#0d0d0d;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#0d0d0d;padding:32px 16px;">
    <tr>
      <td align="center">
        <table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">
          <!-- Logo -->
          <tr>
            <td style="padding-bottom:24px;text-align:center;">
              <span style="font-size:22px;font-weight:700;background:linear-gradient(90deg,#a855f7,#ec4899);-webkit-background-clip:text;-webkit-text-fill-color:transparent;color:#a855f7;">
                pixelry
              </span>
            </td>
          </tr>
          <!-- Card -->
          <tr>
            <td style="background:#1a1a1a;border-radius:12px;padding:36px 32px;border:1px solid #2a2a2a;">
              ${content}
            </td>
          </tr>
          <!-- Footer -->
          <tr>
            <td style="padding-top:24px;text-align:center;color:#555;font-size:12px;line-height:1.6;">
              <p style="margin:0;">Este é um email automático — não responda a esta mensagem.</p>
              <p style="margin:4px 0 0;">© ${new Date().getFullYear()} Pixelry. Todos os direitos reservados.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`
}

export function templateInvoiceCreated(
  clientName: string | null,
  amount: number,
  description: string,
  paymentUrl: string | null,
  qrCodeText: string | null,
  dueDate: string | null,
): string {
  const name = clientName ?? 'Cliente'
  const dueDateStr = dueDate ? `<p style="margin:0 0 8px;color:#aaa;font-size:14px;">Vencimento: <strong style="color:#e0e0e0;">${formatDate(dueDate)}</strong></p>` : ''
  const pixSection = qrCodeText ? `
    <div style="margin-top:24px;padding:16px;background:#111;border-radius:8px;border:1px solid #2a2a2a;">
      <p style="margin:0 0 8px;font-size:13px;color:#aaa;font-weight:600;text-transform:uppercase;letter-spacing:.05em;">Pix — Copia e cola</p>
      <p style="margin:0;font-size:12px;color:#d0d0d0;word-break:break-all;font-family:monospace;">${qrCodeText}</p>
    </div>` : ''
  const ctaButton = paymentUrl ? `
    <div style="text-align:center;margin-top:28px;">
      <a href="${paymentUrl}" style="display:inline-block;background:linear-gradient(90deg,#a855f7,#ec4899);color:#fff;font-weight:600;font-size:15px;padding:14px 32px;border-radius:8px;text-decoration:none;">
        Pagar agora
      </a>
    </div>` : ''

  return baseLayout(`
    <h2 style="margin:0 0 8px;font-size:20px;color:#f0f0f0;font-weight:700;">Nova cobrança disponível</h2>
    <p style="margin:0 0 24px;color:#aaa;font-size:14px;">Olá, ${name}. Você tem uma nova cobrança da Pixelry.</p>
    <div style="background:#111;border-radius:8px;padding:20px;border:1px solid #2a2a2a;margin-bottom:8px;">
      <p style="margin:0 0 8px;color:#aaa;font-size:14px;">Descrição: <strong style="color:#e0e0e0;">${description}</strong></p>
      <p style="margin:0 0 8px;font-size:22px;font-weight:700;color:#fff;">${formatBRL(amount)}</p>
      ${dueDateStr}
    </div>
    ${pixSection}
    ${ctaButton}
    <p style="margin-top:24px;font-size:13px;color:#666;text-align:center;">Acesse também o seu <a href="https://www.pixelry.com.br/portal" style="color:#a855f7;text-decoration:none;">portal do cliente</a> para ver todos os seus projetos e cobranças.</p>
  `)
}

export function templatePaymentConfirmed(
  clientName: string | null,
  amount: number,
  description: string,
  paidAt: string | null,
): string {
  const name = clientName ?? 'Cliente'
  const paidAtStr = paidAt
    ? new Date(paidAt).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Sao_Paulo' })
    : ''

  return baseLayout(`
    <div style="text-align:center;margin-bottom:24px;">
      <div style="display:inline-block;background:linear-gradient(135deg,#16a34a22,#16a34a11);border:1px solid #16a34a55;border-radius:50%;width:56px;height:56px;line-height:56px;font-size:26px;">✓</div>
    </div>
    <h2 style="margin:0 0 8px;font-size:20px;color:#f0f0f0;font-weight:700;text-align:center;">Pagamento confirmado!</h2>
    <p style="margin:0 0 24px;color:#aaa;font-size:14px;text-align:center;">Obrigado, ${name}. Recebemos o seu pagamento com sucesso.</p>
    <div style="background:#111;border-radius:8px;padding:20px;border:1px solid #2a2a2a;">
      <p style="margin:0 0 6px;color:#aaa;font-size:13px;">Serviço</p>
      <p style="margin:0 0 16px;color:#e0e0e0;font-size:14px;font-weight:600;">${description}</p>
      <p style="margin:0 0 6px;color:#aaa;font-size:13px;">Valor pago</p>
      <p style="margin:0 0 16px;font-size:22px;font-weight:700;color:#4ade80;">${formatBRL(amount)}</p>
      ${paidAtStr ? `<p style="margin:0;color:#555;font-size:12px;">Registrado em ${paidAtStr}</p>` : ''}
    </div>
    <p style="margin-top:24px;font-size:13px;color:#666;text-align:center;">Acompanhe o andamento do seu projeto no <a href="https://www.pixelry.com.br/portal" style="color:#a855f7;text-decoration:none;">portal do cliente</a>.</p>
  `)
}

export function templateAdminPaymentAlert(
  clientName: string | null,
  clientEmail: string | null,
  amount: number,
  description: string,
): string {
  const name = clientName ?? 'Cliente desconhecido'
  const email = clientEmail ?? '—'

  return baseLayout(`
    <h2 style="margin:0 0 8px;font-size:20px;color:#f0f0f0;font-weight:700;">Pagamento recebido</h2>
    <p style="margin:0 0 24px;color:#aaa;font-size:14px;">Um cliente acabou de confirmar o pagamento de uma fatura.</p>
    <div style="background:#111;border-radius:8px;padding:20px;border:1px solid #2a2a2a;">
      <p style="margin:0 0 8px;color:#aaa;font-size:13px;">Cliente</p>
      <p style="margin:0 0 16px;color:#e0e0e0;font-size:15px;font-weight:600;">${name} <span style="color:#555;font-weight:400;">(${email})</span></p>
      <p style="margin:0 0 8px;color:#aaa;font-size:13px;">Serviço</p>
      <p style="margin:0 0 16px;color:#e0e0e0;font-size:14px;">${description}</p>
      <p style="margin:0 0 8px;color:#aaa;font-size:13px;">Valor</p>
      <p style="margin:0;font-size:22px;font-weight:700;color:#4ade80;">${formatBRL(amount)}</p>
    </div>
  `)
}
