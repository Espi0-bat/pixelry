import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { autorizar, cors } from '../_shared/auth.ts'

const NOTION_VERSION = '2022-06-28'

const PRIORITY_MAP: Record<string, string> = { high: 'Alta', medium: 'Media', low: 'Baixa' }
const STATUS_MAP:   Record<string, string> = { done: 'Concluida', pending: 'Pendente' }

const json = (corpo: unknown, status: number, headers: Record<string, string>) =>
  new Response(JSON.stringify(corpo), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json' },
  })

serve(async (req) => {
  const headers = cors(req)
  if (req.method === 'OPTIONS') return new Response('ok', { headers })

  // SEC-02 — antes esta função só verificava se existia um usuário válido e
  // seguia. Como ela age com service_role e com o token do Notion, qualquer
  // cliente do portal podia arquivar páginas do workspace e escrever em
  // weekly_goals. Agora exige papel, como as outras funções.
  const auth = await autorizar(req, ['super_admin', 'manager'])
  if (!auth.ok) return json({ error: auth.erro }, auth.status, headers)

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const [{ data: tokenRow }, { data: dbRow }] = await Promise.all([
      supabaseAdmin.rpc('get_vault_secret', { secret_name: 'notion_token' }),
      supabaseAdmin.rpc('get_vault_secret', { secret_name: 'notion_db_id' }),
    ])

    const notionToken = tokenRow as string
    const notionDbId  = dbRow  as string

    if (!notionToken || !notionDbId) {
      return json({ error: 'Notion credentials not found' }, 500, headers)
    }

    const { action, goal } = await req.json()
    if (!action || !goal?.id) {
      return json({ error: 'action e goal.id são obrigatórios' }, 400, headers)
    }

    // SEC-02 — o notion_page_id NÃO vem mais do corpo da requisição. Vindo de
    // fora, ele permitia apontar a operação para qualquer página do workspace.
    // A fonte da verdade é a linha em weekly_goals.
    const { data: meta, error: metaErro } = await supabaseAdmin
      .from('weekly_goals')
      .select('id, title, status, priority, week_start, category, assignee, description, notion_page_id')
      .eq('id', goal.id)
      .single()

    if (metaErro || !meta) {
      return json({ error: 'Meta não encontrada' }, 404, headers)
    }

    const notionHeaders = {
      'Authorization': `Bearer ${notionToken}`,
      'Notion-Version': NOTION_VERSION,
      'Content-Type': 'application/json',
    }

    // ── DELETE: arquiva a página no Notion ──────────────────────────────────
    if (action === 'delete') {
      if (meta.notion_page_id) {
        const res = await fetch(`https://api.notion.com/v1/pages/${meta.notion_page_id}`, {
          method: 'PATCH',
          headers: notionHeaders,
          body: JSON.stringify({ archived: true }),
        })
        if (!res.ok) {
          console.error('[sync-notion] falha ao arquivar:', res.status, await res.text())
          return json({ error: 'Falha ao arquivar no Notion' }, 502, headers)
        }
      }
      return json({ success: true }, 200, headers)
    }

    // ── UPSERT: cria ou atualiza ────────────────────────────────────────────
    const properties: Record<string, unknown> = {
      'Meta':       { title:  [{ text: { content: meta.title } }] },
      'Status':     { select: { name: STATUS_MAP[meta.status]     ?? 'Pendente' } },
      'Prioridade': { select: { name: PRIORITY_MAP[meta.priority] ?? 'Media'    } },
      'Semana':     { date:   { start: meta.week_start } },
    }
    if (meta.category)    properties['Categoria']   = { select:    { name: meta.category } }
    if (meta.assignee)    properties['Responsavel'] = { rich_text: [{ text: { content: meta.assignee } }] }
    if (meta.description) properties['Descricao']   = { rich_text: [{ text: { content: meta.description } }] }

    let notionPageId = meta.notion_page_id

    if (notionPageId) {
      const res = await fetch(`https://api.notion.com/v1/pages/${notionPageId}`, {
        method: 'PATCH',
        headers: notionHeaders,
        body: JSON.stringify({ properties }),
      })
      if (!res.ok) {
        console.error('[sync-notion] falha ao atualizar:', res.status, await res.text())
        return json({ error: 'Falha ao atualizar no Notion' }, 502, headers)
      }
    } else {
      const res = await fetch('https://api.notion.com/v1/pages', {
        method: 'POST',
        headers: notionHeaders,
        body: JSON.stringify({ parent: { database_id: notionDbId }, properties }),
      })
      if (!res.ok) {
        console.error('[sync-notion] falha ao criar:', res.status, await res.text())
        return json({ error: 'Falha ao criar no Notion' }, 502, headers)
      }

      const page = await res.json()
      notionPageId = page.id

      await supabaseAdmin
        .from('weekly_goals')
        .update({ notion_page_id: notionPageId })
        .eq('id', meta.id)
    }

    return json({ success: true, notion_page_id: notionPageId }, 200, headers)

  } catch (err) {
    // SEC-08 — o erro completo fica no log; o cliente recebe algo genérico.
    console.error('[sync-notion] erro inesperado:', err)
    return json({ error: 'Erro inesperado' }, 500, headers)
  }
})
