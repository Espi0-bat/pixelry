import { useEffect, useMemo, useState } from 'react'
import { UserPlus, X } from 'lucide-react'
import { supabase } from '../../config/supabase'
import { parseSource, ranking } from '../utils/leadSource'
import './Leads.css'

function formatDate(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleDateString('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  })
}

/** Lista ordenada de origens, com barra proporcional. Clicar filtra a tabela. */
function Ranking({ titulo, nota, itens, campo, filtro, onFiltrar }) {
  const maior = itens[0]?.quantidade || 1
  return (
    <div className="leads-rank">
      <div className="leads-rank-head">
        <h2>{titulo}</h2>
        <span>{nota}</span>
      </div>
      {itens.length === 0 ? (
        <p className="leads-rank-vazio">Ainda sem dados.</p>
      ) : itens.map(item => {
        const ativo = filtro?.campo === campo && filtro.valor === item.valor
        return (
          <button
            type="button"
            key={item.valor}
            className={`leads-rank-item${ativo ? ' is-active' : ''}`}
            onClick={() => onFiltrar(ativo ? null : { campo, valor: item.valor })}
            aria-pressed={ativo}
          >
            <span className="leads-rank-label">{item.valor}</span>
            <span className="leads-rank-bar" aria-hidden="true">
              <span style={{ width: `${(item.quantidade / maior) * 100}%` }} />
            </span>
            <span className="leads-rank-num">{item.quantidade} · {item.porcentagem}%</span>
          </button>
        )
      })}
    </div>
  )
}

export default function Leads() {
  const [leads, setLeads] = useState([])
  const [loading, setLoading] = useState(true)
  const [filtro, setFiltro] = useState(null)

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

  const porDesafio = useMemo(() => ranking(leads, 'desafio'), [leads])
  const porLugar = useMemo(() => ranking(leads, 'lugar'), [leads])

  const visiveis = useMemo(() => {
    if (!filtro) return leads
    return leads.filter(lead => parseSource(lead.source)[filtro.campo] === filtro.valor)
  }, [leads, filtro])

  return (
    <div className="leads-container">
      <div className="leads-header">
        <div>
          <h1 className="leads-title">Leads</h1>
          <p className="leads-sub">Contatos captados pelo diagnóstico do site e pela LP de clínicas.</p>
        </div>
        {!loading && (
          <div className="leads-count-badge">
            {leads.length} lead{leads.length !== 1 ? 's' : ''}
          </div>
        )}
      </div>

      {!loading && leads.length > 0 && (
        <div className="leads-ranks">
          <Ranking
            titulo="Qual desafio trouxe o lead"
            nota="a dor escolhida na LP"
            itens={porDesafio}
            campo="desafio"
            filtro={filtro}
            onFiltrar={setFiltro}
          />
          <Ranking
            titulo="De onde na página ele saiu"
            nota="o botão que abriu o formulário"
            itens={porLugar}
            campo="lugar"
            filtro={filtro}
            onFiltrar={setFiltro}
          />
          {/* Sem isso o painel vira uma medição de cliques que ele não é. */}
          <p className="leads-ranks-nota">
            Conta cadastro enviado, não clique: quem abriu o formulário e desistiu não entra nestes números.
          </p>
        </div>
      )}

      {filtro && (
        <button type="button" className="leads-filtro" onClick={() => setFiltro(null)} aria-label={`Limpar filtro: ${filtro.valor}`}>
          {visiveis.length} de {leads.length} · {filtro.valor}
          <X size={14} aria-hidden="true" />
        </button>
      )}

      <div className="leads-table-wrap">
        <table className="leads-table">
          <thead>
            <tr>
              <th>Nome</th>
              <th>E-mail</th>
              <th>Origem</th>
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
                  <td><div className="skeleton skeleton-long" /></td>
                  <td><div className="skeleton skeleton-short" /></td>
                  <td><div className="skeleton skeleton-medium" /></td>
                  <td><div className="skeleton skeleton-medium" /></td>
                  <td><div className="skeleton skeleton-short" /></td>
                  <td><div className="skeleton skeleton-short" /></td>
                  <td><div className="skeleton skeleton-medium" /></td>
                </tr>
              ))
            ) : visiveis.length === 0 ? (
              <tr>
                <td colSpan={9}>
                  <div className="leads-empty">
                    <UserPlus size={36} className="leads-empty-icon" />
                    <span>{filtro ? 'Nenhum lead com esse filtro.' : 'Nenhum lead captado ainda.'}</span>
                    <span style={{ fontSize: '0.8rem' }}>
                      {filtro
                        ? 'Limpe o filtro acima para ver todos os contatos.'
                        : 'Os leads aparecerão aqui quando alguém preencher o formulário do site.'}
                    </span>
                  </div>
                </td>
              </tr>
            ) : visiveis.map(lead => {
              const origem = parseSource(lead.source)
              return (
                <tr key={lead.id}>
                  <td className="leads-name">{lead.name}</td>
                  <td className="leads-email">{lead.email}</td>
                  <td className="leads-origem">
                    <span className="leads-chip" title={origem.raw || 'sem source'}>{origem.canal}</span>
                    <span className="leads-origem-lugar">{origem.lugar}</span>
                    {origem.desafio !== '—' && <span className="leads-origem-desafio">{origem.desafio}</span>}
                  </td>
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
              )
            })}
          </tbody>
        </table>
      </div>
    </div>
  )
}
