// Rate limiting compartilhado, apoiado na função SQL public.check_rate_limit.
// Precisa de um client com service_role (a função é grant-only p/ esse papel).

// deno-lint-ignore no-explicit-any
type SupabaseClient = any

/**
 * @returns `true` se a chamada está DENTRO do limite; `false` se estourou.
 * Falha "aberta" (retorna true) se o RPC der erro — não queremos derrubar
 * tráfego legítimo por soluço de infra; as outras camadas (honeypot,
 * constraints, trigger de flood) seguem valendo.
 */
export async function withinRateLimit(
  admin: SupabaseClient,
  bucket: string,
  limit: number,
  windowSeconds: number,
): Promise<boolean> {
  const { data, error } = await admin.rpc('check_rate_limit', {
    p_bucket: bucket,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  })
  if (error) {
    console.error('[rateLimit] check_rate_limit falhou, liberando:', error.message)
    return true
  }
  return data === true
}

/** Extrai um identificador de origem para chavear o limite (best-effort). */
export function clientKey(req: Request): string {
  const fwd = req.headers.get('x-forwarded-for') ?? ''
  const ip = fwd.split(',')[0].trim() || req.headers.get('cf-connecting-ip') || 'unknown'
  return ip
}
