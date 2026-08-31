import { useEffect, useRef, useState } from 'react'
import { X, CheckCircle2, AlertCircle } from 'lucide-react'
import PasswordInput from './PasswordInput'
import { useUpdatePassword, checkPasswordStrength } from '../hooks/usePasswordRecovery'
import styles from './ChangePassword.module.css'

/** Modal para trocar a senha estando logado (admin ou cliente). */
export default function ChangePassword({ onClose }) {
  const { update, status, error } = useUpdatePassword()
  const [pw, setPw] = useState('')
  const [confirm, setConfirm] = useState('')
  const [submitted, setSubmitted] = useState(false)
  const firstRef = useRef(null)

  const strength = checkPasswordStrength(pw)
  const mismatch = confirm.length > 0 && confirm !== pw
  const pwErr = submitted && !strength.ok ? 'Use pelo menos 8 caracteres, com letras e números.' : ''
  const confirmErr = submitted && mismatch ? 'As senhas não coincidem.' : ''

  useEffect(() => { firstRef.current?.focus() }, [])
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose?.() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  useEffect(() => {
    if (status === 'done') {
      const t = setTimeout(() => onClose?.(), 1400)
      return () => clearTimeout(t)
    }
  }, [status, onClose])

  async function handleSubmit(e) {
    e.preventDefault()
    setSubmitted(true)
    if (!strength.ok || mismatch) return
    await update(pw)
  }

  const done = status === 'done'

  return (
    <div className={styles.overlay} onClick={onClose}>
      <div
        className={styles.card}
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="cp-title"
      >
        <button className={styles.close} onClick={onClose} aria-label="Fechar"><X size={16} /></button>

        {done ? (
          <div className={styles.doneState}>
            <div className={styles.doneIcon}><CheckCircle2 size={24} aria-hidden="true" /></div>
            <h2 className={styles.title} id="cp-title">Senha alterada</h2>
          </div>
        ) : (
          <>
            <h2 className={styles.title} id="cp-title">Alterar senha</h2>
            <form className={styles.form} onSubmit={handleSubmit} noValidate>
              {(error && submitted) && (
                <div className={styles.err} role="alert">
                  <AlertCircle size={15} aria-hidden="true" /> <span>{error}</span>
                </div>
              )}

              <div className={styles.group}>
                <label className={styles.label} htmlFor="cp-new">Nova senha</label>
                <PasswordInput
                  id="cp-new"
                  ref={firstRef}
                  className={styles.input}
                  autoComplete="new-password"
                  value={pw}
                  placeholder="Mínimo 8 caracteres"
                  onChange={(e) => setPw(e.target.value)}
                  aria-invalid={Boolean(pwErr)}
                  aria-describedby="cp-new-err"
                />
                {pwErr && <p className={styles.error} id="cp-new-err">{pwErr}</p>}
              </div>

              <div className={styles.group}>
                <label className={styles.label} htmlFor="cp-confirm">Confirmar</label>
                <PasswordInput
                  id="cp-confirm"
                  className={styles.input}
                  autoComplete="new-password"
                  value={confirm}
                  placeholder="Repita a senha"
                  onChange={(e) => setConfirm(e.target.value)}
                  aria-invalid={Boolean(confirmErr)}
                  aria-describedby="cp-confirm-err"
                />
                {confirmErr && <p className={styles.error} id="cp-confirm-err">{confirmErr}</p>}
              </div>

              <button type="submit" className={styles.submit} disabled={status === 'saving'}>
                {status === 'saving' ? 'Salvando…' : 'Salvar'}
              </button>
            </form>
          </>
        )}
      </div>
    </div>
  )
}
