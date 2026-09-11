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
    // SEC-05 — ver comentário em _shared/auth.ts.
    const auth = await autorizar(req, ['super_admin', 'manager'])
    if (!auth.ok) return json({ error: auth.erro }, auth.status)

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    if (!(await withinRateLimit(supabaseAdmin, `create-employee:${auth.user!.id}`, 15, 300))) {
      return json({ error: 'Muitas requisições. Aguarde um minuto.' }, 429)
    }

    const { email, full_name, job_title, password } = await req.json()
    if (!email?.trim()) return json({ error: 'E-mail é obrigatório' }, 400)
    if (!password?.trim()) return json({ error: 'Senha é obrigatória' }, 400)
    if (!job_title?.trim()) return json({ error: 'Cargo é obrigatório' }, 400)

    const { data, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email: email.trim(),
      password: password.trim(),
      email_confirm: true,
      user_metadata: { full_name },
    })
    if (createError) return json({ error: createError.message }, 400)

    const { error: profileError } = await supabaseAdmin.from('profiles').upsert({
      id: data.user.id,
      full_name: full_name?.trim() || '',
      email: email.trim(),
      job_title: job_title.trim(),
      role: 'employee',
      updated_at: new Date().toISOString(),
    })
    if (profileError) console.error('Profile upsert error:', profileError)

    return json({ success: true, user_id: data.user.id })

  } catch (err) {
    console.error('[create-employee] erro inesperado:', err)
    return json({ error: 'Erro inesperado' }, 500)
  }
})
