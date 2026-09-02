import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendEmail, templateInvoiceCreated } from '../_shared/resend.ts'
import { autorizar, cors } from '../_shared/auth.ts'
import { withinRateLimit } from '../_shared/rateLimit.ts'

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('')
}

serve(async (req) => {
  const headers = cors(req)
  const json = (obj: unknown, status = 200) =>
    new Response(JSON.stringify(obj), { status, headers: { ...headers, 'Content-Type': 'application/json' } })

  if (req.method === 'OPTIONS') return new Response('ok', { headers })

  try {
    // SEC-05 — a checagem inline criava o cliente com a chave anon sem repassar
    // o JWT, então a consulta a profiles rodava como anon, voltava nula e o
    // teste de papel virava código morto. autorizar() manda o header junto.
    const auth = await autorizar(req, ['super_admin', 'manager'])
    if (!auth.ok) return json({ error: auth.erro }, auth.status)

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // Rate limit por usuário (defesa em profundidade — a rota já é admin-only).
    if (!(await withinRateLimit(supabaseAdmin, `create-invoice:${auth.user!.id}`, 20, 300))) {
      return json({ error: 'Muitas cobranças em sequência. Aguarde um minuto.' }, 429)
    }

    const { client_id, amount, description, due_date } = await req.json()
    if (!client_id || !amount || !description) {
      return json({ error: 'client_id, amount e description são obrigatórios' }, 400)
    }

    const amountNum = Number(amount)
    if (!Number.isFinite(amountNum) || amountNum <= 0) {
      return json({ error: 'amount inválido' }, 400)
    }
    const desc = String(description).trim()
    const dueDate: string | null = due_date ?? null

    // Chave determinística: mesma cobrança lógica => mesma chave => sem duplicata.
    const idempotencyKey = await sha256Hex(
      `${client_id}|${amountNum.toFixed(2)}|${desc}|${dueDate ?? ''}`,
    )

    // ── 1. Reivindica a cobrança gravando um rascunho ANTES de falar com o MP ──
    let invoiceRow: Record<string, any> | null = null
    const { data: draft, error: draftErr } = await supabaseAdmin
      .from('invoices')
      .insert({
        client_id,
        amount: amountNum,
        description: desc,
        due_date: dueDate,
        status: 'draft',
        idempotency_key: idempotencyKey,
      })
      .select('*')
      .maybeSingle()

    if (draftErr) {
      if (draftErr.code === '23505') {
        // Já existe (ou está sendo criada) uma cobrança idêntica.
        const { data: existing } = await supabaseAdmin
          .from('invoices')
          .select('*')
          .eq('idempotency_key', idempotencyKey)
          .neq('status', 'cancelled')
          .maybeSingle()

        if (existing?.mp_preference_id) {
          return json({ success: true, invoice: existing, deduplicated: true })
        }
        // Rascunho preso? Se for velho, assume abandonado e reaproveita.
        const stale = existing?.status === 'draft' &&
          Date.now() - new Date(existing.created_at).getTime() > 120_000
        if (existing?.status === 'draft' && !stale) {
          return json({ error: 'Uma cobrança idêntica está sendo processada. Tente de novo em alguns segundos.' }, 409)
        }
        invoiceRow = existing ?? null
        if (!invoiceRow) return json({ error: 'Conflito ao criar cobrança' }, 409)
      } else {
        console.error('[create-invoice] erro ao gravar rascunho:', draftErr)
        return json({ error: 'Erro ao salvar fatura' }, 500)
      }
    } else {
      invoiceRow = draft
    }

    // A partir daqui, qualquer falha remove o rascunho para permitir nova tentativa.
    const rollbackDraft = async () => {
      await supabaseAdmin.from('invoices').delete().eq('id', invoiceRow!.id).eq('status', 'draft')
    }

    try {
      const { data: clientProfile } = await supabaseAdmin
        .from('profiles')
        .select('email, full_name, company_name, contact_info')
        .eq('id', client_id)
        .single()

      const mpToken = Deno.env.get('MERCADOPAGO_ACCESS_TOKEN')!
      const appUrl = Deno.env.get('VITE_APP_URL') ?? 'https://www.pixelry.com.br'
      const webhookUrl = `${Deno.env.get('SUPABASE_URL')!}/functions/v1/payment-webhook`

      const preferenceBody: Record<string, unknown> = {
        items: [{ title: desc, quantity: 1, unit_price: amountNum, currency_id: 'BRL' }],
        payer: {
          email: clientProfile?.email ?? 'cliente@pixelry.com.br',
          name: clientProfile?.full_name || clientProfile?.company_name || 'Cliente Pixelry',
        },
        back_urls: { success: `${appUrl}/portal`, failure: `${appUrl}/portal`, pending: `${appUrl}/portal` },
        auto_return: 'approved',
        notification_url: webhookUrl,
        statement_descriptor: 'PIXELRY',
        payment_methods: { installments: 12 },
        external_reference: invoiceRow!.id,
      }
      if (dueDate) {
        preferenceBody.expires = true
        preferenceBody.expiration_date_to = new Date(`${dueDate}T23:59:59-03:00`).toISOString()
      }

      const mpRes = await fetch('https://api.mercadopago.com/checkout/preferences', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${mpToken}`,
          'Content-Type': 'application/json',
          // Chave determinística: retry / duplo-submit não geram 2ª preferência.
          'X-Idempotency-Key': idempotencyKey,
        },
        body: JSON.stringify(preferenceBody),
      })

      if (!mpRes.ok) {
        const errBody = await mpRes.text()
        console.error('[create-invoice] erro do Mercado Pago:', errBody)
        await rollbackDraft()
        return json({ error: 'Erro ao criar cobrança no MercadoPago', detail: errBody }, 502)
      }

      const preference = await mpRes.json()

      // Pix direto (QR) se houver CPF salvo.
      let qrCode: string | null = null
      let qrCodeText: string | null = null
      const cpf = clientProfile?.contact_info?.cpf?.replace(/\D/g, '') ?? null
      if (cpf && cpf.length === 11) {
        const pixRes = await fetch('https://api.mercadopago.com/v1/payments', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${mpToken}`,
            'Content-Type': 'application/json',
            'X-Idempotency-Key': `${idempotencyKey}:pix`,
          },
          body: JSON.stringify({
            transaction_amount: amountNum,
            description: desc,
            payment_method_id: 'pix',
            payer: { email: clientProfile?.email ?? 'cliente@pixelry.com.br', identification: { type: 'CPF', number: cpf } },
          }),
        })
        if (pixRes.ok) {
          const pixPayment = await pixRes.json()
          qrCode = pixPayment?.point_of_interaction?.transaction_data?.qr_code_base64 ?? null
          qrCodeText = pixPayment?.point_of_interaction?.transaction_data?.qr_code ?? null
        }
      }

      // ── 2. Finaliza: draft -> pending, com os dados do Mercado Pago ──
      const { data: finalRow, error: finalErr } = await supabaseAdmin
        .from('invoices')
        .update({
          status: 'pending',
          mp_preference_id: preference.id,
          payment_url: preference.init_point,
          qr_code: qrCode,
          qr_code_text: qrCodeText,
          updated_at: new Date().toISOString(),
        })
        .eq('id', invoiceRow!.id)
        .select('*')
        .single()

      if (finalErr) {
        console.error('[create-invoice] erro ao finalizar fatura:', finalErr)
        return json({ error: 'Erro ao salvar fatura' }, 500)
      }

      // E-mail de aviso — falha não quebra a resposta.
      try {
        const clientEmail = clientProfile?.contact_info?.emails?.[0] ?? clientProfile?.email
        if (clientEmail) {
          await sendEmail(
            clientEmail,
            'Você tem uma nova cobrança — Pixelry',
            templateInvoiceCreated(
              clientProfile?.full_name ?? clientProfile?.company_name ?? null,
              finalRow.amount, finalRow.description, finalRow.payment_url ?? null,
              finalRow.qr_code_text ?? null, finalRow.due_date ?? null,
            ),
          )
        }
      } catch (emailErr) {
        console.error('[create-invoice] falha ao enviar e-mail:', emailErr)
      }

      return json({ success: true, invoice: finalRow })

    } catch (err) {
      console.error('[create-invoice] erro no fluxo de cobrança:', err)
      await rollbackDraft()
      return json({ error: (err as Error).message ?? 'Erro inesperado' }, 500)
    }

  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error).message ?? 'Erro inesperado' }),
      { status: 500, headers: { ...cors(req), 'Content-Type': 'application/json' } },
    )
  }
})
