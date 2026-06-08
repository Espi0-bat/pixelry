import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200 })
  }

  try {
    const body = await req.text()

    // Validate HMAC-SHA256 signature sent by MercadoPago
    const webhookSecret = Deno.env.get('MERCADOPAGO_WEBHOOK_SECRET')
    if (webhookSecret) {
      const xSignature = req.headers.get('x-signature') ?? ''
      const xRequestId = req.headers.get('x-request-id') ?? ''
      const url = new URL(req.url)
      const dataId = url.searchParams.get('data.id') ?? ''

      // Signature format: "ts=<timestamp>,v1=<hash>"
      const sigParts = Object.fromEntries(xSignature.split(',').map(p => p.split('=')))
      const ts = sigParts['ts'] ?? ''
      const v1 = sigParts['v1'] ?? ''

      if (!ts || !v1) {
        console.warn('[payment-webhook] Missing or malformed signature — request rejected')
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

      if (computed !== v1) {
        console.warn('[payment-webhook] Invalid signature — request rejected')
        return new Response('Invalid signature', { status: 401 })
      }
    }

    const payload = JSON.parse(body)

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
    }

    // Always return 200 so MercadoPago does not retry
    return new Response('ok', { status: 200 })

  } catch (err) {
    console.error('[payment-webhook] Unhandled error:', err)
    return new Response('ok', { status: 200 })
  }
})
