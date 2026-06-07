import React, { useEffect, useState, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  UserCircle2, Star, Users, X, ChevronRight, Check,
  Plus, Loader2, FileArchive, Send, UserPlus, UserMinus,
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

  // Note form
  const [noteText, setNoteText]       = useState('');
  const [noteRating, setNoteRating]   = useState(0);
  const [saving, setSaving]           = useState(false);

  // File upload
  const fileInputRef = useRef(null);
  const [uploading, setUploading]     = useState(false);
  const [uploadMsg, setUploadMsg]     = useState('');

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session?.user) setCurrentUser(session.user);
    });
    loadEmployees();
  }, []);

  async function loadEmployees() {
    const { data } = await supabase
      .from('profiles')
      .select('id, full_name, email, avatar_url, job_title, role')
      .eq('role', 'employee');
    setEmployees(data || []);
    setLoading(false);
  }

  async function openEmployee(emp) {
    setSelected(emp);
    setTab('notas');
    setDrawerLoading(true);
    await refreshDrawerData(emp.id);
    setDrawerLoading(false);
  }

  async function refreshDrawerData(empId) {
    const [
      { data: empNotes },
      { data: empClients },
      { data: allC },
      { data: empFiles },
    ] = await Promise.all([
      supabase
        .from('employee_notes')
        .select('*')
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
        .select('*')
        .or(`from_id.eq.${empId},to_id.eq.${empId}`)
        .order('created_at', { ascending: false }),
    ]);
    setNotes(empNotes || []);
    setClients(empClients || []);
    setAllClients(allC || []);
    setFiles(empFiles || []);
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
      const { data: { publicUrl } } = supabase.storage.from('internal-files').getPublicUrl(path);
      await supabase.from('internal_files').insert({
        from_id: currentUser.id,
        to_id: selected.id,
        file_url: publicUrl,
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
    const empNotes = notes.filter(n => n.employee_id === emp.id && n.rating);
    if (!empNotes.length) return null;
    return (empNotes.reduce((a, n) => a + n.rating, 0) / empNotes.length).toFixed(1);
  };

  const drawerNotes   = notes.filter(n => n.employee_id === selected?.id);
  const drawerAvg     = drawerNotes.filter(n => n.rating).length
    ? (drawerNotes.filter(n => n.rating).reduce((a, n) => a + n.rating, 0) / drawerNotes.filter(n => n.rating).length).toFixed(1)
    : null;

  return (
    <div className="equipe-container">

      {/* ── Header ── */}
      <div className="equipe-header">
        <div>
          <h1 className="equipe-title">Equipe</h1>
          <p className="equipe-sub">Gerencie funcionários, avalie e atribua clientes.</p>
        </div>
        <div className="equipe-count-badge">{employees.length} funcionário{employees.length !== 1 ? 's' : ''}</div>
      </div>

      {/* ── Employee grid ── */}
      {loading ? (
        <div className="equipe-loading">Carregando equipe...</div>
      ) : employees.length === 0 ? (
        <div className="equipe-empty">Nenhum funcionário cadastrado ainda.</div>
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
                    ? <img src={emp.avatar_url} alt={emp.full_name} />
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
                  <Users size={12} /> {clients.filter(c => c.assigned_employee_id === emp.id).length} clientes
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

      {/* ── Drawer overlay ── */}
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
                      ? <img src={selected.avatar_url} alt={selected.full_name} />
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
                              <span className="note-time">{formatRelative(note.created_at)}</span>
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
    </div>
  );
}
