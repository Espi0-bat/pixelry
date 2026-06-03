import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const ADMIN_EMAILS = (Deno.env.get('ADMIN_EMAILS') ?? 'moutinhoezer@gmail.com,erickvin49@gmail.com')
  .split(',').map(e => e.trim())

const cors = {
  'Access-Control-Allow-Origin': 'https://www.pixelry.com.br',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
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

    if (authError || !user || !ADMIN_EMAILS.includes(user.email ?? '')) {
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
      JSON.stringify({ error: err.message ?? 'Erro inesperado' }),
      { status: 500, headers: cors }
    )
  }
})
