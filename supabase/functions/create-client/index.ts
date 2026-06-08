import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const ADMIN_EMAILS = (Deno.env.get('ADMIN_EMAILS')
  ?? 'moutinhoezer@gmail.com,erickvin49@gmail.com,sofiagramelich@icloud.com')
  .split(',').map(e => e.trim())

const ALLOWED_ORIGINS = [
  'https://www.pixelry.com.br',
  'https://pixelry.com.br',
  'http://localhost:5173',
  'http://localhost:3000',
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

    // Verify caller is admin
    const supabaseAnon = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
    )
    const { data: { user }, error: authError } = await supabaseAnon.auth.getUser(
      authHeader.replace('Bearer ', '')
    )

    const { data: callerProfile } = await supabaseAnon
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .single()

    const isAuthorized = ADMIN_EMAILS.includes(user.email ?? '') ||
      ['super_admin', 'manager'].includes(callerProfile?.role ?? '')

    if (authError || !user || !isAuthorized) {
      return new Response(JSON.stringify({ error: 'Acesso negado' }), { status: 403, headers: cors })
    }

    const { email, full_name, company_name } = await req.json()

    if (!email?.trim()) {
      return new Response(JSON.stringify({ error: 'Email é obrigatório' }), { status: 400, headers: cors })
    }

    // Use service role to invite user
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data, error: inviteError } = await supabaseAdmin.auth.admin.inviteUserByEmail(email.trim(), {
      data: { full_name, company_name },
    })

    if (inviteError) {
      return new Response(JSON.stringify({ error: inviteError.message }), { status: 400, headers: cors })
    }

    // Create profile immediately so client appears in admin list
    const { error: profileError } = await supabaseAdmin.from('profiles').upsert({
      id: data.user.id,
      full_name: full_name?.trim() || '',
      company_name: company_name?.trim() || '',
      email: email.trim(),
      role: 'client',
    })

    if (profileError) {
      console.error('Profile upsert error:', profileError)
    }

    return new Response(
      JSON.stringify({ success: true, user_id: data.user.id }),
      { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } }
    )

  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error).message ?? 'Erro inesperado' }),
      { status: 500, headers: getCors(req) }
    )
  }
})
