import { useState, useRef } from 'react';
import { Plus, X, Calendar, User, Briefcase, Flag, ChevronDown } from 'lucide-react';
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

const initialTasks = [
  { id: 1, title: 'Landing Page Casarão dos Pireneus', client: 'Casarão dos Pireneus', type: 'Landing Page',  assignee: 'Ana',    priority: 'high',   due: '2025-06-10', status: 'design'  },
  { id: 2, title: 'Posts Instagram — Junho',           client: 'Boutique Zen',         type: 'Social Media', assignee: 'Carlos', priority: 'medium', due: '2025-06-01', status: 'copy'    },
  { id: 3, title: 'Identidade Visual Completa',        client: 'Studio K',             type: 'Branding',     assignee: 'Ana',    priority: 'high',   due: '2025-06-20', status: 'backlog' },
  { id: 4, title: 'Email Marketing — Campanha Verão',  client: 'Casarão dos Pireneus', type: 'E-mail',       assignee: 'Marcos', priority: 'low',    due: '2025-06-15', status: 'review'  },
  { id: 5, title: 'Redesign do Site',                  client: 'Studio K',             type: 'Website',      assignee: 'Carlos', priority: 'high',   due: '2025-05-30', status: 'done'    },
  { id: 6, title: 'Vídeo Institucional — Roteiro',     client: 'Boutique Zen',         type: 'Vídeo',        assignee: 'Marcos', priority: 'medium', due: '2025-06-25', status: 'backlog' },
];

const EMPTY_FORM = { title: '', client: '', type: '', assignee: '', priority: 'medium', due: '' };

export default function Kanban() {
  const [tasks, setTasks]       = useState(initialTasks);
  const [modal, setModal]       = useState(false);
  const [form, setForm]         = useState(EMPTY_FORM);
  const [dragOver, setDragOver] = useState(null);
  const dragId = useRef(null);

  function handleDragStart(id) {
    dragId.current = id;
  }

  function handleDrop(colId) {
    if (dragId.current == null) return;
    setTasks(prev => prev.map(t => t.id === dragId.current ? { ...t, status: colId } : t));
    dragId.current = null;
    setDragOver(null);
  }

  function handleAddTask() {
    if (!form.title.trim()) return;
    setTasks(prev => [...prev, { ...form, id: Date.now(), status: 'backlog' }]);
    setModal(false);
    setForm(EMPTY_FORM);
  }

  function handleMoveCard(taskId, direction) {
    const colIds = COLUMNS.map(c => c.id);
    setTasks(prev => prev.map(t => {
      if (t.id !== taskId) return t;
      const idx = colIds.indexOf(t.status);
      const next = colIds[idx + direction];
      return next ? { ...t, status: next } : t;
    }));
  }

  const totalByCol = col => tasks.filter(t => t.status === col).length;

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
                const p = PRIORITY_MAP[task.priority];
                const colIdx = COLUMNS.findIndex(c => c.id === col.id);
                return (
                  <div
                    key={task.id}
                    className="kanban-card"
                    draggable
                    onDragStart={() => handleDragStart(task.id)}
                    onDragEnd={() => setDragOver(null)}
                  >
                    <div className="kcard-top">
                      <span className="kcard-type">{task.type}</span>
                      <span className="kcard-priority" style={{ color: p.color, background: p.bg }}>
                        <Flag size={10} />
                        {p.label}
                      </span>
                    </div>

                    <p className="kcard-title">{task.title}</p>

                    <div className="kcard-meta">
                      <span><Briefcase size={12} />{task.client}</span>
                      <span><User size={12} />{task.assignee}</span>
                      {task.due && <span><Calendar size={12} />{task.due}</span>}
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
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>

      {modal && (
        <div className="kanban-overlay" onClick={() => setModal(false)}>
          <div className="kanban-modal" onClick={e => e.stopPropagation()}>
            <div className="kanban-modal-header">
              <h2>Nova Tarefa</h2>
              <button className="kanban-modal-close" onClick={() => setModal(false)}><X size={18} /></button>
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
                  <select className="kform-input" value={form.priority} onChange={e => setForm(f => ({ ...f, priority: e.target.value }))}>
                    <option value="low">Baixa</option>
                    <option value="medium">Média</option>
                    <option value="high">Alta</option>
                  </select>
                </div>
                <div className="kform-row">
                  <label className="kform-label">Prazo</label>
                  <input className="kform-input" type="date" value={form.due} onChange={e => setForm(f => ({ ...f, due: e.target.value }))} />
                </div>
              </div>
            </div>

            <div className="kanban-modal-footer">
              <button className="kbtn-cancel" onClick={() => setModal(false)}>Cancelar</button>
              <button className="kbtn-submit" onClick={handleAddTask}>Criar Tarefa</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
