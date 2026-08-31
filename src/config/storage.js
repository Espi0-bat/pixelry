import { supabase } from './supabase'

/**
 * Camada de acesso a arquivos.
 *
 * Os buckets `deliveries`, `client-uploads` e `internal-files` são PRIVADOS.
 * O acesso é feito por URL assinada, gerada sob demanda e validada pela RLS
 * do storage — quem não tem permissão simplesmente não consegue assinar.
 *
 * Retrocompatibilidade: registros antigos guardaram a URL pública inteira
 * (`/storage/v1/object/public/<bucket>/<path>`), que hoje retorna 400. As
 * funções abaixo extraem o path dessas URLs, então nada precisa ser migrado
 * no banco.
 */

export const BUCKETS = {
  deliveries: 'deliveries',
  clientUploads: 'client-uploads',
  internalFiles: 'internal-files',
  avatars: 'avatars',
}

/** Buckets que seguem públicos por serem imagens de exibição. */
const PUBLIC_BUCKETS = new Set(['avatars', 'pixelry-assets'])

const DEFAULT_EXPIRES_IN = 60 * 60 // 1 hora

/**
 * Extrai o caminho dentro do bucket a partir do que estiver salvo no banco:
 * URL pública antiga, URL assinada, ou já o próprio path.
 */
export function storagePath(urlOrPath, bucket) {
  if (!urlOrPath) return null
  const value = String(urlOrPath).trim()

  if (!value.startsWith('http')) {
    return value.replace(/^\/+/, '') || null
  }

  let pathname
  try {
    pathname = new URL(value).pathname
  } catch {
    return null
  }

  // /storage/v1/object/public/<bucket>/<path>  |  .../sign/<bucket>/<path>
  const match = pathname.match(/\/storage\/v1\/object\/(?:public|sign|authenticated)\/([^/]+)\/(.+)$/)
  if (!match) return null

  const [, urlBucket, rest] = match
  if (bucket && urlBucket !== bucket) return null

  return decodeURIComponent(rest) || null
}

/** Nome do arquivo, para exibição e para o atributo download. */
export function fileNameFrom(urlOrPath, fallback = 'arquivo') {
  const path = storagePath(urlOrPath)
  if (!path) return fallback
  const raw = path.split('/').pop() || fallback
  // paths gerados pelo app têm prefixo de timestamp: 1788198706858_nome.pdf
  return raw.replace(/^\d{10,}_/, '') || fallback
}

/**
 * Gera uma URL assinada temporária. Retorna `null` se o usuário não tiver
 * permissão ou o arquivo não existir.
 *
 * @param {string} bucket
 * @param {string} urlOrPath  path no bucket ou URL antiga salva no banco
 * @param {{ expiresIn?: number, download?: boolean|string }} options
 */
export async function getSignedUrl(bucket, urlOrPath, options = {}) {
  if (!supabase || !urlOrPath) return null

  // buckets públicos não precisam de assinatura
  if (PUBLIC_BUCKETS.has(bucket)) {
    const path = storagePath(urlOrPath, bucket)
    if (!path) return String(urlOrPath)
    return supabase.storage.from(bucket).getPublicUrl(path).data.publicUrl
  }

  const path = storagePath(urlOrPath, bucket)
  if (!path) {
    console.warn('[storage] caminho inválido para o bucket', bucket, urlOrPath)
    return null
  }

  const { expiresIn = DEFAULT_EXPIRES_IN, download } = options
  const signOptions = download
    ? { download: typeof download === 'string' ? download : fileNameFrom(path) }
    : undefined

  const { data, error } = await supabase.storage
    .from(bucket)
    .createSignedUrl(path, expiresIn, signOptions)

  if (error) {
    console.error('[storage] falha ao assinar URL:', error.message, { bucket, path })
    return null
  }
  return data?.signedUrl ?? null
}

/** Abre o arquivo numa nova aba (visualizar). */
export async function openFile(bucket, urlOrPath) {
  const url = await getSignedUrl(bucket, urlOrPath)
  if (!url) return false
  window.open(url, '_blank', 'noopener,noreferrer')
  return true
}

/** Força o download do arquivo com o nome original. */
export async function downloadFile(bucket, urlOrPath, filename) {
  const url = await getSignedUrl(bucket, urlOrPath, {
    download: filename || fileNameFrom(urlOrPath),
  })
  if (!url) return false
  window.location.assign(url)
  return true
}

const IMAGE_RE = /\.(png|jpe?g|gif|webp|svg|avif)$/i
const PDF_RE = /\.pdf$/i

export function isImagePath(urlOrPath) {
  const path = storagePath(urlOrPath)
  return Boolean(path && IMAGE_RE.test(path))
}

export function isPdfPath(urlOrPath) {
  const path = storagePath(urlOrPath)
  return Boolean(path && PDF_RE.test(path))
}
