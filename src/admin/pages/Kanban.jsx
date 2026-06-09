import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Plus, X, Calendar, User, Briefcase, Flag, ChevronDown, Clock } from 'lucide-react';
import { supabase } from '../../config/supabase';
import './Kanban.css';

const COLUMNS = [
  { id: 'backlog',  label: 'Backlog',       color: '#6b7280' },
  { id: 'copy',     label: 'Copywriting',   color: '#f59e0b' },
  { id: 'design',   label: 'Design',        color: '#8040F5' },
  { id: 'review',   label: 'Em Revisão',    color: '#f43f5e' },
  { id: 'done',     label: 'Pronto',        color: '#10b981' },
];

const PRIORITY_MAP = {
  high:   { label: 'Alta',  color: '#f43f5e', bg: 'rgba(244,63,94,0.12)' },
  medium: { label: 'Média', color: '#f59e0b', bg: 'rgba(245,158,11,0.12)' },
  low:    { label: 'Baixa', color: '#10b981', bg: 'rgba(16,185,129,0.12)' },
};

const EMPTY_FORM = { title: '', client: '', type: '', assignee: '', priority: 'medium', due: '' };

const PRIORITY_RANK = { high: 3, medium: 2, low: 1 };

function getEffectivePriority(task) {
  if (!task.due) return { priority: task.priority, autoEscalated: false };
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const daysLeft = Math.floor((new Date(task.due + 'T00:00:00') - today) / 86400000);
  let minPriority = task.priority;
  if (daysLeft <= 2) minPriority = 'high';
  else if (daysLeft <= 5 && task.priority === 'low') minPriority = 'medium';
  return { priority: minPriority, autoEscalated: PRIORITY_RANK[minPriority] > PRIORITY_RANK[task.priority] };
}

function formatDue(due) {
  if (!due) return null;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const daysLeft = Math.floor((new Date(due + 'T00:00:00') - today) / 86400000);
  if (daysLeft < 0)  return { text: `Vencido (${Math.abs(daysLeft)}d)`, level: 'overdue' };
  if (daysLeft === 0) return { text: 'Hoje!', level: 'critical' };
  if (daysLeft === 1) return { text: 'Amanhã', level: 'critical' };
  if (daysLeft <= 5)  return { text: `${daysLeft} dias`, level: 'warning' };
  return { text: due, level: null };
}

export default function Kanban() {
  const [tasks, setTasks]       = useState([]);
  const [modal, setModal]       = useState(false);
  const [form, setForm]         = useState(EMPTY_FORM);
  const [dragOver, setDragOver] = useState(null);
  const [loading, setLoading]   = useState(true);
  const [saving, setSaving]     = useState(false);
  const dragId = useRef(null);

  // ── Carrega tarefas do Supabase ──────────────────────────────────────────
  useEffect(() => {
    async function load() {
      const { data, error } = await supabase
        .from('kanban_tasks')
        .select('id, title, client, type, assignee, priority, due, status, created_at')
        .order('created_at', { ascending: true });

      if (error) {
        console.error('Kanban load error:', error);
        setLoading(false);
        return;
      }
      setTasks(data || []);
      setLoading(false);
    }
    load();
  }, []);

  // ── Realtime: sincroniza mudanças feitas por outros admins ───────────────
  useEffect(() => {
    const channel = supabase
      .channel('admin:kanban')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'kanban_tasks' },
        (payload) => {
          if (payload.eventType === 'INSERT') {
            setTasks(prev => [...prev, payload.new]);
          } else if (payload.eventType === 'UPDATE') {
            setTasks(prev => prev.map(t => t.id === payload.new.id ? payload.new : t));
          } else if (payload.eventType === 'DELETE') {
            setTasks(prev => prev.filter(t => t.id !== payload.old.id));
          }
        }
      )
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, []);

  // ── Drag & Drop — atualiza status no Supabase ────────────────────────────
  const handleDragStart = useCallback((id) => {
    dragId.current = id;
  }, []);

  const handleDrop = useCallback(async (colId) => {
    if (dragId.current == null) return;
    const taskId = dragId.current;
    dragId.current = null;
    setDragOver(null);

    // Guarda status anterior para rollback
    let prevStatus = null;
    setTasks(prev => prev.map(t => {
      if (t.id !== taskId) return t;
      prevStatus = t.status;
      return { ...t, status: colId };
    }));

    const { error } = await supabase
      .from('kanban_tasks')
      .update({ status: colId })
      .eq('id', taskId);

    if (error) {
      console.error('Kanban drop error:', error);
      setTasks(prev => prev.map(t => t.id === taskId ? { ...t, status: prevStatus } : t));
    }
  }, []);

  // ── Adicionar tarefa ─────────────────────────────────────────────────────
  const handleAddTask = useCallback(async () => {
    if (!form.title.trim() || saving) return;
    setSaving(true);

    const { error } = await supabase
      .from('kanban_tasks')
      .insert({
        title:    form.title.trim(),
        client:   form.client.trim(),
        type:     form.type.trim(),
        assignee: form.assignee.trim(),
        priority: form.priority,
        due:      form.due || null,
        status:   'backlog',
      });

    if (error) console.error('Kanban insert error:', error);
    setModal(false);
    setForm(EMPTY_FORM);
    setSaving(false);
  }, [form, saving]);

  // ── Mover card entre colunas ─────────────────────────────────────────────
  const handleMoveCard = useCallback(async (taskId, direction) => {
    const colIds = COLUMNS.map(c => c.id);
    let nextStatus = null;

    setTasks(prev => prev.map(t => {
      if (t.id !== taskId) return t;
      const idx = colIds.indexOf(t.status);
      const next = colIds[idx + direction];
      if (next) { nextStatus = next; return { ...t, status: next }; }
      return t;
    }));

    if (nextStatus) {
      await supabase
        .from('kanban_tasks')
        .update({ status: nextStatus })
        .eq('id', taskId);
    }
  }, []);

  // ── Deletar card ─────────────────────────────────────────────────────────
  const handleDeleteTask = useCallback(async (taskId) => {
    if (!window.confirm('Excluir esta tarefa? A ação não pode ser desfeita.')) return;
    setTasks(prev => prev.filter(t => t.id !== taskId));
    await supabase.from('kanban_tasks').delete().eq('id', taskId);
  }, []);

  const totalByCol = (col) => tasks.filter(t => t.status === col).length;

  return (
    <div className="kanban-page">
      <div className="kanban-header">
        <div>
          <h1 className="kanban-title">Kanban Interno</h1>
          <p className="kanban-subtitle">Pipeline de produção da equipe — não visível ao cliente</p>
        </div>
        <button className="kanban-add-btn" onClick={() => setModal(true)}>
          <Plus size={16} />
          Nova Tarefa
        </button>
      </div>

      {loading ? (
        <div className="kanban-board">
          {COLUMNS.map(col => (
            <div key={col.id} className="kanban-col" style={{ '--col-color': col.color }}>
              <div className="kanban-col-header">
                <span className="kanban-col-dot" />
                <span className="kanban-col-label">{col.label}</span>
                <span className="kanban-col-count">0</span>
              </div>
              <div className="kanban-cards">
                {[1, 2].map(i => (
                  <div key={i} className="skeleton-kanban-card">
                    <div className="skeleton skeleton-kanban-title" />
                    <div className="skeleton skeleton-kanban-meta" />
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="kanban-board">
          {COLUMNS.map(col => (
            <div
              key={col.id}
              className={`kanban-col${dragOver === col.id ? ' kanban-col--over' : ''}`}
              style={{ '--col-color': col.color }}
              onDragOver={e => { e.preventDefault(); setDragOver(col.id); }}
              onDragLeave={() => setDragOver(null)}
              onDrop={() => handleDrop(col.id)}
            >
              <div className="kanban-col-header">
                <span className="kanban-col-dot" />
                <span className="kanban-col-label">{col.label}</span>
                <span className="kanban-col-count">{totalByCol(col.id)}</span>
              </div>

              <div className="kanban-cards">
                {tasks.filter(t => t.status === col.id).map(task => {
                  const { priority: effPriority, autoEscalated } = getEffectivePriority(task);
                  const p = PRIORITY_MAP[effPriority] || PRIORITY_MAP.medium;
                  const due = formatDue(task.due);
                  const colIdx = COLUMNS.findIndex(c => c.id === col.id);
                  return (
                    <div
                      key={task.id}
                      className={`kanban-card${due?.level === 'overdue' ? ' kanban-card--overdue' : ''}`}
                      draggable
                      onDragStart={() => handleDragStart(task.id)}
                      onDragEnd={() => setDragOver(null)}
                    >
                      <div className="kcard-top">
                        <span className="kcard-type">{task.type}</span>
                        <span
                          className={`kcard-priority${autoEscalated ? ' kcard-priority--escalated' : ''}`}
                          style={{ color: p.color, background: p.bg }}
                          title={autoEscalated ? `Escalada automaticamente pelo prazo (prioridade original: ${PRIORITY_MAP[task.priority]?.label})` : undefined}
                        >
                          {autoEscalated ? <Clock size={10} /> : <Flag size={10} />}
                          {p.label}
                        </span>
                      </div>

                      <p className="kcard-title">{task.title}</p>

                      <div className="kcard-meta">
                        {task.client && <span><Briefcase size={12} />{task.client}</span>}
                        {task.assignee && <span><User size={12} />{task.assignee}</span>}
                        {task.due && (
                          <span className={due?.level ? `kcard-due--${due.level}` : ''}>
                            <Calendar size={12} />
                            {due?.text || task.due}
                          </span>
                        )}
                      </div>

                      <div className="kcard-actions">
                        {colIdx > 0 && (
                          <button className="kcard-move kcard-move--left" title="Voltar" onClick={() => handleMoveCard(task.id, -1)}>
                            <ChevronDown size={13} style={{ transform: 'rotate(90deg)' }} />
                          </button>
                        )}
                        {colIdx < COLUMNS.length - 1 && (
                          <button className="kcard-move kcard-move--right" title="Avançar" onClick={() => handleMoveCard(task.id, 1)}>
                            <ChevronDown size={13} style={{ transform: 'rotate(-90deg)' }} />
                          </button>
                        )}
                        <button
                          className="kcard-move"
                          title="Excluir tarefa"
                          onClick={() => handleDeleteTask(task.id)}
                          style={{ marginLeft: 'auto', color: 'rgba(244,63,94,0.6)' }}
                        >
                          <X size={13} />
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}

      {modal && (
        <div className="kanban-overlay" onClick={() => setModal(false)}>
          <div role="dialog" aria-modal="true" aria-labelledby="modal-kanban-title" className="kanban-modal" onClick={e => e.stopPropagation()}>
            <div className="kanban-modal-header">
              <h2 id="modal-kanban-title">Nova Tarefa</h2>
              <button className="kanban-modal-close" aria-label="Fechar" onClick={() => setModal(false)}><X size={18} /></button>
            </div>

            <div className="kanban-modal-body">
              <div className="kform-row">
                <label className="kform-label">Título *</label>
                <input className="kform-input" placeholder="Ex: Landing Page cliente X" value={form.title} onChange={e => setForm(f => ({ ...f, title: e.target.value }))} />
              </div>
              <div className="kform-row">
                <label className="kform-label">Cliente</label>
                <input className="kform-input" placeholder="Nome do cliente" value={form.client} onChange={e => setForm(f => ({ ...f, client: e.target.value }))} />
              </div>
              <div className="kform-grid">
                <div className="kform-row">
                  <label className="kform-label">Tipo</label>
                  <input className="kform-input" placeholder="Landing Page, Social…" value={form.type} onChange={e => setForm(f => ({ ...f, type: e.target.value }))} />
                </div>
                <div className="kform-row">
                  <label className="kform-label">Responsável</label>
                  <input className="kform-input" placeholder="Nome" value={form.assignee} onChange={e => setForm(f => ({ ...f, assignee: e.target.value }))} />
                </div>
              </div>
              <div className="kform-grid">
                <div className="kform-row">
                  <label className="kform-label">Prioridade</label>
                  <div className="kpriority-selector">
                    {Object.entries(PRIORITY_MAP).map(([key, p]) => (
                      <button
                        key={key}
                        type="button"
                        className={`kpriority-opt${form.priority === key ? ' kpriority-opt--active' : ''}`}
                        style={{ '--p-color': p.color, '--p-bg': p.bg }}
                        onClick={() => setForm(f => ({ ...f, priority: key }))}
                      >
                        <Flag size={11} />
                        {p.label}
                      </button>
                    ))}
                  </div>
                </div>
                <div className="kform-row">
                  <label className="kform-label">Prazo</label>
                  <input className="kform-input" type="date" value={form.due} onChange={e => setForm(f => ({ ...f, due: e.target.value }))} />
                </div>
              </div>
            </div>

            <div className="kanban-modal-footer">
              <button className="kbtn-cancel" onClick={() => setModal(false)}>Cancelar</button>
              <button className="kbtn-submit" onClick={handleAddTask} disabled={saving || !form.title.trim()}>
                {saving ? 'Salvando...' : 'Criar Tarefa'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
