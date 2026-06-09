import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Target, Plus, ChevronLeft, ChevronRight, Check, Trash2, X, User, Flag, Tag } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { supabase } from '../../config/supabase';
import './Metas.css';

function getMonday(date) {
  const d = new Date(date);
  const day = d.getDay();
  d.setDate(d.getDate() + (day === 0 ? -6 : 1 - day));
  d.setHours(0, 0, 0, 0);
  return d;
}

function getWeekBounds(date) {
  const mon = getMonday(date);
  const sun = new Date(mon);
  sun.setDate(mon.getDate() + 6);
  const fmt = d => d.toISOString().split('T')[0];
  return { start: fmt(mon), end: fmt(sun) };
}

function fmtWeek(date) {
  const mon = getMonday(date);
  const sun = new Date(mon);
  sun.setDate(mon.getDate() + 6);
  const opts = { day: '2-digit', month: 'short' };
  return `${mon.toLocaleDateString('pt-BR', opts)} – ${sun.toLocaleDateString('pt-BR', opts)}`;
}

const CATEGORIES = ['Design', 'Vendas', 'Conteúdo', 'Financeiro', 'Outros'];
const PRIORITIES = [
  { value: 'high',   label: 'Alta'  },
  { value: 'medium', label: 'Média' },
  { value: 'low',    label: 'Baixa' },
];
const priorityMap = {
  high:   { label: 'Alta',  color: '#f43f5e' },
  medium: { label: 'Média', color: '#f59e0b' },
  low:    { label: 'Baixa', color: '#10b981' },
};

const EMPTY_FORM = { title: '', description: '', category: 'Design', assignee: '', priority: 'medium' };

export default function Metas() {
  const [week, setWeek]         = useState(new Date());
  const [goals, setGoals]       = useState([]);
  const [loading, setLoading]   = useState(true);
  const [showModal, setShowModal] = useState(false);
  const [form, setForm]         = useState(EMPTY_FORM);
  const [saving, setSaving]     = useState(false);
  const [deleteId, setDeleteId] = useState(null);
  const subRef = useRef(null);

  const { start, end } = getWeekBounds(week);
  const isCurrentWeek = getWeekBounds(new Date()).start === start;

  const loadGoals = useCallback(async () => {
    const { data } = await supabase
      .from('weekly_goals')
      .select('id, title, description, week_start, week_end, category, assignee, priority, status, created_at, updated_at')
      .eq('week_start', start)
      .order('created_at', { ascending: true });
    setGoals(data || []);
    setLoading(false);
  }, [start]);

  useEffect(() => {
    setLoading(true);
    loadGoals();

    if (subRef.current) subRef.current.unsubscribe();
    subRef.current = supabase
      .channel(`metas_${start}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'weekly_goals' }, loadGoals)
      .subscribe();

    return () => { if (subRef.current) subRef.current.unsubscribe(); };
  }, [loadGoals, start]);

  const done  = goals.filter(g => g.status === 'done').length;
  const total = goals.length;
  const progress = total ? Math.round((done / total) * 100) : 0;

  async function syncNotion(action, goal) {
    try {
      const { data: { session } } = await supabase.auth.getSession();
      await supabase.functions.invoke('sync-notion', {
        body: { action, goal },
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
    } catch (_) { /* sync falhou silenciosamente — dados já estão no Supabase */ }
  }

  async function toggleGoal(id, status) {
    const newStatus = status === 'done' ? 'pending' : 'done';
    await supabase.from('weekly_goals')
      .update({ status: newStatus, updated_at: new Date().toISOString() })
      .eq('id', id);
    const goal = goals.find(g => g.id === id);
    if (goal) syncNotion('upsert', { ...goal, status: newStatus });
  }

  async function deleteGoal(id) {
    const goal = goals.find(g => g.id === id);
    await supabase.from('weekly_goals').delete().eq('id', id);
    setDeleteId(null);
    if (goal) syncNotion('delete', goal);
  }

  async function handleCreate(e) {
    e.preventDefault();
    if (!form.title.trim()) return;
    setSaving(true);
    const { data: inserted } = await supabase.from('weekly_goals').insert({
      title: form.title.trim(),
      description: form.description.trim() || null,
      week_start: start,
      week_end: end,
      category: form.category,
      assignee: form.assignee.trim() || null,
      priority: form.priority,
    }).select().single();
    setShowModal(false);
    setForm(EMPTY_FORM);
    setSaving(false);
    if (inserted) syncNotion('upsert', inserted);
  }

  function shiftWeek(days) {
    const d = new Date(week);
    d.setDate(d.getDate() + days);
    setWeek(d);
  }

  return (
    <div className="metas-container">

      {/* Header */}
      <div className="metas-header">
        <div className="metas-title-wrap">
          <div className="metas-icon-bg"><Target size={22} /></div>
          <div>
            <h1>Metas Semanais</h1>
            <p>Objetivos e resultados da equipe Pixelry</p>
          </div>
        </div>
        <button className="btn-nova-meta" onClick={() => setShowModal(true)}>
          <Plus size={16} /> Nova Meta
        </button>
      </div>

      {/* Week navigator */}
      <div className="week-nav">
        <button className="week-btn" onClick={() => shiftWeek(-7)}><ChevronLeft size={18} /></button>
        <div className="week-label">
          <span className="week-range">{fmtWeek(week)}</span>
          {isCurrentWeek && <span className="week-badge">Semana atual</span>}
        </div>
        <button className="week-btn" onClick={() => shiftWeek(7)}><ChevronRight size={18} /></button>
      </div>

      {/* Progress bar */}
      <AnimatePresence>
        {total > 0 && (
          <motion.div className="meta-progress-wrap"
            initial={{ opacity: 0, y: -8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
            <div className="meta-progress-header">
              <span>{done} de {total} {total === 1 ? 'meta concluída' : 'metas concluídas'}</span>
              <span className="meta-progress-pct"
                style={{ color: progress === 100 ? '#10b981' : 'var(--text-secondary)' }}>
                {progress}%
              </span>
            </div>
            <div className="meta-progress-track">
              <motion.div className="meta-progress-fill"
                initial={{ width: 0 }}
                animate={{ width: `${progress}%` }}
                transition={{ duration: 0.6, ease: 'easeOut' }}
                style={{ background: progress === 100 ? '#10b981' : 'var(--grad)' }}
              />
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Goals list */}
      {loading ? (
        <div className="metas-loading">Carregando metas...</div>
      ) : goals.length === 0 ? (
        <motion.div className="metas-empty" initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
          <Target size={36} style={{ opacity: 0.25, marginBottom: 12 }} />
          <div>Nenhuma meta para essa semana.</div>
          <div style={{ fontSize: 12, marginTop: 6, color: 'var(--text-secondary)' }}>
            Clique em "Nova Meta" para começar.
          </div>
        </motion.div>
      ) : (
        <motion.div className="goals-list" layout>
          <AnimatePresence mode="popLayout">
            {goals.map(goal => {
              const p = priorityMap[goal.priority] ?? priorityMap.medium;
              const isDone = goal.status === 'done';
              return (
                <motion.div key={goal.id} className={`goal-card${isDone ? ' done' : ''}`}
                  layout
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, scale: 0.96 }}
                  transition={{ duration: 0.18 }}
                >
                  <button className={`goal-check${isDone ? ' checked' : ''}`}
                    onClick={() => toggleGoal(goal.id, goal.status)}>
                    {isDone && <Check size={13} />}
                  </button>

                  <div className="goal-body">
                    <div className="goal-title">{goal.title}</div>
                    {goal.description && <div className="goal-desc">{goal.description}</div>}
                    <div className="goal-tags">
                      {goal.category && <span className="goal-tag cat">{goal.category}</span>}
                      <span className="goal-tag prio"
                        style={{ color: p.color, borderColor: `${p.color}40`, background: `${p.color}12` }}>
                        <Flag size={10} /> {p.label}
                      </span>
                      {goal.assignee && (
                        <span className="goal-tag assign"><User size={10} /> {goal.assignee}</span>
                      )}
                    </div>
                  </div>

                  <button className="goal-delete" onClick={() => setDeleteId(goal.id)} title="Excluir">
                    <Trash2 size={15} />
                  </button>
                </motion.div>
              );
            })}
          </AnimatePresence>
        </motion.div>
      )}

      {/* Modal — Nova Meta */}
      <AnimatePresence>
        {showModal && (
          <motion.div className="modal-overlay"
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
            onClick={e => e.target === e.currentTarget && setShowModal(false)}>
            <motion.div
              role="dialog"
              aria-modal="true"
              aria-labelledby="modal-meta-title"
              className="modal-card"
              initial={{ opacity: 0, scale: 0.94, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.94, y: 20 }}
              transition={{ type: 'spring', stiffness: 300, damping: 28 }}>

              <div className="modal-header">
                <div className="modal-title-wrap">
                  <div className="modal-icon-bg"><Target size={20} /></div>
                  <div>
                    <h2 id="modal-meta-title">Nova Meta</h2>
                    <p>{fmtWeek(week)}</p>
                  </div>
                </div>
                <button className="modal-close" aria-label="Fechar" onClick={() => setShowModal(false)}><X size={18} /></button>
              </div>

              <form className="modal-form" onSubmit={handleCreate}>
                <div className="modal-field">
                  <label>Título <span className="required">*</span></label>
                  <input type="text" placeholder="Ex: Fechar 2 novos clientes"
                    value={form.title} onChange={e => setForm(f => ({ ...f, title: e.target.value }))} required />
                </div>
                <div className="modal-field">
                  <label>Descrição</label>
                  <textarea placeholder="Detalhes opcionais..." rows={2}
                    value={form.description} onChange={e => setForm(f => ({ ...f, description: e.target.value }))} />
                </div>
                <div className="modal-row">
                  <div className="modal-field">
                    <label><Tag size={13} /> Categoria</label>
                    <select value={form.category} onChange={e => setForm(f => ({ ...f, category: e.target.value }))}>
                      {CATEGORIES.map(c => <option key={c}>{c}</option>)}
                    </select>
                  </div>
                  <div className="modal-field">
                    <label><Flag size={13} /> Prioridade</label>
                    <select value={form.priority} onChange={e => setForm(f => ({ ...f, priority: e.target.value }))}>
                      {PRIORITIES.map(p => <option key={p.value} value={p.value}>{p.label}</option>)}
                    </select>
                  </div>
                </div>
                <div className="modal-field">
                  <label><User size={13} /> Responsável</label>
                  <input type="text" placeholder="Ex: Ezer, CK, Sofia"
                    value={form.assignee} onChange={e => setForm(f => ({ ...f, assignee: e.target.value }))} />
                </div>

                <div className="modal-actions">
                  <button type="button" className="btn-cancel" onClick={() => setShowModal(false)} disabled={saving}>
                    Cancelar
                  </button>
                  <button type="submit" className="btn-invite" disabled={saving || !form.title.trim()}>
                    {saving ? <><span className="spinner" /> Salvando...</> : <><Plus size={15} /> Criar Meta</>}
                  </button>
                </div>
              </form>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Modal — Confirmar exclusão */}
      <AnimatePresence>
        {deleteId && (
          <motion.div className="modal-overlay"
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
            onClick={e => e.target === e.currentTarget && setDeleteId(null)}>
            <motion.div className="modal-card confirm-card"
              initial={{ opacity: 0, scale: 0.94 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.94 }}
              transition={{ type: 'spring', stiffness: 300, damping: 28 }}>
              <Trash2 size={28} color="#f43f5e" style={{ marginBottom: 12 }} />
              <h3>Excluir meta?</h3>
              <p style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 8, textAlign: 'center' }}>
                Essa ação não pode ser desfeita.
              </p>
              <div className="modal-actions" style={{ marginTop: 24 }}>
                <button className="btn-cancel" onClick={() => setDeleteId(null)}>Cancelar</button>
                <button className="btn-delete" onClick={() => deleteGoal(deleteId)}>Excluir</button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

    </div>
  );
}
