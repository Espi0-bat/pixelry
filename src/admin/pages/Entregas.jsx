import React, { useState, useCallback, useEffect } from 'react';
import {
  Upload, FileText, Palette, Film, BarChart2, X, Check,
  Plus, ChevronDown, Clock, CheckCircle2, XCircle, Zap, Image, Paperclip
} from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { supabase, STORAGE_BUCKET } from '../../config/supabase';
import './Entregas.css';

const DELIVERY_TYPES = ['Design', 'Vídeo', 'Documento', 'Relatório', 'Imagem'];
const DELIVERY_STATUSES = [
  { value: 'production', label: 'Em Produção',        color: '#00D8FF' },
  { value: 'pending',    label: 'Aguardando Revisão', color: '#f59e0b' },
  { value: 'approved',   label: 'Aprovado',           color: '#10b981' },
  { value: 'revision',   label: 'Ajuste Solicitado',  color: '#f43f5e' },
];

const statusMap = {
  pending:    { label: 'Aguardando Revisão', color: '#f59e0b', bg: 'rgba(245,158,11,0.1)', border: 'rgba(245,158,11,0.3)', icon: Clock },
  approved:   { label: 'Aprovado',           color: '#10b981', bg: 'rgba(16,185,129,0.1)', border: 'rgba(16,185,129,0.3)', icon: CheckCircle2 },
  revision:   { label: 'Ajuste Solicitado',  color: '#f43f5e', bg: 'rgba(244,63,94,0.1)',  border: 'rgba(244,63,94,0.3)',  icon: XCircle },
  production: { label: 'Em Produção',        color: '#00D8FF', bg: 'rgba(0,216,255,0.1)',  border: 'rgba(0,216,255,0.3)', icon: Zap },
};

function typeIcon(type) {
  const map = { Design: Palette, Vídeo: Film, Relatório: BarChart2, Imagem: Image, Documento: FileText };
  return map[type] || Paperclip;
}

function getFileIcon(name) {
  const ext = name.split('.').pop().toLowerCase();
  if (['jpg','jpeg','png','gif','webp','svg'].includes(ext)) return Image;
  if (ext === 'pdf') return FileText;
  if (['fig','psd','ai','sketch'].includes(ext)) return Palette;
  if (['mp4','mov','avi'].includes(ext)) return Film;
  return Paperclip;
}

async function getOrCreateProject(clientId) {
  const { data } = await supabase
    .from('projects')
    .select('id')
    .eq('client_id', clientId)
    .limit(1)
    .maybeSingle();
  if (data) return data.id;

  const { data: created } = await supabase
    .from('projects')
    .insert({ client_id: clientId, title: 'Projeto Principal' })
    .select('id')
    .single();
  return created?.id ?? null;
}

function formatDate(iso) {
  return new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' }).replace('.', '');
}

const DeliveryRow = React.memo(function DeliveryRow({ d, s, Icon, SIcon }) {
  const [hov, setHov] = useState(false);
  return (
    <motion.div
      className="delivery-item"
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -6 }}
      transition={{ delay: 0, duration: 0.18 }}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        background: hov ? `${s.color}0a` : undefined,
        borderColor: hov ? `${s.color}44` : undefined,
        boxShadow: hov ? `0 8px 32px ${s.color}1a` : 'none',
        transform: hov ? 'translateX(4px)' : 'none',
        transition: 'background 0.18s, border-color 0.18s, box-shadow 0.18s, transform 0.18s',
      }}
    >
      <div
        className="delivery-icon"
        style={{
          background: hov ? `${s.color}20` : undefined,
          color: hov ? s.color : undefined,
          transition: 'background 0.18s, color 0.18s',
        }}
      >
        <Icon size={20} strokeWidth={1.5} />
      </div>
      <div className="delivery-info">
        <div className="delivery-title">{d.title}</div>
        <div className="delivery-meta">{d.clientName} · {d.type} · {d.date}</div>
      </div>
      <div className="status-badge" style={{ background: s.bg, border: `1px solid ${s.border}`, color: s.color }}>
        <SIcon size={13} /> {s.label}
      </div>
    </motion.div>
  );
});

export default function Entregas() {
  const [showModal, setShowModal]     = useState(false);
  const [uploads, setUploads]         = useState([]);
  const [dragging, setDragging]       = useState(false);
  const [form, setForm]               = useState({ clientId: '', title: '', type: '', status: 'production', description: '' });
  const [deliveries, setDeliveries]   = useState([]);
  const [clients, setClients]         = useState([]);
  const [filterStatus, setFilterStatus] = useState('all');
  const [loading, setLoading]         = useState(true);
  const [submitting, setSubmitting]   = useState(false);
  const [submitError, setSubmitError] = useState(null);
  const [uploadedFile, setUploadedFile] = useState(null);

  const loadDeliveries = useCallback(async () => {
    const [{ data: profilesData }, { data: deliveriesData }] = await Promise.all([
      supabase.from('profiles').select('id, full_name, company_name, email').eq('role', 'client').order('full_name'),
      supabase
        .from('deliveries')
        .select('id, title, type, status, created_at, client_id, profiles!deliveries_client_id_profiles_fkey(full_name, company_name)')
        .order('created_at', { ascending: false }),
    ]);
    setClients(profilesData || []);
    setDeliveries((deliveriesData || []).map(d => ({
      ...d,
      clientName: d.profiles?.company_name || d.profiles?.full_name || '—',
      date: formatDate(d.created_at),
    })));
    setLoading(false);
  }, []);

  useEffect(() => {
    loadDeliveries();
  }, [loadDeliveries]);

  // Real-time: atualiza quando cliente aprova ou solicita ajuste
  useEffect(() => {
    if (!supabase) return;
    const channel = supabase
      .channel('admin:deliveries')
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'deliveries' },
        (payload) => {
          setDeliveries(prev => prev.map(d =>
            d.id === payload.new.id
              ? { ...d, ...payload.new, clientName: d.clientName, date: d.date }
              : d
          ));
        }
      )
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, []);

  const processFiles = useCallback((files) => {
    const file = files[0];
    if (!file) return;
    const entry = { id: Date.now(), name: file.name, size: (file.size / 1024 / 1024).toFixed(1) + ' MB', progress: 0, done: false, error: false, raw: file };
    setUploads([entry]);
    setUploadedFile(file);
  }, []);

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!form.clientId || !form.title) return;
    setSubmitting(true);
    setSubmitError(null);

    let fileUrl = null;

    if (uploadedFile) {
      let p = 0;
      const iv = setInterval(() => {
        p = Math.min(p + Math.random() * 18 + 8, 85);
        setUploads(prev => prev.map(u => ({ ...u, progress: Math.floor(p) })));
      }, 180);

      const path = `${form.clientId}/${Date.now()}_${uploadedFile.name}`;
      const { error: uploadError } = await supabase.storage
        .from(STORAGE_BUCKET)
        .upload(path, uploadedFile, { upsert: false });

      clearInterval(iv);

      if (uploadError) {
        setUploads(prev => prev.map(u => ({ ...u, progress: 0, error: true })));
        setSubmitError(`Erro no upload: ${uploadError.message}`);
        setSubmitting(false);
        return;
      }

      const { data: { publicUrl } } = supabase.storage.from(STORAGE_BUCKET).getPublicUrl(path);
      fileUrl = publicUrl;
      setUploads(prev => prev.map(u => ({ ...u, progress: 100, done: true })));
    }

    const projectId = await getOrCreateProject(form.clientId);
    if (!projectId) {
      setSubmitError('Erro ao criar ou encontrar o projeto para este cliente.');
      setSubmitting(false);
      return;
    }

    const { data: newDelivery, error: insertError } = await supabase
      .from('deliveries')
      .insert({
        client_id: form.clientId,
        project_id: projectId,
        title: form.title,
        type: form.type || 'Documento',
        status: form.status,
        description: form.description,
        file_url: fileUrl,
      })
      .select('id, title, type, status, created_at, client_id, profiles!deliveries_client_id_profiles_fkey(full_name, company_name)')
      .single();

    if (insertError) {
      setSubmitError(`Erro ao publicar entrega: ${insertError.message}`);
      setSubmitting(false);
      return;
    }

    if (newDelivery) {
      setDeliveries(prev => [{
        ...newDelivery,
        clientName: newDelivery.profiles?.company_name || newDelivery.profiles?.full_name || '—',
        date: formatDate(newDelivery.created_at),
      }, ...prev]);
    }

    setShowModal(false);
    setUploads([]);
    setUploadedFile(null);
    setForm({ clientId: '', title: '', type: '', status: 'production', description: '' });
    setSubmitting(false);
  };

  const filtered = filterStatus === 'all' ? deliveries : deliveries.filter(d => d.status === filterStatus);

  return (
    <div className="entregas-container">
      <div className="entregas-header">
        <div>
          <h1>Entregas</h1>
          <p>Gerencie e envie arquivos para seus clientes.</p>
        </div>
        <button className="btn-new-delivery" onClick={() => setShowModal(true)}>
          <Plus size={18} /> Nova Entrega
        </button>
      </div>

      <div className="filter-tabs">
        {[{ val: 'all', label: 'Todas' }, ...DELIVERY_STATUSES.map(s => ({ val: s.value, label: s.label }))].map(f => (
          <button
            key={f.val}
            onClick={() => setFilterStatus(f.val)}
            className={`filter-tab ${filterStatus === f.val ? 'active' : ''}`}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="deliveries-list">
        {loading && (
          <>
            {[1, 2, 3].map(i => (
              <div key={i} className="skeleton-delivery-row">
                <div className="skeleton skeleton-delivery-icon" />
                <div className="skeleton-lines">
                  <div className="skeleton skeleton-line" />
                  <div className="skeleton skeleton-line skeleton-line-short" />
                </div>
                <div className="skeleton skeleton-badge" />
              </div>
            ))}
          </>
        )}
        <AnimatePresence>
          {filtered.map((d, i) => {
            const s = statusMap[d.status] || statusMap.production;
            const Icon = typeIcon(d.type);
            const SIcon = s.icon;
            return (
              <DeliveryRow key={d.id} d={d} s={s} Icon={Icon} SIcon={SIcon} index={i} />
            );
          })}
        </AnimatePresence>
        {!loading && filtered.length === 0 && (
          <motion.div
            className="empty-deliveries"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
          >
            Nenhuma entrega encontrada.
          </motion.div>
        )}
      </div>

      {showModal && (
        <div className="modal-overlay" onClick={() => setShowModal(false)}>
          <div role="dialog" aria-modal="true" aria-labelledby="modal-entrega-title" className="modal-content" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <div>
                <h2 id="modal-entrega-title">Nova Entrega</h2>
                <p>Envie um arquivo para o portal do cliente.</p>
              </div>
              <button className="btn-close" aria-label="Fechar" onClick={() => setShowModal(false)}><X size={15} /></button>
            </div>

            <form onSubmit={handleSubmit}>
              <div className="form-group">
                <label className="form-label">Cliente *</label>
                <div className="select-wrapper">
                  <select required value={form.clientId}
                    onChange={e => setForm(f => ({ ...f, clientId: e.target.value }))}
                    className="select-input">
                    <option value="">Selecionar cliente...</option>
                    {clients.map(c => (
                      <option key={c.id} value={c.id}>
                        {c.company_name || c.full_name || c.email}
                      </option>
                    ))}
                  </select>
                  <ChevronDown size={16} className="select-icon" />
                </div>
              </div>

              <div className="form-group">
                <label className="form-label">Título da Entrega *</label>
                <input required type="text" placeholder="Ex: Landing Page v2 — Desktop"
                  value={form.title} onChange={e => setForm(f => ({ ...f, title: e.target.value }))}
                  className="form-input" />
              </div>

              <div className="form-row">
                <div>
                  <label className="form-label">Tipo</label>
                  <div className="select-wrapper">
                    <select value={form.type} onChange={e => setForm(f => ({ ...f, type: e.target.value }))} className="select-input">
                      <option value="">Selecionar...</option>
                      {DELIVERY_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
                    </select>
                    <ChevronDown size={16} className="select-icon" />
                  </div>
                </div>
                <div>
                  <label className="form-label">Status Inicial</label>
                  <div className="select-wrapper">
                    <select value={form.status} onChange={e => setForm(f => ({ ...f, status: e.target.value }))} className="select-input">
                      {DELIVERY_STATUSES.map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
                    </select>
                    <ChevronDown size={16} className="select-icon" />
                  </div>
                </div>
              </div>

              <div className="form-group">
                <label className="form-label">Descrição / Observações</label>
                <textarea placeholder="Descreva o que foi entregue, instruções de revisão, etc..."
                  value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))}
                  rows={3} className="form-input" style={{ resize: 'vertical' }} />
              </div>

              <div className="form-group">
                <label className="form-label">Arquivo</label>
                <motion.div
                  onDragOver={e => { e.preventDefault(); setDragging(true); }}
                  onDragLeave={() => setDragging(false)}
                  onDrop={e => { e.preventDefault(); setDragging(false); processFiles(e.dataTransfer.files); }}
                  onClick={() => document.getElementById('admin-file-input').click()}
                  className={`upload-zone ${dragging ? 'dragging' : ''}`}
                  animate={{
                    borderColor: dragging ? 'rgba(0,216,255,0.7)' : 'rgba(128,64,245,0.4)',
                    background: dragging ? 'rgba(0,216,255,0.06)' : 'rgba(128,64,245,0.03)',
                    boxShadow: dragging ? '0 0 48px rgba(0,216,255,0.15), inset 0 0 30px rgba(0,216,255,0.05)' : 'none',
                    scale: dragging ? 1.01 : 1,
                  }}
                  transition={{ duration: 0.2 }}
                >
                  <input id="admin-file-input" type="file" style={{ display: 'none' }}
                    onChange={e => processFiles(e.target.files)} />
                  <motion.div
                    className="upload-icon"
                    animate={{ scale: dragging ? 1.2 : 1, rotate: dragging ? 15 : 0 }}
                    transition={{ duration: 0.2 }}
                  >
                    <Upload size={24} color={dragging ? '#00D8FF' : undefined} />
                  </motion.div>
                  <div className="upload-text" style={{ color: dragging ? '#00D8FF' : undefined }}>
                    {dragging ? 'Solte aqui!' : 'Arraste um arquivo ou clique'}
                  </div>
                  <div className="upload-hint">PDF, Figma, ZIP, Imagens, Vídeos — Máx. 50 MB</div>
                </motion.div>

                {uploads.length > 0 && (
                  <div className="upload-progress-list">
                    {uploads.map(u => {
                      const Icon = getFileIcon(u.name);
                      return (
                        <div key={u.id} className={`upload-item ${u.done ? 'done' : ''}`}>
                          <div className="upload-item-icon"><Icon size={18} strokeWidth={1.5} /></div>
                          <div className="upload-item-info">
                            <div className="upload-item-name">{u.name}</div>
                            {u.done
                              ? <div className="upload-status-done"><Check size={12} /> Pronto — {u.size}</div>
                              : <div className="progress-bar-container"><div className="progress-bar-fill" style={{ width: `${u.progress}%` }} /></div>
                            }
                          </div>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>

              {submitError && (
                <div style={{ color: '#f43f5e', fontSize: 13, padding: '8px 12px', background: 'rgba(244,63,94,0.1)', borderRadius: 8, marginBottom: 8 }}>
                  {submitError}
                </div>
              )}
              <button type="submit" className="btn-submit" disabled={submitting}>
                {submitting ? 'Publicando...' : 'Publicar Entrega no Portal do Cliente'}
              </button>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
