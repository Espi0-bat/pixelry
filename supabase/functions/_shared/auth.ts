import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

export type Papel = 'super_admin' | 'manager' | 'employee' | 'client'

export interface Resultado {
  ok: boolean
  status: number
  erro?: string
  user?: { id: string; email: string | undefined }
  papel?: string
}

/**
 * Autoriza o chamador de uma Edge Function.
 *
 * Duas coisas que a implementação copiada em cada função errava:
 *
 * 1. O cliente Supabase era criado com a chave anon SEM repassar o JWT de quem
 *    chamou, então a consulta a `profiles` rodava como `anon`. Sob as políticas
 *    atuais o anon não enxerga nenhuma linha, o perfil voltava nulo e a
 *    checagem de papel virava código morto — sobrava só a lista ADMIN_EMAILS.
 *    Aqui o header vai junto e a RLS resolve sob a identidade real.
 *
 * 2. Em create-client o `user.id` era lido antes do teste de nulo, o que
 *    transformava token inválido em 500 em vez de 401.
 */
export async function autorizar(req: Request, papeisPermitidos: Papel[]): Promise<Resultado> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) {
    return { ok: false, status: 401, erro: 'Não autorizado' }
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  )

  const { data: { user }, error } = await supabase.auth.getUser(
    authHeader.replace('Bearer ', ''),
  )
  if (error || !user) {
    return { ok: false, status: 401, erro: 'Não autorizado' }
  }

  const { data: perfil } = await supabase
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .single()

  const adminEmails = (Deno.env.get('ADMIN_EMAILS') ?? '')
    .split(',')
    .map((e) => e.trim())
    .filter(Boolean)

  const papel = perfil?.role ?? ''
  const autorizado =
    adminEmails.includes(user.email ?? '') ||
    (papeisPermitidos as string[]).includes(papel)

  if (!autorizado) {
    return { ok: false, status: 403, erro: 'Acesso negado' }
  }

  return { ok: true, status: 200, user: { id: user.id, email: user.email }, papel }
}

/** Origens que podem chamar as funções a partir do navegador. */
export const ORIGENS_PERMITIDAS = [
  'https://www.pixelry.com.br',
  'https://pixelry.com.br',
  'http://localhost:5173',
  'http://localhost:3000',
]

export function cors(req: Request): Record<string, string> {
  const origem = req.headers.get('origin') ?? ''
  return {
    'Access-Control-Allow-Origin': ORIGENS_PERMITIDAS.includes(origem)
      ? origem
      : 'https://www.pixelry.com.br',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
}
