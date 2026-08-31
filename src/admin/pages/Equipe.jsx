import React, { useEffect, useState, useRef } from 'react';
import { createPortal } from 'react-dom';
import { motion, AnimatePresence } from 'framer-motion';
import {
  UserCircle2, Star, Users, X, ChevronRight, Check,
  Plus, Loader2, FileArchive, Send, UserPlus, UserMinus, Trash2,
} from 'lucide-react';
import { supabase } from '../../config/supabase';
import './Equipe.css';

function StarPicker({ value, onChange }) {
  const [hov, setHov] = useState(0);
  return (
    <div className="star-picker">
      {[1, 2, 3, 4, 5].map(i => (
        <button
          key={i}
          type="button"
          className="star-btn"
          onMouseEnter={() => setHov(i)}
          onMouseLeave={() => setHov(0)}
          onClick={() => onChange(i)}
        >
          <Star
            size={20}
            fill={(hov || value) >= i ? '#f59e0b' : 'none'}
            color={(hov || value) >= i ? '#f59e0b' : 'rgba(255,255,255,0.2)'}
          />
        </button>
      ))}
    </div>
  );
}

function StarDisplay({ value }) {
  return (
    <div className="star-display">
      {[1, 2, 3, 4, 5].map(i => (
        <Star key={i} size={12}
          fill={i <= value ? '#f59e0b' : 'none'}
          color={i <= value ? '#f59e0b' : 'rgba(255,255,255,0.15)'} />
      ))}
    </div>
  );
}

function formatRelative(iso) {
  if (!iso) return '';
  const diff = Date.now() - new Date(iso).getTime();
  const min = Math.floor(diff / 60000);
  if (min < 60) return `${min}min atrás`;
  const h = Math.floor(min / 60);
  if (h < 24) return `${h}h atrás`;
  return `${Math.floor(h / 24)}d atrás`;
}

const JOB_TITLES = ['SDR', 'Closer', 'Hunter', 'Chefe de Infraestrutura', 'Designer', 'Sócio'];

export default function Equipe() {
  const [employees, setEmployees]     = useState([]);
  const [loading, setLoading]         = useState(true);
  const [selected, setSelected]       = useState(null);
  const [tab, setTab]                 = useState('notas');
  const [notes, setNotes]             = useState([]);
  const [clients, setClients]         = useState([]);
  const [allClients, setAllClients]   = useState([]);
  const [files, setFiles]             = useState([]);
  const [drawerLoading, setDrawerLoading] = useState(false);
  const [currentUser, setCurrentUser] = useState(null);
  const [clientCounts, setClientCounts] = useState({});

  // Note form
  const [noteText, setNoteText]       = useState('');
  const [noteRating, setNoteRating]   = useState(0);
  const [saving, setSaving]           = useState(false);

  // File upload
  const fileInputRef = useRef(null);
  const [uploading, setUploading]     = useState(false);
  const [uploadMsg, setUploadMsg]     = useState('');

  // Create member modal
  const [showCreate, setShowCreate]   = useState(false);
  const [creating, setCreating]       = useState(false);
  const [createForm, setCreateForm]   = useState({ full_name: '', email: '', job_title: '', password: '' });
  const [createError, setCreateError] = useState('');

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      const me = session?.user || null;
      if (me) setCurrentUser(me);
      loadEmployees(me?.id);
    });
    supabase
      .from('profiles')
      .select('assigned_employee_id')
      .eq('role', 'client')
      .not('assigned_employee_id', 'is', null)
      .then(({ data }) => {
        const counts = {};
        (data || []).forEach(p => {
          counts[p.assigned_employee_id] = (counts[p.assigned_employee_id] || 0) + 1;
        });
        setClientCounts(counts);
      });
  }, []);

  async function loadEmployees(myId) {
    const { data } = await supabase
      .from('profiles')
      .select('id, full_name, email, avatar_url, job_title, role')
      .in('role', ['employee', 'manager', 'super_admin'])
      .limit(100);
    setEmployees((data || []).filter(e => e.id !== myId));
    setLoading(false);
  }

  async function handleCreateMember(e) {
    e.preventDefault();
    if (!createForm.full_name.trim() || !createForm.job_title || !createForm.email.trim() || !createForm.password.trim()) return;
    setCreating(true);
    setCreateError('');
    try {
      const { data: { session } } = await supabase.auth.getSession();
      const res = await fetch(`${import.meta.env.VITE_SUPABASE_URL}/functions/v1/create-employee`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${session?.access_token}`,
          'apikey': import.meta.env.VITE_SUPABASE_ANON_KEY,
        },
        body: JSON.stringify({
          full_name: createForm.full_name.trim(),
          email: createForm.email.trim(),
          job_title: createForm.job_title,
          password: createForm.password.trim(),
        }),
      });
      const json = await res.json();
      if (!res.ok) {
        setCreateError(json.error ?? 'Erro ao criar membro');
        setCreating(false);
        return;
      }
      setCreateForm({ full_name: '', email: '', job_title: '', password: '' });
      setShowCreate(false);
      await loadEmployees(currentUser?.id);
    } catch {
      setCreateError('Erro de conexão. Tente novamente.');
    }
    setCreating(false);
  }

  async function openEmployee(emp) {
    setSelected(emp);
    setTab('notas');
    setDrawerLoading(true);
    await refreshDrawerData(emp.id);
    setDrawerLoading(false);
  }

  async function refreshDrawerData(empId) {
    const [notesRes, clientsRes, allCRes, filesRes] = await Promise.all([
      supabase
        .from('employee_notes')
        .select('id, employee_id, author_id, content, rating, created_at')
        .eq('employee_id', empId)
        .order('created_at', { ascending: false }),
      supabase
        .from('profiles')
        .select('id, full_name, company_name, email, avatar_url')
        .eq('assigned_employee_id', empId)
        .eq('role', 'client'),
      supabase
        .from('profiles')
        .select('id, full_name, company_name, email, assigned_employee_id')
        .eq('role', 'client'),
      supabase
        .from('internal_files')
        .select('id, from_id, to_id, file_url, file_name, file_size, message, created_at')
        .or(`from_id.eq.${empId},to_id.eq.${empId}`)
        .order('created_at', { ascending: false }),
    ]);
    if (!notesRes.error)   setNotes(notesRes.data || []);
    if (!clientsRes.error) setClients(clientsRes.data || []);
    if (!allCRes.error)    setAllClients(allCRes.data || []);
    if (!filesRes.error)   setFiles(filesRes.data || []);
  }

  async function handleAddNote(e) {
    e.preventDefault();
    if (!noteText.trim() || !selected || !currentUser) return;
    setSaving(true);
    await supabase.from('employee_notes').insert({
      employee_id: selected.id,
      author_id: currentUser.id,
      content: noteText.trim(),
      rating: noteRating || null,
    });
    setNoteText('');
    setNoteRating(0);
    await refreshDrawerData(selected.id);
    setSaving(false);
  }

  async function handleDeleteNote(noteId) {
    await supabase.from('employee_notes').delete().eq('id', noteId);
    await refreshDrawerData(selected.id);
  }

  async function toggleClientAssign(client) {
    const isAssigned = client.assigned_employee_id === selected?.id;
    await supabase
      .from('profiles')
      .update({ assigned_employee_id: isAssigned ? null : selected.id })
      .eq('id', client.id);
    await refreshDrawerData(selected.id);
  }

  async function handleFileUpload(e) {
    const file = e.target.files?.[0];
    if (!file || !selected || !currentUser) return;
    setUploading(true);
    const ext  = file.name.split('.').pop().toLowerCase();
    const path = `internal/${currentUser.id}/${selected.id}/${Date.now()}.${ext}`;
    const { error: uploadErr } = await supabase.storage
      .from('internal-files')
      .upload(path, file, { contentType: file.type });
    if (!uploadErr) {
      // Bucket privado: guardamos o caminho; o link é assinado no download.
      await supabase.from('internal_files').insert({
        from_id: currentUser.id,
        to_id: selected.id,
        file_url: path,
        file_name: file.name,
        file_size: `${(file.size / 1024).toFixed(1)} KB`,
        message: uploadMsg.trim() || null,
      });
      setUploadMsg('');
      await refreshDrawerData(selected.id);
    }
    setUploading(false);
    e.target.value = '';
  }

  const avgRating = (emp) => {
    const empNotes = notes.filter(n => n.employee_id === emp.id && n.rating != null);
    if (!empNotes.length) return null;
    return (empNotes.reduce((a, n) => a + n.rating, 0) / empNotes.length).toFixed(1);
  };

  const drawerNotes   = notes.filter(n => n.employee_id === selected?.id);
  const drawerNotesWithRating = drawerNotes.filter(n => n.rating != null);
  const drawerAvg = drawerNotesWithRating.length
    ? (drawerNotesWithRating.reduce((a, n) => a + n.rating, 0) / drawerNotesWithRating.length).toFixed(1)
    : null;

  return (
    <div className="equipe-container">

      {/* ── Header ── */}
      <div className="equipe-header">
        <div>
          <h1 className="equipe-title">Equipe</h1>
          <p className="equipe-sub">Gerencie membros, avalie e atribua clientes.</p>
        </div>
        <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
          <button className="btn-novo-membro" onClick={() => setShowCreate(true)}>
            <Plus size={14} /> Novo membro
          </button>
          <div className="equipe-count-badge">{employees.length} membro{employees.length !== 1 ? 's' : ''}</div>
        </div>
      </div>

      {/* ── Employee grid ── */}
      {loading ? (
        <div className="equipe-grid">
          {[1, 2, 3].map(i => (
            <div key={i} className="skeleton-emp-card">
              <div className="skeleton-emp-top">
                <div className="skeleton skeleton-avatar-sq" />
                <div className="skeleton-lines">
                  <div className="skeleton skeleton-line" />
                  <div className="skeleton skeleton-line skeleton-line-short" />
                </div>
              </div>
              <div className="skeleton skeleton-line skeleton-line-short" />
            </div>
          ))}
        </div>
      ) : employees.length === 0 ? (
        <div className="equipe-empty" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', padding: '48px 0', gap: 8 }}>
          <Users size={36} style={{ opacity: 0.25 }} />
          <div>Nenhum funcionário cadastrado ainda.</div>
          <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Clique em "Novo membro" para adicionar.</div>
        </div>
      ) : (
        <div className="equipe-grid">
          {employees.map((emp, idx) => (
            <motion.div
              key={emp.id}
              className="emp-card-admin"
              initial={{ opacity: 0, y: 16 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: idx * 0.06 }}
              whileHover={{ y: -4 }}
              onClick={() => openEmployee(emp)}
            >
              <div className="emp-card-top">
                <div className="emp-card-avatar">
                  {emp.avatar_url
                    ? <img src={emp.avatar_url} alt={emp.full_name} loading="lazy" />
                    : <span>{(emp.full_name || emp.email || '?').slice(0, 1).toUpperCase()}</span>
                  }
                  <div className="emp-online-dot" />
                </div>
                <div className="emp-card-info">
                  <div className="emp-card-name">{emp.full_name || emp.email}</div>
                  <div className="emp-card-role">{emp.job_title || 'Funcionário'}</div>
                  <div className="emp-card-email">{emp.email}</div>
                </div>
                <ChevronRight size={16} className="emp-card-chevron" />
              </div>
              <div className="emp-card-footer">
                <span className="emp-card-stat">
                  <Users size={12} /> {clientCounts[emp.id] || 0} clientes
                </span>
                {avgRating(emp) && (
                  <span className="emp-card-stat">
                    <Star size={12} style={{ color: '#f59e0b' }} /> {avgRating(emp)}
                  </span>
                )}
              </div>
            </motion.div>
          ))}
        </div>
      )}

      {/* ── Create member modal ── */}
      {createPortal(
      <AnimatePresence>
        {showCreate && (
          <>
            <motion.div
              className="drawer-overlay"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => { setShowCreate(false); setCreateError(''); }}
            />
            <div className="create-modal-centering">
            <motion.div
              role="dialog"
              aria-modal="true"
              aria-labelledby="modal-novo-membro-title"
              className="create-member-modal"
              initial={{ opacity: 0, scale: 0.95, y: -12 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: -12 }}
              transition={{ type: 'spring', damping: 28, stiffness: 320 }}
            >
              <div className="create-modal-header">
                <span id="modal-novo-membro-title" className="create-modal-title">Novo membro</span>
                <button className="drawer-close" aria-label="Fechar" onClick={() => setShowCreate(false)}>
                  <X size={16} />
                </button>
              </div>
              <form className="create-modal-form" onSubmit={handleCreateMember}>
                <div className="create-field">
                  <label className="create-label">Nome</label>
                  <input
                    className="create-input"
                    type="text"
                    placeholder="Nome completo"
                    value={createForm.full_name}
                    onChange={e => setCreateForm(f => ({ ...f, full_name: e.target.value }))}
                    required
                    autoFocus
                  />
                </div>
                <div className="create-field">
                  <label className="create-label">E-mail</label>
                  <input
                    className="create-input"
                    type="email"
                    placeholder="email@exemplo.com"
                    value={createForm.email}
                    onChange={e => setCreateForm(f => ({ ...f, email: e.target.value }))}
                    required
                  />
                </div>
                <div className="create-field">
                  <label className="create-label">Senha</label>
                  <input
                    className="create-input"
                    type="password"
                    placeholder="Senha de acesso"
                    value={createForm.password}
                    onChange={e => setCreateForm(f => ({ ...f, password: e.target.value }))}
                    required
                  />
                </div>
                <div className="create-field">
                  <label className="create-label">Cargo</label>
                  <div className="create-cargo-grid">
                    {JOB_TITLES.map(title => (
                      <button
                        key={title}
                        type="button"
                        className={`create-cargo-btn${createForm.job_title === title ? ' selected' : ''}`}
                        onClick={() => setCreateForm(f => ({ ...f, job_title: title }))}
                      >
                        {title}
                      </button>
                    ))}
                  </div>
                </div>
                {createError && (
                  <p style={{ color: '#f87171', fontSize: '0.8rem', margin: '0 0 4px' }}>{createError}</p>
                )}
                <button
                  type="submit"
                  className="note-submit"
                  disabled={creating || !createForm.full_name.trim() || !createForm.job_title || !createForm.email.trim() || !createForm.password.trim()}
                >
                  {creating ? <Loader2 size={14} className="spin" /> : <Plus size={14} />}
                  {creating ? 'Criando...' : 'Criar membro'}
                </button>
              </form>
            </motion.div>
            </div>
          </>
        )}
      </AnimatePresence>
      , document.body)}

      {/* ── Drawer overlay ── */}
      {createPortal(
      <AnimatePresence>
        {selected && (
          <>
            <motion.div
              className="drawer-overlay"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setSelected(null)}
            />
            <motion.div
              className="emp-drawer"
              initial={{ x: '100%' }}
              animate={{ x: 0 }}
              exit={{ x: '100%' }}
              transition={{ type: 'spring', damping: 28, stiffness: 280 }}
            >
              {/* Drawer header */}
              <div className="drawer-header">
                <div className="drawer-employee-info">
                  <div className="drawer-avatar">
                    {selected.avatar_url
                      ? <img src={selected.avatar_url} alt={selected.full_name} loading="lazy" />
                      : <span>{(selected.full_name || selected.email).slice(0, 1).toUpperCase()}</span>
                    }
                  </div>
                  <div>
                    <div className="drawer-name">{selected.full_name || selected.email}</div>
                    <div className="drawer-job">{selected.job_title || 'Funcionário'}</div>
                    {drawerAvg && (
                      <div className="drawer-avg">
                        <span style={{ color: '#f59e0b', fontWeight: 700, fontFamily: 'var(--font-mono)' }}>{drawerAvg}</span>
                        <StarDisplay value={Math.round(Number(drawerAvg))} />
                      </div>
                    )}
                  </div>
                </div>
                <button className="drawer-close" onClick={() => setSelected(null)}>
                  <X size={18} />
                </button>
              </div>

              {/* Tabs */}
              <div className="drawer-tabs">
                {['notas', 'clientes', 'arquivos'].map(t => (
                  <button
                    key={t}
                    className={`drawer-tab${tab === t ? ' active' : ''}`}
                    onClick={() => setTab(t)}
                  >
                    {t === 'notas' ? 'Avaliações' : t === 'clientes' ? 'Clientes' : 'Arquivos'}
                  </button>
                ))}
              </div>

              {/* Tab content */}
              <div className="drawer-body">
                {drawerLoading ? (
                  <div className="drawer-loading"><Loader2 size={20} className="spin" /> Carregando...</div>
                ) : (

                  /* ── Notas tab ── */
                  tab === 'notas' ? (
                    <div className="drawer-notas">
                      <form className="note-form" onSubmit={handleAddNote}>
                        <div className="note-form-rating">
                          <span className="note-form-label">Avaliação</span>
                          <StarPicker value={noteRating} onChange={setNoteRating} />
                        </div>
                        <textarea
                          className="note-textarea"
                          placeholder="Escreva uma nota ou feedback..."
                          value={noteText}
                          onChange={e => setNoteText(e.target.value)}
                          rows={3}
                        />
                        <button type="submit" className="note-submit" disabled={saving || !noteText.trim()}>
                          {saving ? <Loader2 size={14} className="spin" /> : <Plus size={14} />}
                          {saving ? 'Salvando...' : 'Adicionar nota'}
                        </button>
                      </form>

                      <div className="notes-timeline">
                        {drawerNotes.length === 0 ? (
                          <div className="drawer-empty">Nenhuma avaliação ainda.</div>
                        ) : drawerNotes.map(note => (
                          <div key={note.id} className="note-entry">
                            <div className="note-entry-header">
                              <span className="note-author">Equipe Pixelry</span>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                                <span className="note-time">{formatRelative(note.created_at)}</span>
                                <button
                                  className="note-delete-btn"
                                  onClick={() => handleDeleteNote(note.id)}
                                  title="Excluir avaliação"
                                >
                                  <Trash2 size={12} />
                                </button>
                              </div>
                            </div>
                            {note.rating && <StarDisplay value={note.rating} />}
                            <p className="note-body">{note.content}</p>
                          </div>
                        ))}
                      </div>
                    </div>

                  /* ── Clientes tab ── */
                  ) : tab === 'clientes' ? (
                    <div className="drawer-clients">
                      <p className="drawer-clients-hint">Marque quais clientes estão sob responsabilidade de {selected.full_name?.split(' ')[0] || 'este funcionário'}.</p>
                      <div className="all-clients-list">
                        {allClients.length === 0 && (
                          <div className="drawer-empty">Nenhum cliente cadastrado.</div>
                        )}
                        {allClients.map(client => {
                          const isAssigned = client.assigned_employee_id === selected.id;
                          return (
                            <div key={client.id} className={`client-assign-row${isAssigned ? ' assigned' : ''}`}>
                              <div className="client-assign-avatar">
                                {(client.company_name || client.full_name || '?').slice(0, 1).toUpperCase()}
                              </div>
                              <div className="client-assign-info">
                                <div className="client-assign-name">{client.company_name || client.full_name || 'Cliente'}</div>
                                <div className="client-assign-email">{client.email}</div>
                              </div>
                              <button
                                className={`client-assign-btn${isAssigned ? ' remove' : ''}`}
                                onClick={() => toggleClientAssign(client)}
                              >
                                {isAssigned ? <><UserMinus size={13} /> Remover</> : <><UserPlus size={13} /> Atribuir</>}
                              </button>
                            </div>
                          );
                        })}
                      </div>
                    </div>

                  /* ── Arquivos tab ── */
                  ) : (
                    <div className="drawer-arquivos">
                      <div className="file-upload-area">
                        <input
                          type="text"
                          className="file-msg-input"
                          placeholder="Mensagem (opcional)..."
                          value={uploadMsg}
                          onChange={e => setUploadMsg(e.target.value)}
                        />
                        <button
                          className="file-upload-btn"
                          onClick={() => fileInputRef.current?.click()}
                          disabled={uploading}
                        >
                          {uploading ? <Loader2 size={14} className="spin" /> : <FileArchive size={14} />}
                          {uploading ? 'Enviando...' : 'Enviar arquivo'}
                        </button>
                        <input
                          ref={fileInputRef}
                          type="file"
                          style={{ display: 'none' }}
                          onChange={handleFileUpload}
                        />
                      </div>
                      <div className="files-list-drawer">
                        {files.length === 0 ? (
                          <div className="drawer-empty">Nenhum arquivo trocado.</div>
                        ) : files.map(f => (
                          <div key={f.id} className="file-row">
                            <div className="file-row-icon"><FileArchive size={14} /></div>
                            <div className="file-row-info">
                              <div className="file-row-name">{f.file_name}</div>
                              {f.message && <div className="file-row-msg">{f.message}</div>}
                              <div className="file-row-meta">{f.file_size && `${f.file_size} · `}{formatRelative(f.created_at)}</div>
                            </div>
                            <a href={f.file_url} target="_blank" rel="noreferrer" className="file-row-dl">
                              Baixar
                            </a>
                          </div>
                        ))}
                      </div>
                    </div>
                  )
                )}
              </div>
            </motion.div>
          </>
        )}
      </AnimatePresence>
      , document.body)}
    </div>
  );
}
