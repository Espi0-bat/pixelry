import { useState } from 'react'
import { supabase } from '../config/supabase'
import styles from './LeadCaptureModal.module.css'

const CLINIC_TYPES = [
  'Clínica Médica',
  'Odontologia',
  'Estética Avançada',
  'Fisioterapia',
  'Dermatologia',
  'Psicologia / Terapia',
  'Profissional Liberal',
  'Outro',
]

const REVENUE_RANGES = [
  'Até R$ 20 mil',
  'R$ 20 mil a R$ 50 mil',
  'R$ 50 mil a R$ 100 mil',
  'R$ 100 mil a R$ 200 mil',
  'Acima de R$ 200 mil',
  'Prefiro não informar',
]

const INVESTMENT_RANGES = [
  'Ainda estou avaliando',
  'Até R$ 1 mil',
  'R$ 1 mil a R$ 3 mil',
  'R$ 3 mil a R$ 5 mil',
  'Acima de R$ 5 mil',
]

const EMPTY_FORM = {
  name: '', email: '', whatsapp: '', instagram: '',
  clinicType: '', revenueRange: '', investmentRange: '',
}

function buildQualifiedLink(baseLink, form) {
  const extras = [
    form.clinicType && `Segmento: ${form.clinicType}`,
    form.revenueRange && `Faturamento: ${form.revenueRange}`,
    form.investmentRange && `Investimento: ${form.investmentRange}`,
  ].filter(Boolean)

  if (!extras.length) return baseLink

  const [url, query] = baseLink.split('?text=')
  if (!query) return baseLink
  const message = decodeURIComponent(query)
  return `${url}?text=${encodeURIComponent(`${message}\n\n${extras.join('\n')}`)}`
}

export default function LeadCaptureModal({ isOpen, onClose, waLink, source = 'diagnostico_hero' }) {
  const [form, setForm] = useState(EMPTY_FORM)
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
      clinic_type: form.clinicType || null,
      revenue_range: form.revenueRange || null,
      investment_range: form.investmentRange || null,
      source,
    })
    setLoading(false)
    window.open(buildQualifiedLink(waLink, form), '_blank', 'noreferrer')
    setForm(EMPTY_FORM)
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

          <div className={styles.field}>
            <label className={styles.label} htmlFor="lead-clinic-type">
              Segmento
              <span className={styles.labelOptional}>(opcional)</span>
            </label>
            <select
              id="lead-clinic-type"
              className={styles.select}
              name="clinicType"
              value={form.clinicType}
              onChange={handleChange}
            >
              <option value="">Selecione o segmento</option>
              {CLINIC_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
            </select>
          </div>

          <div className={styles.field}>
            <label className={styles.label} htmlFor="lead-revenue">
              Faturamento mensal
              <span className={styles.labelOptional}>(opcional)</span>
            </label>
            <select
              id="lead-revenue"
              className={styles.select}
              name="revenueRange"
              value={form.revenueRange}
              onChange={handleChange}
            >
              <option value="">Selecione a faixa</option>
              {REVENUE_RANGES.map(r => <option key={r} value={r}>{r}</option>)}
            </select>
          </div>

          <div className={styles.field}>
            <label className={styles.label} htmlFor="lead-investment">
              Investimento mensal previsto
              <span className={styles.labelOptional}>(opcional)</span>
            </label>
            <select
              id="lead-investment"
              className={styles.select}
              name="investmentRange"
              value={form.investmentRange}
              onChange={handleChange}
            >
              <option value="">Selecione a faixa</option>
              {INVESTMENT_RANGES.map(i => <option key={i} value={i}>{i}</option>)}
            </select>
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
