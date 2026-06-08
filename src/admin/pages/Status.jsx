import { useState, useEffect } from 'react';
import {
  CheckCircle2, XCircle, Clock, Zap, MessageSquare,
  AlertTriangle, RefreshCw, Send, X
} from 'lucide-react';
import { supabase } from '../../config/supabase';
import './Status.css';

const statusMap = {
  pending:    { label: 'Aguardando Revisão', color: '#f59e0b', bg: 'rgba(245,158,11,0.1)',  border: 'rgba(245,158,11,0.3)',  icon: Clock },
  approved:   { label: 'Aprovado',           color: '#10b981', bg: 'rgba(16,185,129,0.1)',  border: 'rgba(16,185,129,0.3)',  icon: CheckCircle2 },
  revision:   { label: 'Ajuste Solicitado',  color: '#f43f5e', bg: 'rgba(244,63,94,0.1)',   border: 'rgba(244,63,94,0.3)',   icon: XCircle },
  production: { label: 'Em Produção',        color: '#00D8FF', bg: 'rgba(0,216,255,0.1)',   border: 'rgba(0,216,255,0.3)',  icon: Zap },
};

function formatDate(iso) {
  if (!iso) return '';
  return new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }).replace('.', '');
}

export default function Status() {
  const [deliveries, setDeliveries]       = useState([]);
  const [filterStatus, setFilterStatus]   = useState('all');
  const [replyModal, setReplyModal]       = useState(null);
  const [replyText, setReplyText]         = useState('');
  const [confirmModal, setConfirmModal]   = useState(null);
  const [loading, setLoading]             = useState(true);
  const [sendingReply, setSendingReply]   = useState(false);
  const [updatingId, setUpdatingId]       = useState(null);

  useEffect(() => {
    async function load() {
      // Query principal limpa — sem JOIN pesado de messages
      const { data } = await supabase
        .from('deliveries')
        .select('id, title, type, status, updated_at, client_id, profiles!deliveries_client_id_profiles_fkey(full_name, company_name)')
        .order('updated_at', { ascending: false });

      const deliveriesRaw = data || [];

      // Busca separada: só a última mensagem do cliente para entregas em revisão
      const revisionClientIds = deliveriesRaw
        .filter(d => d.status === 'revision')
        .map(d => d.client_id);

      let clientNoteMap = {};
      if (revisionClientIds.length > 0) {
        const { data: msgs } = await supabase
          .from('messages')
          .select('client_id, content, created_at')
          .eq('from_client', true)
          .in('client_id', revisionClientIds)
          .order('created_at', { ascending: false });

        // Mapeia client_id -> última mensagem (primeira do resultado, já ordenado desc)
        for (const m of (msgs || [])) {
          if (!clientNoteMap[m.client_id]) {
            clientNoteMap[m.client_id] = m.content;
          }
        }
      }

      setDeliveries(deliveriesRaw.map(d => ({
        ...d,
        clientName: d.profiles?.company_name || d.profiles?.full_name || '—',
        updatedAt: formatDate(d.updated_at),
        clientNote: d.status === 'revision' ? (clientNoteMap[d.client_id] ?? null) : null,
      })));
      setLoading(false);
    }
    load();

    // Realtime: atualiza quando cliente age no portal
    const channel = supabase
      .channel('admin:status:deliveries')
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'deliveries' },
        (payload) => {
          setDeliveries(prev => prev.map(d =>
            d.id === payload.new.id
              ? {
                  ...d,
                  ...payload.new,
                  clientName: d.clientName,
                  updatedAt: formatDate(payload.new.updated_at),
                  clientNote: payload.new.status === 'revision' ? d.clientNote : null,
                }
              : d
          ));
        }
      )
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, []);

  const updateStatus = async (id, nextStatus) => {
    setUpdatingId(id);
    const { error } = await supabase
      .from('deliveries')
      .update({ status: nextStatus, updated_at: new Date().toISOString() })
      .eq('id', id);

    if (!error) {
      setDeliveries(prev => prev.map(d =>
        d.id === id ? { ...d, status: nextStatus, clientNote: null, updatedAt: formatDate(new Date().toISOString()) } : d
      ));
    }
    setConfirmModal(null);
    setUpdatingId(null);
  };

  const handleSendReply = async () => {
    if (!replyText.trim() || !replyModal?.client_id) return;
    setSendingReply(true);
    await supabase.from('messages').insert({
      client_id: replyModal.client_id,
      content: replyText.trim(),
      from_client: false,
    });
    setReplyModal(null);
    setReplyText('');
    setSendingReply(false);
  };

  const filtered = filterStatus === 'all'
    ? deliveries
    : deliveries.filter(d => d.status === filterStatus);

  const revisionCount = deliveries.filter(d => d.status === 'revision').length;
  const pendingCount  = deliveries.filter(d => d.status === 'pending').length;
  const approvedCount = deliveries.filter(d => d.status === 'approved').length;

  return (
    <div className="status-container">
      <div className="status-header">
        <h1>Sincronização de Status</h1>
        <p>Monitore o feedback dos clientes e atualize o status das entregas.</p>
      </div>

      <div className="summary-cards">
        {[
          { label: 'Ajustes Solicitados', count: revisionCount, color: '#f43f5e', bg: 'rgba(244,63,94,0.1)',   border: 'rgba(244,63,94,0.25)',   icon: XCircle,       filterVal: 'revision' },
          { label: 'Aguardando Revisão',  count: pendingCount,  color: '#f59e0b', bg: 'rgba(245,158,11,0.1)',  border: 'rgba(245,158,11,0.25)',  icon: AlertTriangle, filterVal: 'pending'  },
          { label: 'Aprovados',           count: approvedCount, color: '#10b981', bg: 'rgba(16,185,129,0.1)',  border: 'rgba(16,185,129,0.25)',  icon: CheckCircle2,  filterVal: 'approved' },
        ].map(card => {
          const Icon = card.icon;
          return (
            <div
              key={card.label}
              onClick={() => setFilterStatus(prev => prev === card.filterVal ? 'all' : card.filterVal)}
              className="summary-card"
              style={{
                background: filterStatus === card.filterVal ? card.bg : '',
                borderColor: filterStatus === card.filterVal ? card.border : '',
                boxShadow: filterStatus === card.filterVal ? `0 4px 20px ${card.bg}` : '',
              }}
            >
              <div className="summary-card-inner">
                <div>
                  <div className="summary-label">{card.label}</div>
                  <div className="summary-value" style={{ color: card.color }}>
                    {loading ? '—' : card.count}
                  </div>
                </div>
                <div className="summary-icon" style={{ background: card.bg }}>
                  <Icon size={24} color={card.color} strokeWidth={1.5} />
                </div>
              </div>
            </div>
          );
        })}
      </div>

      <div className="status-tabs">
        {[
          { val: 'all',        label: 'Todas' },
          { val: 'revision',   label: 'Ajuste Solicitado' },
          { val: 'pending',    label: 'Aguardando Revisão' },
          { val: 'approved',   label: 'Aprovado' },
          { val: 'production', label: 'Em Produção' },
        ].map(f => (
          <button key={f.val} onClick={() => setFilterStatus(f.val)}
            className={`status-tab ${filterStatus === f.val ? 'active' : ''}`}>
            {f.label}
          </button>
        ))}
      </div>

      <div className="status-list">
        {loading && <div style={{ color: 'var(--text-secondary)', fontSize: 13, padding: '12px 0' }}>Carregando...</div>}
        {filtered.map((d, i) => {
          const s = statusMap[d.status] || statusMap.production;
          const SIcon = s.icon;
          const isUpdating = updatingId === d.id;
          return (
            <div key={d.id} className="status-item animate-in"
              style={{ borderColor: d.status === 'revision' ? 'rgba(244,63,94,0.3)' : '', animationDelay: `${i * 0.05}s` }}>
              <div className="status-item-content">
                <div className="status-icon" style={{ background: s.bg }}>
                  <SIcon size={24} color={s.color} strokeWidth={1.5} />
                </div>

                <div className="status-info">
                  <div className="status-title-row">
                    <span className="status-title">{d.title}</span>
                    <span className="status-badge" style={{ background: s.bg, border: `1px solid ${s.border}`, color: s.color }}>
                      {s.label}
                    </span>
                  </div>
                  <div className="status-meta" style={{ marginBottom: d.clientNote ? 16 : 0 }}>
                    {d.clientName} · {d.type} · Atualizado em {d.updatedAt}
                  </div>

                  {d.clientNote && (
                    <div className="client-feedback">
                      <div className="feedback-header">
                        <MessageSquare size={14} color="#f43f5e" />
                        <span className="feedback-title">Feedback do Cliente</span>
                      </div>
                      <p className="feedback-text">{d.clientNote}</p>
                    </div>
                  )}
                </div>

                <div className="status-actions">
                  <button className="btn-action btn-reply" onClick={() => setReplyModal(d)} disabled={isUpdating}>
                    <MessageSquare size={16} /> Responder
                  </button>

                  {d.status === 'revision' && (
                    <button className="btn-action btn-mark-fixed" disabled={isUpdating}
                      onClick={() => setConfirmModal({
                        id: d.id, title: d.title, nextStatus: 'pending',
                        label: 'Marcar como Ajustado',
                        color: '#f59e0b',
                        description: 'O arquivo foi corrigido e será enviado novamente ao cliente para revisão.',
                      })}>
                      <RefreshCw size={16} /> {isUpdating ? 'Atualizando...' : 'Ajustado'}
                    </button>
                  )}

                  {d.status === 'production' && (
                    <button className="btn-action btn-send-review" disabled={isUpdating}
                      onClick={() => setConfirmModal({
                        id: d.id, title: d.title, nextStatus: 'pending',
                        label: 'Enviar para Revisão',
                        color: '#00D8FF',
                        description: 'O arquivo será disponibilizado no portal do cliente para revisão e aprovação.',
                      })}>
                      <Send size={16} /> {isUpdating ? 'Atualizando...' : 'Enviar'}
                    </button>
                  )}

                  {d.status === 'approved' && (
                    <div className="badge-finished">
                      <CheckCircle2 size={16} /> Finalizado
                    </div>
                  )}
                </div>
              </div>
            </div>
          );
        })}
        {!loading && filtered.length === 0 && (
          <div className="empty-status animate-in">Nenhuma entrega encontrada para este filtro.</div>
        )}
      </div>

      {replyModal && (
        <div className="modal-overlay" onClick={() => setReplyModal(null)}>
          <div className="modal-content" onClick={e => e.stopPropagation()} style={{ maxWidth: 520 }}>
            <div className="modal-header">
              <div>
                <h2>Responder ao Cliente</h2>
                <p>{replyModal.title} · {replyModal.clientName}</p>
              </div>
              <button className="btn-close" onClick={() => setReplyModal(null)}><X size={15} /></button>
            </div>
            {replyModal.clientNote && (
              <div className="client-feedback" style={{ marginBottom: 24 }}>
                <div className="feedback-header"><span className="feedback-title">Feedback recebido</span></div>
                <p className="feedback-text">{replyModal.clientNote}</p>
              </div>
            )}
            <textarea
              placeholder="Escreva sua resposta para o cliente..."
              value={replyText}
              onChange={e => setReplyText(e.target.value)}
              rows={5} className="form-input" style={{ marginBottom: 24, resize: 'vertical' }}
            />
            <button className="btn-submit" onClick={handleSendReply} disabled={sendingReply || !replyText.trim()}
              style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
              <Send size={16} /> {sendingReply ? 'Enviando...' : 'Enviar Mensagem'}
            </button>
          </div>
        </div>
      )}

      {confirmModal && (
        <div className="modal-overlay" onClick={() => setConfirmModal(null)}>
          <div className="modal-content" onClick={e => e.stopPropagation()} style={{ maxWidth: 460 }}>
            <h2 style={{ marginBottom: 8 }}>{confirmModal.label}</h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: 14, marginBottom: 8 }}>
              <strong style={{ color: 'var(--text-primary)' }}>{confirmModal.title}</strong>
            </p>
            <p style={{ color: 'var(--text-secondary)', fontSize: 14, lineHeight: 1.6, marginBottom: 32 }}>
              {confirmModal.description}
            </p>
            <div className="confirm-modal-buttons">
              <button className="btn-cancel" onClick={() => setConfirmModal(null)}>Cancelar</button>
              <button className="btn-confirm" onClick={() => updateStatus(confirmModal.id, confirmModal.nextStatus)}>
                Confirmar
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
