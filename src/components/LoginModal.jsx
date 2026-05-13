import { useState } from 'react'
import { CLIENT_WHATSAPP_NUMBER } from '../config/contact'
import { isSupabaseConfigured, supabase } from '../config/supabase'
import styles from './LoginModal.module.css'
import logoImg from './images/pixelryicone.jpeg'

export default function LoginModal({ isOpen, onClose, onLoginSuccess }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [errorMessage, setErrorMessage] = useState('')

  if (!isOpen) return null

  const handleSubmit = async (e) => {
    e.preventDefault()
    if (!email || !password) return

    if (!isSupabaseConfigured || !supabase) {
      setErrorMessage('O portal ainda não está conectado ao Supabase neste deploy.')
      return
    }

    setLoading(true)
    setErrorMessage('')

    const { data, error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password,
    })

    if (error) {
      setLoading(false)
      setErrorMessage('E-mail ou senha inválidos. Verifique os dados e tente novamente.')
      return
    }

    setLoading(false)
    setPassword('')
    onLoginSuccess(data.session, data.user)
  }

  return (
    <div className={styles.modalOverlay} onClick={onClose}>
      <div className={styles.modalContent} onClick={(e) => e.stopPropagation()}>
        <button className={styles.closeBtn} onClick={onClose} aria-label="Fechar">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
            <line x1="18" y1="6" x2="6" y2="18"></line>
            <line x1="6" y1="6" x2="18" y2="18"></line>
          </svg>
        </button>

        <div className={styles.logoArea}>
          <img src={logoImg} alt="Pixelry" className={styles.logo} />
          <h2 className={styles.title}>Área do Cliente</h2>
          <p className={styles.subtitle}>
            Acesse o portal exclusivo para acompanhar seus projetos e aprovar entregas.
          </p>
        </div>

        <form className={styles.form} onSubmit={handleSubmit}>
          <div className={styles.inputGroup}>
            <label className={styles.inputLabel}>E-mail Registrado</label>
            <div className={styles.inputWrapper}>
              <input
                type="email"
                className={styles.input}
                placeholder="seu@email.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>
          </div>

          <div className={styles.inputGroup}>
            <label className={styles.inputLabel}>Senha</label>
            <div className={styles.inputWrapper}>
              <input
                type="password"
                className={styles.input}
                placeholder="Sua senha"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                autoComplete="current-password"
                required
              />
            </div>
          </div>

          {errorMessage && (
            <p className={styles.errorText} role="alert">
              {errorMessage}
            </p>
          )}

          <button type="submit" className={styles.submitBtn} disabled={loading}>
            {loading ? (
              <span>Verificando...</span>
            ) : (
              <>
                <span>Acessar Portal</span>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                  <line x1="5" y1="12" x2="19" y2="12"></line>
                  <polyline points="12 5 19 12 12 19"></polyline>
                </svg>
              </>
            )}
          </button>
        </form>

        <p className={styles.footerText}>
          Ainda não é cliente? <a href={`https://wa.me/${CLIENT_WHATSAPP_NUMBER}`} target="_blank" rel="noreferrer">Fale conosco</a>
        </p>
      </div>
    </div>
  )
}
