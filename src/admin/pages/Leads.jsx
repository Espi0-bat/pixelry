import { useEffect, useState } from 'react'
import { UserPlus } from 'lucide-react'
import { supabase } from '../../config/supabase'
import './Leads.css'

function formatDate(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  })
}

export default function Leads() {
  const [leads, setLeads] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase
      .from('leads')
      .select('*')
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setLeads(data || [])
        setLoading(false)
      })
  }, [])

  return (
    <div className="leads-container">
      <div className="leads-header">
        <div>
          <h1 className="leads-title">Leads</h1>
          <p className="leads-sub">Contatos captados pelo diagnóstico do site.</p>
        </div>
        {!loading && (
          <div className="leads-count-badge">
            {leads.length} lead{leads.length !== 1 ? 's' : ''}
          </div>
        )}
      </div>

      <div className="leads-table-wrap">
        <table className="leads-table">
          <thead>
            <tr>
              <th>Nome</th>
              <th>E-mail</th>
              <th>Segmento</th>
              <th>Faturamento</th>
              <th>Investimento</th>
              <th>WhatsApp</th>
              <th>Instagram</th>
              <th>Data</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              Array.from({ length: 5 }).map((_, i) => (
                <tr key={i} className="skeleton-row">
                  <td><div className="skeleton skeleton-medium" /></td>
                  <td><div className="skeleton skeleton-long" /></td>
                  <td><div className="skeleton skeleton-short" /></td>
                  <td><div className="skeleton skeleton-medium" /></td>
                  <td><div className="skeleton skeleton-medium" /></td>
                  <td><div className="skeleton skeleton-short" /></td>
                  <td><div className="skeleton skeleton-short" /></td>
                  <td><div className="skeleton skeleton-medium" /></td>
                </tr>
              ))
            ) : leads.length === 0 ? (
              <tr>
                <td colSpan={8}>
                  <div className="leads-empty">
                    <UserPlus size={36} className="leads-empty-icon" />
                    <span>Nenhum lead captado ainda.</span>
                    <span style={{ fontSize: '0.8rem' }}>Os leads aparecerão aqui quando alguém preencher o formulário do site.</span>
                  </div>
                </td>
              </tr>
            ) : leads.map(lead => (
              <tr key={lead.id}>
                <td className="leads-name">{lead.name}</td>
                <td className="leads-email">{lead.email}</td>
                <td>
                  {lead.clinic_type
                    ? <span className="leads-chip">{lead.clinic_type}</span>
                    : <span className="leads-muted">—</span>}
                </td>
                <td className={lead.revenue_range ? '' : 'leads-muted'}>{lead.revenue_range || '—'}</td>
                <td className={lead.investment_range ? '' : 'leads-muted'}>{lead.investment_range || '—'}</td>
                <td className={lead.whatsapp ? '' : 'leads-muted'}>{lead.whatsapp || '—'}</td>
                <td className={lead.instagram ? '' : 'leads-muted'}>{lead.instagram || '—'}</td>
                <td className="leads-date">{formatDate(lead.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
