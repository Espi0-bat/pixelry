import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

export const ADMIN_EMAIL = import.meta.env.VITE_ADMIN_EMAIL || 'moutinhoezer@gmail.com'
export const ADMIN_EMAILS = (import.meta.env.VITE_ADMIN_EMAILS || 'moutinhoezer@gmail.com,erickvin49@gmail.com').split(',').map(e => e.trim())
export const STORAGE_BUCKET = 'deliveries'
export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey)

if (!isSupabaseConfigured) {
  console.warn('Supabase URL or Anon Key is missing. The portal will run in preview mode.')
}

export const supabase = isSupabaseConfigured
  ? createClient(supabaseUrl, supabaseAnonKey)
  : null
