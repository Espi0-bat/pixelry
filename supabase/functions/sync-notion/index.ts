import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const NOTION_VERSION = '2022-06-28'

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

const PRIORITY_MAP: Record<string, string> = { high: 'Alta', medium: 'Media', low: 'Baixa' }
const STATUS_MAP:   Record<string, string> = { done: 'Concluida', pending: 'Pendente' }

serve(async (req) => {
  const cors = getCors(req)
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  // Require auth — only authenticated users can trigger Notion sync
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

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // Ler token e DB ID do Vault
    const [{ data: tokenRow }, { data: dbRow }] = await Promise.all([
      supabaseAdmin.rpc('get_vault_secret', { secret_name: 'notion_token' }),
      supabaseAdmin.rpc('get_vault_secret', { secret_name: 'notion_db_id' }),
    ])

    const notionToken = tokenRow as string
    const notionDbId  = dbRow  as string

    if (!notionToken || !notionDbId) {
      return new Response(JSON.stringify({ error: 'Notion credentials not found' }), { status: 500, headers: cors })
    }

    const { action, goal } = await req.json()
    if (!action || !goal) {
      return new Response(
        JSON.stringify({ error: 'action e goal são obrigatórios' }),
        { status: 400, headers: cors }
      )
    }
    // action: 'upsert' | 'delete'

    const notionHeaders = {
      'Authorization': `Bearer ${notionToken}`,
      'Notion-Version': NOTION_VERSION,
      'Content-Type': 'application/json',
    }

    // ── DELETE: arquiva a página no Notion ──────────────────────────────────
    if (action === 'delete') {
      if (goal.notion_page_id) {
        await fetch(`https://api.notion.com/v1/pages/${goal.notion_page_id}`, {
          method: 'PATCH',
          headers: notionHeaders,
          body: JSON.stringify({ archived: true }),
        })
      }
      return new Response(JSON.stringify({ success: true }), { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    // ── UPSERT: cria ou atualiza ────────────────────────────────────────────
    const properties: Record<string, unknown> = {
      'Meta':       { title:  [{ text: { content: goal.title } }] },
      'Status':     { select: { name: STATUS_MAP[goal.status]   ?? 'Pendente' } },
      'Prioridade': { select: { name: PRIORITY_MAP[goal.priority] ?? 'Media'  } },
      'Semana':     { date:   { start: goal.week_start } },
    }
    if (goal.category)    properties['Categoria']  = { select:     { name: goal.category } }
    if (goal.assignee)    properties['Responsavel'] = { rich_text: [{ text: { content: goal.assignee } }] }
    if (goal.description) properties['Descricao']   = { rich_text: [{ text: { content: goal.description } }] }

    let notionPageId = goal.notion_page_id

    if (notionPageId) {
      await fetch(`https://api.notion.com/v1/pages/${notionPageId}`, {
        method: 'PATCH',
        headers: notionHeaders,
        body: JSON.stringify({ properties }),
      })
    } else {
      const res  = await fetch('https://api.notion.com/v1/pages', {
        method: 'POST',
        headers: notionHeaders,
        body: JSON.stringify({ parent: { database_id: notionDbId }, properties }),
      })
      const page = await res.json()
      notionPageId = page.id

      // Salva notion_page_id de volta no Supabase
      await supabaseAdmin
        .from('weekly_goals')
        .update({ notion_page_id: notionPageId })
        .eq('id', goal.id)
    }

    return new Response(
      JSON.stringify({ success: true, notion_page_id: notionPageId }),
      { headers: { ...cors, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      { status: 500, headers: cors }
    )
  }
})
