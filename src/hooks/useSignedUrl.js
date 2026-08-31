import { useEffect, useState } from 'react'
import { getSignedUrl } from '../config/storage'

/**
 * Resolve a URL assinada de um arquivo para exibição (preview de imagem, PDF).
 * Retorna { url, loading, error }. Não dispara nada quando `urlOrPath` é nulo.
 */
export function useSignedUrl(bucket, urlOrPath, { enabled = true } = {}) {
  const [url, setUrl] = useState(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState(false)

  useEffect(() => {
    if (!enabled || !urlOrPath) {
      setUrl(null)
      setLoading(false)
      setError(false)
      return
    }

    let cancelled = false
    setLoading(true)
    setError(false)

    getSignedUrl(bucket, urlOrPath)
      .then((signed) => {
        if (cancelled) return
        setUrl(signed)
        setError(!signed)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })

    return () => { cancelled = true }
  }, [bucket, urlOrPath, enabled])

  return { url, loading, error }
}
