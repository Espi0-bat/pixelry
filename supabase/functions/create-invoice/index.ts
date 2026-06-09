import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendEmail, templateInvoiceCreated } from '../_shared/resend.ts'

const adminEmailsEnv = Deno.env.get('ADMIN_EMAILS')
if (!adminEmailsEnv) throw new Error('ADMIN_EMAILS env var is required')
const ADMIN_EMAILS = adminEmailsEnv.split(',').map(e => e.trim())

const ALLOWED_ORIGINS = [
  'https://www.pixelry.com.br',
  'https://pixelry.com.br',
]

function getCors(req: Request) {
  const origin = req.headers.get('origin') ?? ''
  const allowed = ALLOWED_ORIGINS.includes(origin) ? origin : 'https://www.pixelry.com.br'
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
}

serve(async (req) => {
  const cors = getCors(req)

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Não autorizado' }), { status: 401, headers: cors })
    }

    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
    )

    const { data: { user }, error: authError } = await supabaseAnon.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Não autorizado' }), { status: 401, headers: cors })
    }

    const { data: callerProfile } = await supabaseAnon
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single()

    const isAdmin = ADMIN_EMAILS.includes(user.email ?? '') ||
      ['super_admin', 'manager'].includes(callerProfile?.role ?? '')

    if (!isAdmin) {
      return new Response(JSON.stringify({ error: 'Acesso negado' }), { status: 403, headers: cors })
    }

    const { client_id, amount, description, due_date } = await req.json()

    if (!client_id || !amount || !description) {
      return new Response(
        JSON.stringify({ error: 'client_id, amount e description são obrigatórios' }),
        { status: 400, headers: cors }
      )
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: clientProfile } = await supabaseAdmin
      .from('profiles')
      .select('email, full_name, company_name, contact_info')
      .eq('id', client_id)
      .single()

    const mpToken = Deno.env.get('MERCADOPAGO_ACCESS_TOKEN')!
    const appUrl = Deno.env.get('VITE_APP_URL') ?? 'https://www.pixelry.com.br'
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const webhookUrl = `${supabaseUrl}/functions/v1/payment-webhook`

    const preferenceBody: Record<string, unknown> = {
      items: [{
        title: description,
        quantity: 1,
        unit_price: Number(amount),
        currency_id: 'BRL',
      }],
      payer: {
        email: clientProfile?.email ?? 'cliente@pixelry.com.br',
        name: clientProfile?.full_name || clientProfile?.company_name || 'Cliente Pixelry',
      },
      back_urls: {
        success: `${appUrl}/portal`,
        failure: `${appUrl}/portal`,
        pending: `${appUrl}/portal`,
      },
      auto_return: 'approved',
      notification_url: webhookUrl,
      statement_descriptor: 'PIXELRY',
      payment_methods: { installments: 12 },
    }

    if (due_date) {
      preferenceBody.expires = true
      preferenceBody.expiration_date_to = new Date(`${due_date}T23:59:59-03:00`).toISOString()
    }

    const mpRes = await fetch('https://api.mercadopago.com/checkout/preferences', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${mpToken}`,
        'Content-Type': 'application/json',
        'X-Idempotency-Key': crypto.randomUUID(),
      },
      body: JSON.stringify(preferenceBody),
    })

    if (!mpRes.ok) {
      const errBody = await mpRes.text()
      console.error('[create-invoice] MercadoPago error:', errBody)
      return new Response(
        JSON.stringify({ error: 'Erro ao criar cobrança no MercadoPago', detail: errBody }),
        { status: 502, headers: cors }
      )
    }

    const preference = await mpRes.json()

    // Attempt direct Pix QR code generation if CPF is stored in contact_info
    let qrCode: string | null = null
    let qrCodeText: string | null = null

    const cpf = clientProfile?.contact_info?.cpf?.replace(/\D/g, '') ?? null
    if (cpf && cpf.length === 11) {
      const pixRes = await fetch('https://api.mercadopago.com/v1/payments', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${mpToken}`,
          'Content-Type': 'application/json',
          'X-Idempotency-Key': crypto.randomUUID(),
        },
        body: JSON.stringify({
          transaction_amount: Number(amount),
          description,
          payment_method_id: 'pix',
          payer: {
            email: clientProfile?.email ?? 'cliente@pixelry.com.br',
            identification: { type: 'CPF', number: cpf },
          },
        }),
      })

      if (pixRes.ok) {
        const pixPayment = await pixRes.json()
        qrCode = pixPayment?.point_of_interaction?.transaction_data?.qr_code_base64 ?? null
        qrCodeText = pixPayment?.point_of_interaction?.transaction_data?.qr_code ?? null
      }
    }

    const { data: invoice, error: insertError } = await supabaseAdmin
      .from('invoices')
      .insert({
        client_id,
        amount: Number(amount),
        description,
        due_date: due_date ?? null,
        status: 'pending',
        mp_preference_id: preference.id,
        payment_url: preference.init_point,
        qr_code: qrCode,
        qr_code_text: qrCodeText,
      })
      .select('*')
      .single()

    if (insertError) {
      console.error('[create-invoice] Insert error:', insertError)
      return new Response(JSON.stringify({ error: 'Erro ao salvar fatura' }), { status: 500, headers: cors })
    }

    // Send invoice notification email — failure must not break the response
    try {
      const clientEmail = clientProfile?.contact_info?.emails?.[0] ?? clientProfile?.email
      if (clientEmail) {
        await sendEmail(
          clientEmail,
          'Você tem uma nova cobrança — Pixelry',
          templateInvoiceCreated(
            clientProfile?.full_name ?? clientProfile?.company_name ?? null,
            invoice.amount,
            invoice.description,
            invoice.payment_url ?? null,
            invoice.qr_code_text ?? null,
            invoice.due_date ?? null,
          )
        )
      }
    } catch (emailErr) {
      console.error('[create-invoice] Falha ao enviar email:', emailErr)
    }

    return new Response(
      JSON.stringify({ success: true, invoice }),
      { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } }
    )

  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error).message ?? 'Erro inesperado' }),
      { status: 500, headers: getCors(req) }
    )
  }
})
