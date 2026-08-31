import { useRef, useState } from 'react'
import { ArrowLeft, ArrowRight, MailCheck, AlertCircle } from 'lucide-react'
import { useResetRequest } from '../hooks/usePasswordRecovery'
import styles from './ForgotPassword.module.css'

/**
 * Painel "esqueci a senha" — usado dentro do LoginModal (cliente) e do
 * AdminLogin (equipe). Não confirma se o e-mail existe (evita enumeração).
 */
export default function ForgotPassword({ defaultEmail = '', onBack }) {
  const { send, status, error, reset } = useResetRequest()
  const [email, setEmail] = useState(defaultEmail)
  const emailRef = useRef(null)

  const sent = status === 'sent'

  async function handleSubmit(e) {
    e.preventDefault()
    if (!email.trim()) { emailRef.current?.focus(); return }
    await send(email)
  }

  if (sent) {
    return (
      <div className={styles.wrap}>
        <div className={styles.okIcon}><MailCheck size={24} aria-hidden="true" /></div>
        <h2 className={styles.title}>Verifique seu e-mail</h2>
        <p className={styles.text}>
          Se existir uma conta para <strong>{email.trim()}</strong>, enviamos um link para
          redefinir a senha. O link vale por 1 hora — confira também o spam.
        </p>
        <button type="button" className={styles.backBtn} onClick={onBack}>
          <ArrowLeft size={15} aria-hidden="true" /> Voltar ao login
        </button>
        <button
          type="button"
          className={styles.resend}
          onClick={() => { reset(); }}
        >
          Não recebi — tentar outro e-mail
        </button>
      </div>
    )
  }

  return (
    <div className={styles.wrap}>
      <h2 className={styles.title}>Recuperar acesso</h2>
      <p className={styles.text}>
        Informe o e-mail da sua conta. Enviaremos um link para você criar uma nova senha.
      </p>

      <form className={styles.form} onSubmit={handleSubmit} noValidate>
        {status === 'error' && error && (
          <div className={styles.err} role="alert">
            <AlertCircle size={15} aria-hidden="true" /> <span>{error}</span>
          </div>
        )}

        <div className={styles.group}>
          <label className={styles.label} htmlFor="fp-email">E-mail</label>
          <input
            id="fp-email"
            ref={emailRef}
            type="email"
            className={styles.input}
            placeholder="seu@email.com"
            value={email}
            autoComplete="email"
            autoFocus
            onChange={(e) => setEmail(e.target.value)}
            required
          />
        </div>

        <button type="submit" className={styles.submit} disabled={status === 'sending'}>
          {status === 'sending' ? 'Enviando…' : <>Enviar link <ArrowRight size={16} aria-hidden="true" /></>}
        </button>
      </form>

      <button type="button" className={styles.backLink} onClick={onBack}>
        <ArrowLeft size={14} aria-hidden="true" /> Voltar ao login
      </button>
    </div>
  )
}
