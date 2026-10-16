import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const ROLE_LEVELS = {
  super_admin: 4,
  manager:     3,
  employee:    2,
  client:      1,
}

export function hasMinRole(userRole, minRole) {
  return (ROLE_LEVELS[userRole] || 0) >= (ROLE_LEVELS[minRole] || 0)
}

// Papéis que entram pelo login do painel e não usam o portal do cliente.
// Vem de profiles.role, a mesma coluna que a RLS e as Edge Functions conferem;
// nenhum e-mail da equipe fica no código nem no bundle.
export const TEAM_ROLES = ['super_admin', 'manager']

export function isTeamRole(role) {
  return TEAM_ROLES.includes(role)
}

export const STORAGE_BUCKET = 'deliveries'
export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey)

if (!isSupabaseConfigured) {
  console.warn('Supabase URL or Anon Key is missing. The portal will run in preview mode.')
}

export const supabase = isSupabaseConfigured
  ? createClient(supabaseUrl, supabaseAnonKey)
  : null

// Papel do usuário em profiles.role; null sem sessão ou sem perfil.
export async function fetchUserRole(userId) {
  if (!supabase || !userId) return null
  const { data } = await supabase.from('profiles').select('role').eq('id', userId).maybeSingle()
  return data?.role ?? null
}
