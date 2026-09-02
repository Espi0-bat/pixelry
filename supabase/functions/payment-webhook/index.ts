import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendEmail, templatePaymentConfirmed, templateAdminPaymentAlert } from '../_shared/resend.ts'

/** Comparação em tempo constante — evita vazar informação pelo tempo de resposta. */
function igualdadeSegura(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let diff = 0
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return diff === 0
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200 })
  }

  try {
    const body = await req.text()

    // SEC-03 — a validação inteira ficava dentro de `if (webhookSecret)`. Sem a
    // variável definida — não configurada ainda, removida num redeploy, com o
    // nome trocado — a função aceitava qualquer requisição e marcava fatura como
    // paga. Endpoint de pagamento precisa falhar fechado.
    const webhookSecret = Deno.env.get('MERCADOPAGO_WEBHOOK_SECRET')
    if (!webhookSecret) {
      console.error('[payment-webhook] MERCADOPAGO_WEBHOOK_SECRET ausente — recusando')
      return new Response('Webhook not configured', { status: 503 })
    }

    const xSignature = req.headers.get('x-signature') ?? ''
    const xRequestId = req.headers.get('x-request-id') ?? ''
    const url = new URL(req.url)
    const dataId = url.searchParams.get('data.id') ?? ''

    // Formato da assinatura: "ts=<timestamp>,v1=<hash>"
    const sigParts = Object.fromEntries(xSignature.split(',').map(p => p.split('=')))
    const ts = sigParts['ts'] ?? ''
    const v1 = sigParts['v1'] ?? ''

    if (!ts || !v1) {
      console.warn('[payment-webhook] assinatura ausente ou malformada — recusada')
      return new Response('Invalid signature', { status: 401 })
    }

    const manifest = `id:${dataId};request-id:${xRequestId};ts:${ts};`
    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(webhookSecret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign']
    )
    const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(manifest))
    const computed = Array.from(new Uint8Array(sig))
      .map(b => b.toString(16).padStart(2, '0'))
      .join('')

    if (!igualdadeSegura(computed, v1)) {
      console.warn('[payment-webhook] assinatura inválida — recusada')
      return new Response('Invalid signature', { status: 401 })
    }

    // Frescor: sem isto, uma requisição capturada pode ser repetida para sempre.
    const idadeSegundos = Math.abs(Date.now() / 1000 - Number(ts))
    if (!Number.isFinite(idadeSegundos) || idadeSegundos > 300) {
      console.warn('[payment-webhook] assinatura fora da janela de 5 min — recusada')
      return new Response('Stale signature', { status: 401 })
    }

    const payload = JSON.parse(body)

    // O manifesto assina o data.id da query string, mas o código age sobre o
    // data.id do corpo. Sem comparar os dois, a assinatura garante um id e a
    // execução usa outro.
    if (String(payload.data?.id ?? '') !== String(dataId)) {
      console.warn('[payment-webhook] id do corpo difere do id assinado — recusada')
      return new Response('Payload mismatch', { status: 401 })
    }

    // MercadoPago also sends "test" and other types — only handle payments
    if (payload.type !== 'payment') {
      return new Response('ok', { status: 200 })
    }

    const paymentId = payload.data?.id
    if (!paymentId) {
      return new Response('ok', { status: 200 })
    }

    const mpToken = Deno.env.get('MERCADOPAGO_ACCESS_TOKEN')!

    const paymentRes = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
      headers: { 'Authorization': `Bearer ${mpToken}` },
    })

    if (!paymentRes.ok) {
      console.error('[payment-webhook] Failed to fetch payment:', paymentId, await paymentRes.text())
      return new Response('ok', { status: 200 })
    }

    const payment = await paymentRes.json()

    if (payment.status !== 'approved') {
      return new Response('ok', { status: 200 })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // Match invoice by preference_id (all payment methods share the same preference)
    const { error } = await supabase
      .from('invoices')
      .update({
        status: 'paid',
        paid_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('mp_preference_id', payment.preference_id)
      .eq('status', 'pending')

    if (error) {
      console.error('[payment-webhook] Update error:', error)
    } else {
      console.log('[payment-webhook] Invoice marked as paid for preference:', payment.preference_id)

      // Send confirmation emails — failure must not affect the 200 response
      try {
        const { data: invoice } = await supabase
          .from('invoices')
          .select('amount, description, paid_at, client_id, profiles(email, full_name, company_name, contact_info)')
          .eq('mp_preference_id', payment.preference_id)
          .single()

        const profile = (invoice as any)?.profiles
        const clientEmail = profile?.contact_info?.emails?.[0] ?? profile?.email
        const clientName = profile?.full_name ?? profile?.company_name ?? null

        if (clientEmail) {
          await sendEmail(
            clientEmail,
            'Pagamento confirmado — Pixelry',
            templatePaymentConfirmed(clientName, invoice.amount, invoice.description, invoice.paid_at ?? null)
          )
        }

        const adminEmailsEnv = Deno.env.get('ADMIN_EMAILS') ?? ''
        const adminEmails = adminEmailsEnv.split(',').map((e: string) => e.trim()).filter(Boolean)
        for (const adminEmail of adminEmails) {
          await sendEmail(
            adminEmail,
            `Pagamento recebido: ${clientName ?? clientEmail ?? 'cliente'} — R$ ${invoice.amount}`,
            templateAdminPaymentAlert(clientName, clientEmail ?? null, invoice.amount, invoice.description)
          )
        }
      } catch (emailErr) {
        console.error('[payment-webhook] Falha ao enviar emails:', emailErr)
      }
    }

    // Always return 200 so MercadoPago does not retry
    return new Response('ok', { status: 200 })

  } catch (err) {
    console.error('[payment-webhook] Unhandled error:', err)
    return new Response('ok', { status: 200 })
  }
})
