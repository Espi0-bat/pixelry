import { useState } from 'react'
import { supabase } from '../config/supabase'
import styles from './LeadCaptureModal.module.css'

export default function LeadCaptureModal({ isOpen, onClose, waLink, source = 'diagnostico_hero' }) {
  const [form, setForm] = useState({ name: '', email: '', whatsapp: '', instagram: '' })
  const [loading, setLoading] = useState(false)

  if (!isOpen) return null

  function handleChange(e) {
    setForm(f => ({ ...f, [e.target.name]: e.target.value }))
  }

  async function handleSubmit(e) {
    e.preventDefault()
    if (!form.name.trim() || !form.email.trim()) return
    setLoading(true)
    await supabase.from('leads').insert({
      name: form.name.trim(),
      email: form.email.trim(),
      whatsapp: form.whatsapp.trim() || null,
      instagram: form.instagram.trim() || null,
      source,
    })
    setLoading(false)
    window.open(waLink, '_blank', 'noreferrer')
    setForm({ name: '', email: '', whatsapp: '', instagram: '' })
    onClose()
  }

  return (
    <div className={styles.overlay} role="dialog" aria-modal="true" aria-labelledby="lead-modal-title" onClick={e => e.target === e.currentTarget && onClose()}>
      <div className={styles.modal}>
        <button className={styles.closeBtn} onClick={onClose} aria-label="Fechar">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M12 4L4 12M4 4l8 8" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" fill="none"/></svg>
        </button>

        <div className={styles.header}>
          <p className={styles.eyebrow}>Diagnóstico Gratuito</p>
          <h2 className={styles.title} id="lead-modal-title">Antes de falar com a gente,<br />nos conta um pouco sobre você.</h2>
          <p className={styles.subtitle}>Leva menos de 1 minuto. Usamos para entender sua clínica antes da conversa.</p>
        </div>

        <form className={styles.form} onSubmit={handleSubmit}>
          <div className={styles.field}>
            <label className={styles.label} htmlFor="lead-name">Nome</label>
            <input
              id="lead-name"
              className={styles.input}
              type="text"
              name="name"
              placeholder="Seu nome completo"
              value={form.name}
              onChange={handleChange}
              required
              autoFocus
            />
          </div>

          <div className={styles.field}>
            <label className={styles.label} htmlFor="lead-email">E-mail</label>
            <input
              id="lead-email"
              className={styles.input}
              type="email"
              name="email"
              placeholder="seu@email.com"
              value={form.email}
              onChange={handleChange}
              required
            />
          </div>

          <div className={styles.field}>
            <label className={styles.label} htmlFor="lead-whatsapp">
              WhatsApp
              <span className={styles.labelOptional}>(opcional)</span>
            </label>
            <input
              id="lead-whatsapp"
              className={styles.input}
              type="tel"
              name="whatsapp"
              placeholder="(61) 99999-9999"
              value={form.whatsapp}
              onChange={handleChange}
            />
          </div>

          <div className={styles.field}>
            <label className={styles.label} htmlFor="lead-instagram">
              Instagram da Clínica
              <span className={styles.labelOptional}>(opcional)</span>
            </label>
            <input
              id="lead-instagram"
              className={styles.input}
              type="text"
              name="instagram"
              placeholder="@clinicaexemplo"
              value={form.instagram}
              onChange={handleChange}
            />
          </div>

          <button
            type="submit"
            className={styles.submitBtn}
            disabled={loading || !form.name.trim() || !form.email.trim()}
          >
            {loading
              ? <><div className={styles.spinner} /> Enviando...</>
              : 'Continuar para o WhatsApp →'
            }
          </button>
        </form>

        <p className={styles.note}>Nenhum spam. Seus dados são usados apenas pela equipe Pixelry.</p>
      </div>
    </div>
  )
}
