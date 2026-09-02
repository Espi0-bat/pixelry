import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { cors } from '../_shared/auth.ts'
import { withinRateLimit, clientKey } from '../_shared/rateLimit.ts'

// Formulário público de captação de lead.
// Camadas: honeypot -> rate limit por IP -> validação -> insert via service_role.
// verify_jwt = false (é público) — a proteção é toda aqui dentro.

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/

const clamp = (v: unknown, max: number): string | null => {
  if (typeof v !== 'string') return null
  const t = v.trim()
  return t ? t.slice(0, max) : null
}

serve(async (req) => {
  const headers = cors(req)
  const json = (obj: unknown, status = 200) =>
    new Response(JSON.stringify(obj), { status, headers: { ...headers, 'Content-Type': 'application/json' } })

  if (req.method === 'OPTIONS') return new Response('ok', { headers })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const payload = await req.json().catch(() => null)
    if (!payload || typeof payload !== 'object') return json({ error: 'Payload inválido' }, 400)

    // ── Honeypot: campo invisível preenchido => bot. Responde 200 e descarta. ──
    if (typeof payload.company === 'string' && payload.company.trim() !== '') {
      return json({ ok: true })
    }

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // ── Rate limit por IP: 5 / minuto, 30 / hora ──
    const ip = clientKey(req)
    const okMinute = await withinRateLimit(admin, `lead:m:${ip}`, 5, 60)
    const okHour = await withinRateLimit(admin, `lead:h:${ip}`, 30, 3600)
    if (!okMinute || !okHour) {
      return json({ error: 'Muitas tentativas. Tente novamente em instantes.' }, 429)
    }

    // ── Validação ──
    const name = clamp(payload.name, 200)
    const email = clamp(payload.email, 320)?.toLowerCase() ?? null
    if (!name) return json({ error: 'Nome é obrigatório' }, 400)
    if (!email || !EMAIL_RE.test(email)) return json({ error: 'E-mail inválido' }, 400)

    const row = {
      name,
      email,
      whatsapp: clamp(payload.whatsapp, 40),
      instagram: clamp(payload.instagram, 120),
      clinic_type: clamp(payload.clinic_type, 120),
      revenue_range: clamp(payload.revenue_range, 60),
      investment_range: clamp(payload.investment_range, 60),
      source: clamp(payload.source, 80) ?? 'diagnostico_hero',
    }

    const { error } = await admin.from('leads').insert(row)
    if (error) {
      // Trigger de flood dispara errcode 53400.
      if (error.code === '53400') return json({ error: 'Estamos recebendo muitos contatos agora. Tente em 1 minuto.' }, 429)
      console.error('[submit-lead] insert error:', error)
      return json({ error: 'Não foi possível registrar. Tente novamente.' }, 500)
    }

    return json({ ok: true })

  } catch (err) {
    console.error('[submit-lead] erro:', err)
    return json({ error: 'Erro inesperado' }, 500)
  }
})
