import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const SUPER_ADMIN_EMAILS = (import.meta.env.VITE_SUPER_ADMIN_EMAILS || '')
  .split(',').map(e => e.trim()).filter(Boolean)

export const MANAGER_EMAILS = (import.meta.env.VITE_MANAGER_EMAILS || '')
  .split(',').map(e => e.trim()).filter(Boolean)

export const ADMIN_EMAILS = [...SUPER_ADMIN_EMAILS, ...MANAGER_EMAILS]

// true se o e-mail pertence à equipe (super_admin ou manager).
export function isAdminEmail(email) {
  return Boolean(email) && ADMIN_EMAILS.includes(email)
}

export const ROLE_LEVELS = {
  super_admin: 4,
  manager:     3,
  employee:    2,
  client:      1,
}

export function hasMinRole(userRole, minRole) {
  return (ROLE_LEVELS[userRole] || 0) >= (ROLE_LEVELS[minRole] || 0)
}

export const STORAGE_BUCKET = 'deliveries'
export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey)

if (!isSupabaseConfigured) {
  console.warn('Supabase URL or Anon Key is missing. The portal will run in preview mode.')
}

export const supabase = isSupabaseConfigured
  ? createClient(supabaseUrl, supabaseAnonKey)
  : null
