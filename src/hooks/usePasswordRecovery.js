import { useCallback, useEffect, useState } from 'react'
import { supabase, isSupabaseConfigured } from '../config/supabase'
import { PASSWORD_RESET_REDIRECT } from '../config/appUrl'

const NOT_CONFIGURED = 'O portal ainda não está conectado ao Supabase neste deploy.'

/**
 * Detecta quando o usuário chegou por um link de recuperação de senha.
 * O supabase-js dispara o evento PASSWORD_RECOVERY ao processar o hash
 * (#access_token=…&type=recovery). Também checamos o hash na montagem,
 * caso o evento tenha disparado antes do listener existir.
 */
export function useRecoveryMode() {
  const [active, setActive] = useState(() => {
    if (typeof window === 'undefined') return false
    return window.location.hash.includes('type=recovery')
  })

  useEffect(() => {
    if (!isSupabaseConfigured || !supabase) return
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event) => {
      if (event === 'PASSWORD_RECOVERY') setActive(true)
    })
    return () => subscription.unsubscribe()
  }, [])

  const clear = useCallback(() => {
    setActive(false)
    // limpa o hash da URL para o link não reabrir a tela ao dar refresh
    if (typeof window !== 'undefined' && window.location.hash) {
      window.history.replaceState(null, '', window.location.pathname + window.location.search)
    }
  }, [])

  return { active, clear }
}

/** Envia o e-mail de recuperação. status: idle | sending | sent | error */
export function useResetRequest() {
  const [status, setStatus] = useState('idle')
  const [error, setError] = useState('')

  const send = useCallback(async (email) => {
    const clean = (email || '').trim()
    if (!clean) return
    if (!isSupabaseConfigured || !supabase) {
      setStatus('error'); setError(NOT_CONFIGURED); return
    }
    setStatus('sending'); setError('')
    const { error: err } = await supabase.auth.resetPasswordForEmail(clean, {
      redirectTo: PASSWORD_RESET_REDIRECT,
    })
    if (err) {
      // Não revela se o e-mail existe — mensagem neutra, exceto rate limit.
      if (/rate limit|too many/i.test(err.message)) {
        setStatus('error')
        setError('Muitas tentativas. Aguarde alguns minutos e tente de novo.')
      } else {
        setStatus('sent') // trata erro genérico como sucesso para não enumerar contas
      }
      return
    }
    setStatus('sent')
  }, [])

  const reset = useCallback(() => { setStatus('idle'); setError('') }, [])

  return { send, status, error, reset }
}

/** Define a nova senha (usuário já autenticado via link de recuperação ou logado). */
export function useUpdatePassword() {
  const [status, setStatus] = useState('idle') // idle | saving | done | error
  const [error, setError] = useState('')

  const update = useCallback(async (newPassword) => {
    if (!isSupabaseConfigured || !supabase) {
      setStatus('error'); setError(NOT_CONFIGURED); return false
    }
    setStatus('saving'); setError('')
    const { error: err } = await supabase.auth.updateUser({ password: newPassword })
    if (err) {
      setStatus('error')
      setError(
        /at least|weak|short/i.test(err.message)
          ? 'Senha muito fraca. Use pelo menos 8 caracteres, com letras e números.'
          : /same.*password|different from the old/i.test(err.message)
            ? 'A nova senha precisa ser diferente da atual.'
            : err.message || 'Não foi possível alterar a senha. Tente de novo.'
      )
      return false
    }
    setStatus('done')
    return true
  }, [])

  return { update, status, error }
}

/** Regras simples de força de senha, reaproveitadas nas telas. */
export function checkPasswordStrength(pw = '') {
  const checks = {
    length: pw.length >= 8,
    letter: /[a-zA-Z]/.test(pw),
    number: /[0-9]/.test(pw),
  }
  const score = Object.values(checks).filter(Boolean).length
  return { checks, score, ok: score === 3 }
}
