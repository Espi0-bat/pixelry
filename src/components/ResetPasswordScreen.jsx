import { useEffect, useRef, useState } from 'react'
import { CheckCircle2, ShieldCheck, ArrowRight, AlertCircle } from 'lucide-react'
import PasswordInput from './PasswordInput'
import { useUpdatePassword, checkPasswordStrength } from '../hooks/usePasswordRecovery'
import logoImg from './images/pixelryicone.jpeg'
import styles from './ResetPasswordScreen.module.css'

/**
 * Tela de definição de nova senha. Aparece por cima de qualquer rota quando
 * o usuário chega por um link de recuperação (evento PASSWORD_RECOVERY).
 * Serve tanto para admin quanto para cliente — o Supabase Auth é o mesmo.
 */
export default function ResetPasswordScreen({ onSuccess, onCancel }) {
  const { update, status, error } = useUpdatePassword()

  const [pw, setPw] = useState('')
  const [confirm, setConfirm] = useState('')
  const [touched, setTouched] = useState({ pw: false, confirm: false })
  const [submitted, setSubmitted] = useState(false)
  const summaryRef = useRef(null)

  const strength = checkPasswordStrength(pw)
  const mismatch = confirm.length > 0 && confirm !== pw

  const fieldErrors = {
    pw: !strength.ok ? 'Use pelo menos 8 caracteres, com letras e números.' : '',
    confirm: mismatch ? 'As senhas não coincidem.' : '',
  }
  const showPwErr = (touched.pw || submitted) && fieldErrors.pw
  const showConfirmErr = (touched.confirm || submitted) && fieldErrors.confirm
  const hasErrors = Boolean(fieldErrors.pw || fieldErrors.confirm)

  useEffect(() => {
    if (status === 'done') {
      const t = setTimeout(() => onSuccess?.(), 1400)
      return () => clearTimeout(t)
    }
  }, [status, onSuccess])

  async function handleSubmit(e) {
    e.preventDefault()
    setSubmitted(true)
    if (hasErrors) {
      summaryRef.current?.focus()
      return
    }
    await update(pw)
  }

  const done = status === 'done'

  return (
    <div className={styles.overlay} role="dialog" aria-modal="true" aria-labelledby="reset-title">
      <div className={styles.card}>
        <div className={styles.header}>
          <img src={logoImg} alt="" className={styles.logo} />
          {done ? (
            <>
              <div className={styles.successIcon}><CheckCircle2 size={26} aria-hidden="true" /></div>
              <h1 className={styles.title} id="reset-title">Senha alterada</h1>
              <p className={styles.subtitle}>Redirecionando para o seu acesso…</p>
            </>
          ) : (
            <>
              <div className={styles.badge}><ShieldCheck size={14} aria-hidden="true" /> Recuperação de senha</div>
              <h1 className={styles.title} id="reset-title">Defina sua nova senha</h1>
              <p className={styles.subtitle}>Escolha uma senha forte que você não use em outros sites.</p>
            </>
          )}
        </div>

        {!done && (
          <form className={styles.form} onSubmit={handleSubmit} noValidate>
            {/* Resumo de erros — foco movido para cá no submit inválido */}
            {(submitted && (hasErrors || error)) && (
              <div className={styles.summary} role="alert" tabIndex={-1} ref={summaryRef}>
                <AlertCircle size={16} aria-hidden="true" />
                <span>{error || 'Revise os campos destacados abaixo.'}</span>
              </div>
            )}

            <div className={styles.group}>
              <label className={styles.label} htmlFor="new-pw">Nova senha</label>
              <PasswordInput
                id="new-pw"
                className={styles.input}
                autoComplete="new-password"
                autoFocus
                value={pw}
                placeholder="Mínimo 8 caracteres"
                onChange={(e) => setPw(e.target.value)}
                onBlur={() => setTouched((t) => ({ ...t, pw: true }))}
                aria-invalid={Boolean(showPwErr)}
                aria-describedby="pw-hint pw-error"
              />
              <div className={styles.meter} id="pw-hint" aria-hidden="true">
                <span data-on={strength.checks.length}>8+ caracteres</span>
                <span data-on={strength.checks.letter}>letra</span>
                <span data-on={strength.checks.number}>número</span>
              </div>
              {showPwErr && <p className={styles.error} id="pw-error">{fieldErrors.pw}</p>}
            </div>

            <div className={styles.group}>
              <label className={styles.label} htmlFor="confirm-pw">Confirmar nova senha</label>
              <PasswordInput
                id="confirm-pw"
                className={styles.input}
                autoComplete="new-password"
                value={confirm}
                placeholder="Repita a senha"
                onChange={(e) => setConfirm(e.target.value)}
                onBlur={() => setTouched((t) => ({ ...t, confirm: true }))}
                aria-invalid={Boolean(showConfirmErr)}
                aria-describedby="confirm-error"
              />
              {showConfirmErr && <p className={styles.error} id="confirm-error">{fieldErrors.confirm}</p>}
            </div>

            <button type="submit" className={styles.submit} disabled={status === 'saving'}>
              {status === 'saving' ? 'Salvando…' : <>Salvar nova senha <ArrowRight size={17} aria-hidden="true" /></>}
            </button>

            {onCancel && (
              <button type="button" className={styles.cancel} onClick={onCancel}>
                Cancelar e voltar ao login
              </button>
            )}
          </form>
        )}
      </div>
    </div>
  )
}
