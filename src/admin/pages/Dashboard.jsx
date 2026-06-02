import React, { useEffect, useState } from 'react';
import { Users, Clock, CheckCircle2, Zap, FileText, MessageSquare } from 'lucide-react';
import { motion } from 'framer-motion';
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
