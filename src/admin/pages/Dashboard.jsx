import React, { useEffect, useState } from 'react';
import { Users, Clock, CheckCircle2, Zap, FileText, MessageSquare, Target, Check, ChevronRight } from 'lucide-react';
import { motion } from 'framer-motion';
import { Link } from 'react-router-dom';
import { supabase } from '../../config/supabase';
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
  if (min < 60) return `Há ${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `Há ${h}h`;
  return `Há ${Math.floor(h / 24)}d`;
}

const StatCard = React.memo(function StatCard({ title, value, sub, iconBg, iconColor, Icon, glowColor, loading }) {
  const [hov, setHov] = useState(false);
  return (
    <motion.div
      className="stat-card"
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      animate={{
        y: hov ? -4 : 0,
        boxShadow: hov
          ? `0 20px 48px ${glowColor}28, 0 0 0 1px ${glowColor}44`
          : '0 0 0 0 transparent',
        borderColor: hov ? `${glowColor}44` : undefined,
      }}
      transition={{ duration: 0.2 }}
    >
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
      <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>{sub}</div>
    </motion.div>
  );
});

export default function Dashboard() {
  const [stats, setStats] = useState({ clients: 0, pending: 0, approved: 0 });
  const [events, setEvents] = useState([]);
  const [loading, setLoading] = useState(true);
  const [goals, setGoals] = useState([]);
  const [goalsLoading, setGoalsLoading] = useState(true);

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
          iconColor="var(--warning-color)"
          glowColor="#f59e0b"
          Icon={Clock}
          loading={loading}
        />
        <StatCard
          title="Aprovadas (Total)"
          value={stats.approved}
          sub="entregas finalizadas"
          iconBg="rgba(16,185,129,0.15)"
          iconColor="var(--success-color)"
          glowColor="#10b981"
          Icon={CheckCircle2}
          loading={loading}
        />
      </div>

      {/* Widget Metas */}
      <div className="goals-widget animate-in" style={{ animationDelay: '0.05s' }}>
        <div className="goals-widget-header">
          <h2><Target size={20} color="var(--primary-color)" /> Metas desta semana</h2>
          <Link to="/admin/metas" className="goals-widget-link">
            Ver todas <ChevronRight size={15} />
          </Link>
        </div>

        {goalsLoading ? (
          <div style={{ color: 'var(--text-secondary)', fontSize: 13 }}>Carregando...</div>
        ) : goals.length === 0 ? (
          <div className="goals-widget-empty">
            Nenhuma meta criada para essa semana.{' '}
            <Link to="/admin/metas">Criar agora →</Link>
          </div>
        ) : (
          <>
            {/* Barra de progresso */}
            {(() => {
              const done  = goals.filter(g => g.status === 'done').length;
              const total = goals.length;
              const pct   = total ? Math.round((done / total) * 100) : 0;
              return (
                <div className="goals-widget-progress">
                  <div className="goals-widget-progress-bar">
                    <motion.div
                      className="goals-widget-progress-fill"
                      initial={{ width: 0 }}
                      animate={{ width: `${pct}%` }}
                      transition={{ duration: 0.6, ease: 'easeOut' }}
                      style={{ background: pct === 100 ? '#10b981' : 'var(--grad)' }}
                    />
                  </div>
                  <span className="goals-widget-pct" style={{ color: pct === 100 ? '#10b981' : 'var(--text-secondary)' }}>
                    {done}/{total}
                  </span>
                </div>
              );
            })()}

            {/* Checklist */}
            <div className="goals-widget-list">
              {goals.slice(0, 5).map(g => {
                const isDone = g.status === 'done';
                return (
                  <div key={g.id} className={`goals-widget-item${isDone ? ' done' : ''}`}>
                    <div className="goals-widget-check" style={{
                      background: isDone ? 'var(--grad)' : 'transparent',
                      borderColor: isDone ? 'transparent' : `${prioColor[g.priority] ?? '#8040F5'}60`,
                      boxShadow: isDone ? '0 2px 8px rgba(128,64,245,0.35)' : 'none',
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
                <div style={{ fontSize: 12, color: 'var(--text-secondary)', paddingLeft: 4, marginTop: 4 }}>
                  +{goals.length - 5} mais…
                </div>
              )}
            </div>
          </>
        )}
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

          {/* Timeline visual */}
          <div style={{ position: 'relative' }}>
            {events.length > 1 && (
              <div style={{
                position: 'absolute',
                left: 17,
                top: 18,
                bottom: 18,
                width: 2,
                background: 'linear-gradient(to bottom, rgba(128,64,245,0.4), rgba(0,216,255,0.1))',
                borderRadius: 2,
                zIndex: 0,
              }} />
            )}

            {events.map((ev, idx) => {
              const { text, sub, icon: Icon, color } = eventLabel(ev);
              const isNew = idx === 0;
              return (
                <motion.div
                  key={ev.id}
                  className="activity-item"
                  initial={{ opacity: 0, x: -12 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: 0, duration: 0.2 }}
                  style={{ position: 'relative', zIndex: 1 }}
                >
                  <div style={{ position: 'relative', flexShrink: 0 }}>
                    <div
                      className="activity-icon"
                      style={{ background: `${color}18`, border: `1px solid ${color}30` }}
                    >
                      <Icon size={16} color={color} />
                    </div>
                    {isNew && (
                      <motion.div
                        animate={{ scale: [1, 1.6, 1], opacity: [0.8, 0, 0.8] }}
                        transition={{ duration: 2, repeat: Infinity }}
                        style={{
                          position: 'absolute',
                          top: -2, right: -2,
                          width: 8, height: 8,
                          borderRadius: '50%',
                          background: color,
                          boxShadow: `0 0 6px ${color}`,
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
  );
}
