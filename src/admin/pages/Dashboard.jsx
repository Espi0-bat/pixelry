import React, { useEffect, useState } from 'react';
import { Users, Clock, CheckCircle2, Zap, FileText, MessageSquare, Target, Check, ChevronRight, FolderUp, Kanban, ArrowUpRight } from 'lucide-react';
import { motion } from 'framer-motion';
import { Link, useOutletContext } from 'react-router-dom';
import { supabase } from '../../config/supabase';
import EmployeeDashboard from './EmployeeDashboard';
import './Dashboard.css';

function getMonday(date) {
  const d = new Date(date);
  const day = d.getDay();
  d.setDate(d.getDate() + (day === 0 ? -6 : 1 - day));
  d.setHours(0, 0, 0, 0);
  return d;
}

function getWeekStart() {
  return getMonday(new Date()).toISOString().split('T')[0];
}

const prioColor = { high: '#f43f5e', medium: '#f59e0b', low: '#10b981' };

function formatRelative(isoString) {
  if (!isoString) return '';
  const diff = Date.now() - new Date(isoString).getTime();
  const min = Math.floor(diff / 60000);
  if (min < 60) return `Há ${min}min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `Há ${h}h`;
  return `Há ${Math.floor(h / 24)}d`;
}

function getGreeting() {
  const h = new Date().getHours();
  if (h < 12) return 'Bom dia';
  if (h < 18) return 'Boa tarde';
  return 'Boa noite';
}

function getUserName(email = '') {
  if (email.includes('moutinhoezer'))   return 'Ezer';
  if (email.includes('erickvin49'))     return 'CK';
  if (email.includes('sofiagramelich')) return 'Sofia';
  return email.split('@')[0];
}

const StatCard = React.memo(function StatCard({ title, value, sub, iconBg, iconColor, Icon, glowColor, loading, trend }) {
  const [hov, setHov] = useState(false);
  return (
    <motion.div
      className="stat-card"
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      animate={{
        y: hov ? -4 : 0,
        boxShadow: hov
          ? `0 20px 48px ${glowColor}28, 0 0 0 1px ${glowColor}30`
          : '0 0 0 0 transparent',
      }}
      transition={{ duration: 0.2 }}
    >
      <div className="stat-accent" style={{ background: `linear-gradient(90deg, ${glowColor}60, transparent)` }} />
      <div className="stat-header">
        <span className="stat-title">{title}</span>
        <motion.div
          className="stat-icon"
          style={{ background: iconBg, color: iconColor }}
          animate={{ scale: hov ? 1.12 : 1, rotate: hov ? 6 : 0 }}
          transition={{ duration: 0.2 }}
        >
          <Icon size={20} />
        </motion.div>
      </div>
      <motion.div
        className="stat-value"
        style={{ color: iconColor }}
        animate={{ scale: hov ? 1.04 : 1 }}
        transition={{ duration: 0.2 }}
      >
        {loading ? '—' : value}
      </motion.div>
      <div className="stat-sub">
        <span>{sub}</span>
        {trend && <span className="stat-trend" style={{ color: iconColor }}>{trend}</span>}
      </div>
    </motion.div>
  );
});

// Thin router — resolves role and delegates to the right dashboard
export default function Dashboard() {
  const ctx = useOutletContext() || {};
  if (ctx.userRole === 'employee') {
    return <EmployeeDashboard userProfile={ctx.userProfile} user={ctx.user} />;
  }
  return <AdminDashboard />;
}

function AdminDashboard() {
  const [stats, setStats]           = useState({ clients: 0, pending: 0, approved: 0 });
  const [events, setEvents]         = useState([]);
  const [loading, setLoading]       = useState(true);
  const [goals, setGoals]           = useState([]);
  const [goalsLoading, setGoalsLoading] = useState(true);
  const [userEmail, setUserEmail]   = useState('');

  const currentDate = new Date().toLocaleDateString('pt-BR', {
    weekday: 'long', day: 'numeric', month: 'long'
  });

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session?.user?.email) setUserEmail(session.user.email);
    });
  }, []);

  useEffect(() => {
    async function load() {
      const [
        { count: clients },
        { count: pending },
        { count: approved },
        { data: eventsData },
      ] = await Promise.all([
        supabase.from('profiles').select('*', { count: 'exact', head: true }).eq('role', 'client'),
        supabase.from('deliveries').select('*', { count: 'exact', head: true }).eq('status', 'pending'),
        supabase.from('deliveries').select('*', { count: 'exact', head: true }).eq('status', 'approved'),
        supabase
          .from('portal_events')
          .select('id, event_type, metadata, created_at, profiles!portal_events_client_id_profiles_fkey(full_name, company_name)')
          .order('created_at', { ascending: false })
          .limit(5),
      ]);
      setStats({ clients: clients ?? 0, pending: pending ?? 0, approved: approved ?? 0 });
      setEvents(eventsData || []);
      setLoading(false);
    }
    load();
  }, []);

  useEffect(() => {
    async function loadGoals() {
      const { data } = await supabase
        .from('weekly_goals')
        .select('*')
        .eq('week_start', getWeekStart())
        .order('created_at', { ascending: true });
      setGoals(data || []);
      setGoalsLoading(false);
    }
    loadGoals();
  }, []);

  function eventLabel(ev) {
    const name = ev.profiles?.company_name || ev.profiles?.full_name || 'Cliente';
    const title = ev.metadata?.title || '';
    if (ev.event_type === 'delivery_approved')   return { text: `"${title}" aprovado`, sub: name, icon: CheckCircle2, color: '#10b981' };
    if (ev.event_type === 'revision_requested')  return { text: `Ajuste solicitado em "${title}"`, sub: name, icon: MessageSquare, color: '#f43f5e' };
    return { text: ev.event_type, sub: name, icon: FileText, color: '#8040F5' };
  }

  const goalsDone  = goals.filter(g => g.status === 'done').length;
  const goalsTotal = goals.length;
  const goalsPct   = goalsTotal ? Math.round((goalsDone / goalsTotal) * 100) : 0;
  const userName   = getUserName(userEmail);

  return (
    <div className="dashboard-container">

      {/* ── Hero header ── */}
      <div className="dash-hero">
        <div className="dash-hero-left">
          <span className="dash-eyebrow">
            <span className="dash-eyebrow-dot" />
            PIXELRY ADMIN
          </span>
          <h1 className="dash-greeting">
            {getGreeting()},<br />
            <span className="dash-greeting-name">{userName}.</span>
          </h1>
          <p className="dash-date" style={{ textTransform: 'capitalize' }}>{currentDate}</p>
        </div>

        <div className="dash-hero-right">
          <div className="dash-quick-stats">
            <div className="dash-qs-item">
              <span className="dash-qs-val" style={{ color: 'var(--primary-color)' }}>
                {loading ? '—' : stats.clients}
              </span>
              <span className="dash-qs-label">Clientes</span>
            </div>
            <div className="dash-qs-sep" />
            <div className="dash-qs-item">
              <span className="dash-qs-val" style={{ color: '#f59e0b' }}>
                {loading ? '—' : stats.pending}
              </span>
              <span className="dash-qs-label">Pendentes</span>
            </div>
            <div className="dash-qs-sep" />
            <div className="dash-qs-item">
              <span className="dash-qs-val" style={{ color: goalsPct === 100 ? '#10b981' : 'var(--primary-color)' }}>
                {goalsLoading ? '—' : `${goalsPct}%`}
              </span>
              <span className="dash-qs-label">Metas</span>
            </div>
          </div>
        </div>
      </div>

      {/* ── Quick Actions ── */}
      <div className="dash-quick-actions">
        <Link to="/admin/clientes" className="quick-action">
          <Users size={17} />
          <span>Clientes</span>
          <ArrowUpRight size={13} className="qa-arrow" />
        </Link>
        <Link to="/admin/metas" className="quick-action">
          <Target size={17} />
          <span>Metas</span>
          <ArrowUpRight size={13} className="qa-arrow" />
        </Link>
        <Link to="/admin/kanban" className="quick-action">
          <Kanban size={17} />
          <span>Kanban</span>
          <ArrowUpRight size={13} className="qa-arrow" />
        </Link>
        <Link to="/admin/entregas" className="quick-action">
          <FolderUp size={17} />
          <span>Entregas</span>
          <ArrowUpRight size={13} className="qa-arrow" />
        </Link>
      </div>

      {/* ── Stats ── */}
      <div className="stats-grid">
        <StatCard
          title="Clientes Ativos"
          value={stats.clients}
          sub="registros no portal"
          iconBg="rgba(128,64,245,0.15)"
          iconColor="var(--primary-color)"
          glowColor="#8040F5"
          Icon={Users}
          loading={loading}
        />
        <StatCard
          title="Entregas Pendentes"
          value={stats.pending}
          sub="aguardando aprovação"
          iconBg="rgba(245,158,11,0.15)"
          iconColor="#f59e0b"
          glowColor="#f59e0b"
          Icon={Clock}
          loading={loading}
        />
        <StatCard
          title="Aprovadas"
          value={stats.approved}
          sub="entregas finalizadas"
          iconBg="rgba(16,185,129,0.15)"
          iconColor="#10b981"
          glowColor="#10b981"
          Icon={CheckCircle2}
          loading={loading}
        />
      </div>

      {/* ── Linha inferior: Metas + Atividade ── */}
      <div className="dash-bottom-row">

        {/* Widget Metas */}
        <div className="goals-widget">
          <div className="goals-widget-header">
            <h2><Target size={18} color="var(--primary-color)" /> Metas da semana</h2>
            <Link to="/admin/metas" className="goals-widget-link">
              Ver todas <ChevronRight size={14} />
            </Link>
          </div>

          {goalsLoading ? (
            <div className="goals-loading-text">Carregando...</div>
          ) : goals.length === 0 ? (
            <div className="goals-widget-empty">
              Nenhuma meta criada.{' '}
              <Link to="/admin/metas">Criar agora →</Link>
            </div>
          ) : (
            <>
              <div className="goals-widget-progress">
                <div className="goals-widget-progress-bar">
                  <motion.div
                    className="goals-widget-progress-fill"
                    initial={{ width: 0 }}
                    animate={{ width: `${goalsPct}%` }}
                    transition={{ duration: 0.6, ease: 'easeOut' }}
                    style={{ background: goalsPct === 100 ? '#10b981' : 'var(--grad)' }}
                  />
                </div>
                <span className="goals-widget-pct" style={{ color: goalsPct === 100 ? '#10b981' : 'var(--text-secondary)' }}>
                  {goalsDone}/{goalsTotal}
                </span>
              </div>

              <div className="goals-widget-list">
                {goals.slice(0, 5).map(g => {
                  const isDone = g.status === 'done';
                  return (
                    <div key={g.id} className={`goals-widget-item${isDone ? ' done' : ''}`}>
                      <div className="goals-widget-check" style={{
                        background: isDone ? 'var(--grad)' : 'transparent',
                        borderColor: isDone ? 'transparent' : `${prioColor[g.priority] ?? '#8040F5'}50`,
                      }}>
                        {isDone && <Check size={11} color="white" />}
                      </div>
                      <span className="goals-widget-title">{g.title}</span>
                      {g.assignee && (
                        <span className="goals-widget-assignee">{g.assignee}</span>
                      )}
                    </div>
                  );
                })}
                {goals.length > 5 && (
                  <div className="goals-more">+{goals.length - 5} mais</div>
                )}
              </div>
            </>
          )}
        </div>

        {/* Atividade Recente */}
        <div className="recent-activity">
          <h2><Zap size={18} color="#f59e0b" /> Atividade Recente</h2>

          <div className="activity-list">
            {loading && (
              <div className="activity-empty">Carregando eventos...</div>
            )}
            {!loading && events.length === 0 && (
              <div className="activity-empty">Nenhuma atividade registrada ainda.</div>
            )}

            <div style={{ position: 'relative' }}>
              {events.length > 1 && (
                <div className="activity-timeline-line" />
              )}
              {events.map((ev, idx) => {
                const { text, sub, icon: Icon, color } = eventLabel(ev);
                return (
                  <motion.div
                    key={ev.id}
                    className="activity-item"
                    initial={{ opacity: 0, x: -10 }}
                    animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: idx * 0.05, duration: 0.2 }}
                    style={{ position: 'relative', zIndex: 1 }}
                  >
                    <div style={{ position: 'relative', flexShrink: 0 }}>
                      <div className="activity-icon" style={{ background: `${color}18`, border: `1px solid ${color}30` }}>
                        <Icon size={15} color={color} />
                      </div>
                      {idx === 0 && (
                        <motion.div
                          animate={{ scale: [1, 1.6, 1], opacity: [0.8, 0, 0.8] }}
                          transition={{ duration: 2, repeat: Infinity }}
                          style={{
                            position: 'absolute', top: -2, right: -2,
                            width: 8, height: 8, borderRadius: '50%',
                            background: color, boxShadow: `0 0 6px ${color}`,
                          }}
                        />
                      )}
                    </div>
                    <div className="activity-details">
                      <div className="activity-title">{text}</div>
                      <div className="activity-meta">{sub}</div>
                    </div>
                    <div className="activity-time">{formatRelative(ev.created_at)}</div>
                  </motion.div>
                );
              })}
            </div>
          </div>
        </div>

      </div>
    </div>
  );
}
