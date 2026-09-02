import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { autorizar, cors } from '../_shared/auth.ts'
import { withinRateLimit } from '../_shared/rateLimit.ts'

serve(async (req) => {
  const headers = cors(req)
  const json = (obj: unknown, status = 200) =>
    new Response(JSON.stringify(obj), { status, headers: { ...headers, 'Content-Type': 'application/json' } })

  if (req.method === 'OPTIONS') return new Response('ok', { headers })

  try {
    // SEC-05 — autorizar() repassa o JWT, então a consulta a profiles resolve
    // sob a identidade real. Também trata token inválido como 401, não 500
    // (aqui o user.id era lido antes do teste de nulo).
    const auth = await autorizar(req, ['super_admin', 'manager'])
    if (!auth.ok) return json({ error: auth.erro }, auth.status)

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    if (!(await withinRateLimit(supabaseAdmin, `create-client:${auth.user!.id}`, 20, 300))) {
      return json({ error: 'Muitas requisições. Aguarde um minuto.' }, 429)
    }

    const { email, full_name, company_name } = await req.json()
    if (!email?.trim()) return json({ error: 'Email é obrigatório' }, 400)

    const { data, error: inviteError } = await supabaseAdmin.auth.admin.inviteUserByEmail(email.trim(), {
      data: { full_name, company_name },
    })
    if (inviteError) return json({ error: inviteError.message }, 400)

    const { error: profileError } = await supabaseAdmin.from('profiles').upsert({
      id: data.user.id,
      full_name: full_name?.trim() || '',
      company_name: company_name?.trim() || '',
      email: email.trim(),
      role: 'client',
    })
    if (profileError) console.error('Profile upsert error:', profileError)

    return json({ success: true, user_id: data.user.id })

  } catch (err) {
    console.error('[create-client] erro inesperado:', err)
    return json({ error: 'Erro inesperado' }, 500)
  }
})
