import { useEffect, useState } from 'react';
import { Users, Clock, CheckCircle2, Zap, FileText, MessageSquare } from 'lucide-react';
import { supabase } from '../../config/supabase';
import './Dashboard.css';

function formatRelative(isoString) {
  if (!isoString) return '';
  const diff = Date.now() - new Date(isoString).getTime();
  const min = Math.floor(diff / 60000);
  if (min < 60) return `Há ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `Há ${h}h`;
  return `Há ${Math.floor(h / 24)}d`;
}

export default function Dashboard() {
  const [stats, setStats] = useState({ clients: 0, pending: 0, approved: 0 });
  const [events, setEvents] = useState([]);
  const [loading, setLoading] = useState(true);

  const getGreeting = () => {
    const h = new Date().getHours();
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  };

  const currentDate = new Date().toLocaleDateString('pt-BR', {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
  });

  useEffect(() => {
    async function load() {
      const [
        { count: clients },
        { count: pending },
        { count: approved },
        { data: eventsData },
      ] = await Promise.all([
        supabase.from('profiles').select('*', { count: 'exact', head: true }),
        supabase.from('deliveries').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
        supabase.from('deliveries').select('*', { count: 'exact', head: true }).eq('status', 'approved'),
        supabase
          .from('portal_events')
          .select('id, event_type, metadata, created_at, profiles(full_name, company_name)')
          .order('created_at', { ascending: false })
          .limit(6),
      ]);

      setStats({ clients: clients ?? 0, pending: pending ?? 0, approved: approved ?? 0 });
      setEvents(eventsData || []);
      setLoading(false);
    }
    load();
  }, []);

  function eventLabel(ev) {
    const name = ev.profiles?.company_name || ev.profiles?.full_name || 'Cliente';
    const title = ev.metadata?.title || '';
    if (ev.event_type === 'delivery_approved') return { text: `"${title}" aprovado`, sub: name, icon: CheckCircle2, color: '#10b981' };
    if (ev.event_type === 'revision_requested') return { text: `Ajuste solicitado em "${title}"`, sub: name, icon: MessageSquare, color: '#f43f5e' };
    return { text: ev.event_type, sub: name, icon: FileText, color: '#8040F5' };
  }

  return (
    <div className="dashboard-container">
      <div className="dashboard-header">
        <h1>{getGreeting()}, Admin 👋</h1>
        <p style={{ textTransform: 'capitalize' }}>{currentDate}</p>
      </div>

      <div className="stats-grid">
        <div className="stat-card">
          <div className="stat-header">
            <span className="stat-title">Clientes Ativos</span>
            <div className="stat-icon" style={{ background: 'rgba(128,64,245,0.15)', color: 'var(--primary-color)' }}>
              <Users size={20} />
            </div>
          </div>
          <div className="stat-value" style={{ color: 'var(--primary-color)' }}>
            {loading ? '—' : stats.clients}
          </div>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>registros no portal</div>
        </div>

        <div className="stat-card">
          <div className="stat-header">
            <span className="stat-title">Entregas Pendentes</span>
            <div className="stat-icon" style={{ background: 'rgba(245,158,11,0.15)', color: 'var(--warning-color)' }}>
              <Clock size={20} />
            </div>
          </div>
          <div className="stat-value" style={{ color: 'var(--warning-color)' }}>
            {loading ? '—' : stats.pending}
          </div>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>aguardando aprovação</div>
        </div>

        <div className="stat-card">
          <div className="stat-header">
            <span className="stat-title">Aprovadas (Total)</span>
            <div className="stat-icon" style={{ background: 'rgba(16,185,129,0.15)', color: 'var(--success-color)' }}>
              <CheckCircle2 size={20} />
            </div>
          </div>
          <div className="stat-value" style={{ color: 'var(--success-color)' }}>
            {loading ? '—' : stats.approved}
          </div>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>entregas finalizadas</div>
        </div>
      </div>

      <div className="recent-activity animate-in" style={{ animationDelay: '0.1s' }}>
        <h2><Zap size={20} color="var(--accent-color)" /> Atividade Recente</h2>
        <div className="activity-list">
          {loading && (
            <div style={{ color: 'var(--text-secondary)', fontSize: 13, padding: '12px 0' }}>
              Carregando eventos...
            </div>
          )}
          {!loading && events.length === 0 && (
            <div style={{ color: 'var(--text-secondary)', fontSize: 13, padding: '12px 0' }}>
              Nenhuma atividade registrada ainda.
            </div>
          )}
          {events.map(ev => {
            const { text, sub, icon: Icon, color } = eventLabel(ev);
            return (
              <div key={ev.id} className="activity-item">
                <div className="activity-icon" style={{ background: `${color}18` }}>
                  <Icon size={18} color={color} />
                </div>
                <div className="activity-details">
                  <div className="activity-title">{text}</div>
                  <div className="activity-meta">{sub}</div>
                </div>
                <div className="activity-time">{formatRelative(ev.created_at)}</div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
