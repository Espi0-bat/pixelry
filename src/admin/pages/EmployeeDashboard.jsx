import React, { useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import { Users, Star, FileArchive, MessageSquare, ExternalLink, Clock } from 'lucide-react';
import { Link } from 'react-router-dom';
import { supabase } from '../../config/supabase';
import './EmployeeDashboard.css';

function getGreeting() {
  const h = new Date().getHours();
  if (h < 12) return 'Bom dia';
  if (h < 18) return 'Boa tarde';
  return 'Boa noite';
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

function StarRating({ value }) {
  return (
    <div className="emp-stars">
      {[1, 2, 3, 4, 5].map(i => (
        <Star
          key={i}
          size={13}
          fill={i <= value ? 'currentColor' : 'none'}
          style={{ color: i <= value ? '#f59e0b' : 'rgba(255,255,255,0.2)' }}
        />
      ))}
    </div>
  );
}

export default function EmployeeDashboard({ userProfile, user }) {
  const [assignedClients, setAssignedClients] = useState([]);
  const [recentFiles, setRecentFiles]         = useState([]);
  const [notes, setNotes]                     = useState([]);
  const [loading, setLoading]                 = useState(true);

  const firstName = userProfile?.full_name?.split(' ')[0]
    || (user?.email?.includes('sofiagramelich') ? 'Sofia' : user?.email?.split('@')[0] || 'Designer');

  const jobTitle = userProfile?.job_title || 'Designer';

  const currentDate = new Date().toLocaleDateString('pt-BR', {
    weekday: 'long', day: 'numeric', month: 'long',
  });

  useEffect(() => {
    async function load() {
      if (!user?.id) return;
      const [
        { data: clients },
        { data: files },
        { data: myNotes },
      ] = await Promise.all([
        supabase
          .from('profiles')
          .select('id, full_name, company_name, avatar_url, email')
          .eq('assigned_employee_id', user.id)
          .eq('role', 'client'),
        supabase
          .from('internal_files')
          .select('id, file_url, file_name, file_size, message, created_at, to_id, read_at')
          .eq('to_id', user.id)
          .order('created_at', { ascending: false })
          .limit(5),
        supabase
          .from('employee_notes')
          .select('id, rating, content, created_at')
          .eq('employee_id', user.id)
          .order('created_at', { ascending: false }),
      ]);
      setAssignedClients(clients || []);
      setRecentFiles(files || []);
      setNotes(myNotes || []);
      setLoading(false);
    }
    load();
  }, [user?.id]);

  const unreadFiles = recentFiles.filter(f => !f.read_at).length;
  const ratedNotes  = notes.filter(n => n.rating);
  const avgRating   = ratedNotes.length
    ? (ratedNotes.reduce((a, n) => a + n.rating, 0) / ratedNotes.length).toFixed(1)
    : null;

  return (
    <div className="emp-dash">

      {/* ── Hero ── */}
      <div className="emp-hero">
        <div className="emp-hero-left">
          <span className="emp-eyebrow">
            <span className="emp-eyebrow-dot" />
            {jobTitle.toUpperCase()} · PIXELRY
          </span>
          <h1 className="emp-greeting">
            {getGreeting()},<br />
            <span className="emp-greeting-name">{firstName}.</span>
          </h1>
          <p className="emp-date" style={{ textTransform: 'capitalize' }}>{currentDate}</p>
        </div>

        <div className="emp-hero-right">
          <div className="emp-quick-stats">
            <div className="emp-qs-item">
              <span className="emp-qs-val">{loading ? '—' : assignedClients.length}</span>
              <span className="emp-qs-label">Clientes</span>
            </div>
            <div className="emp-qs-sep" />
            <div className="emp-qs-item">
              <span className="emp-qs-val" style={{ color: unreadFiles > 0 ? '#f59e0b' : undefined }}>
                {loading ? '—' : unreadFiles}
              </span>
              <span className="emp-qs-label">Novos arq.</span>
            </div>
            <div className="emp-qs-sep" />
            <div className="emp-qs-item">
              <span className="emp-qs-val" style={{ color: '#f59e0b' }}>
                {loading ? '—' : avgRating ?? '—'}
              </span>
              <span className="emp-qs-label">Avaliação</span>
            </div>
          </div>
        </div>
      </div>

      {/* ── Quick actions ── */}
      <div className="emp-quick-actions">
        <Link to="/admin/mensagens" className="emp-action">
          <div className="emp-action-icon" style={{ background: 'rgba(128,64,245,0.15)', color: 'var(--primary-color)' }}>
            <MessageSquare size={18} />
          </div>
          <div>
            <div className="emp-action-label">Mensagens</div>
            <div className="emp-action-sub">Falar com a equipe</div>
          </div>
        </Link>
        <Link to="/admin/arquivos" className="emp-action">
          <div className="emp-action-icon" style={{ background: 'rgba(245,158,11,0.15)', color: '#f59e0b' }}>
            <FileArchive size={18} />
          </div>
          <div>
            <div className="emp-action-label">Arquivos</div>
            <div className="emp-action-sub">{unreadFiles > 0 ? `${unreadFiles} novo${unreadFiles > 1 ? 's' : ''}` : 'Ver todos'}</div>
          </div>
        </Link>
      </div>

      {/* ── Meus clientes ── */}
      <div className="emp-section">
        <div className="emp-section-header">
          <h2 className="emp-section-title"><Users size={16} /> Meus Clientes</h2>
          <span className="emp-section-count">{assignedClients.length}</span>
        </div>

        {loading ? (
          <div className="emp-loading">Carregando...</div>
        ) : assignedClients.length === 0 ? (
          <div className="emp-empty">Nenhum cliente atribuído ainda.</div>
        ) : (
          <div className="emp-clients-grid">
            {assignedClients.map(client => (
              <motion.div
                key={client.id}
                className="emp-client-card"
                whileHover={{ y: -3 }}
                transition={{ duration: 0.18 }}
              >
                <div className="emp-client-avatar">
                  {client.avatar_url
                    ? <img src={client.avatar_url} alt={client.full_name} loading="lazy" />
                    : <span>{(client.company_name || client.full_name || '?').slice(0, 1).toUpperCase()}</span>
                  }
                </div>
                <div className="emp-client-info">
                  <div className="emp-client-name">{client.company_name || client.full_name || 'Cliente'}</div>
                  <div className="emp-client-email">{client.email}</div>
                </div>
                <ExternalLink size={14} className="emp-client-arrow" />
              </motion.div>
            ))}
          </div>
        )}
      </div>

      {/* ── Bottom row ── */}
      <div className="emp-bottom-row">

        {/* Arquivos recebidos */}
        <div className="emp-card">
          <h2 className="emp-card-title"><FileArchive size={16} color="#f59e0b" /> Arquivos Recebidos</h2>
          {loading ? (
            <div className="emp-loading">Carregando...</div>
          ) : recentFiles.length === 0 ? (
            <div className="emp-empty">Nenhum arquivo recebido.</div>
          ) : (
            <div className="emp-files-list">
              {recentFiles.map(file => (
                <div key={file.id} className={`emp-file-item${!file.read_at ? ' unread' : ''}`}>
                  <div className="emp-file-icon">
                    <FileArchive size={14} />
                  </div>
                  <div className="emp-file-info">
                    <div className="emp-file-name">{file.file_name}</div>
                    {file.message && <div className="emp-file-msg">{file.message}</div>}
                  </div>
                  <div className="emp-file-meta">
                    <div className="emp-file-time">{formatRelative(file.created_at)}</div>
                    <a href={file.file_url} target="_blank" rel="noreferrer" className="emp-file-dl">Baixar</a>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Minhas avaliações */}
        <div className="emp-card">
          <div className="emp-card-header">
            <h2 className="emp-card-title"><Star size={16} color="#f59e0b" /> Minhas Avaliações</h2>
            {avgRating && (
              <div className="emp-avg-rating">
                <span className="emp-avg-val">{avgRating}</span>
                <StarRating value={Math.round(Number(avgRating))} />
              </div>
            )}
          </div>

          {loading ? (
            <div className="emp-loading">Carregando...</div>
          ) : notes.length === 0 ? (
            <div className="emp-empty">Nenhuma avaliação recebida ainda.</div>
          ) : (
            <div className="emp-notes-list">
              {notes.slice(0, 5).map(note => (
                <div key={note.id} className="emp-note-item">
                  <div className="emp-note-header">
                    <div className="emp-note-author">Equipe Pixelry</div>
                    <div className="emp-note-time">{formatRelative(note.created_at)}</div>
                  </div>
                  {note.rating && <StarRating value={note.rating} />}
                  <p className="emp-note-content">{note.content}</p>
                </div>
              ))}
            </div>
          )}
        </div>

      </div>
    </div>
  );
}
