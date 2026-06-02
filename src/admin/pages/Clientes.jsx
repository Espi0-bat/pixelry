import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, ChevronRight, CheckCircle, Clock, UserPlus } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { supabase } from '../../config/supabase';
import './Clientes.css';

const ClientCard = React.memo(function ClientCard({ client, onOpen }) {
  const [hov, setHov] = useState(false);
  const initials = client.name.substring(0, 2).toUpperCase();

  return (
    <motion.div
      className="cliente-card"
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, scale: 0.96 }}
      transition={{ duration: 0.2 }}
      style={{
        background: hov
          ? 'rgba(128,64,245,0.07)'
          : 'rgba(20,20,48,0.55)',
        backdropFilter: 'blur(16px)',
        WebkitBackdropFilter: 'blur(16px)',
        border: `1px solid ${hov ? 'rgba(128,64,245,0.35)' : 'rgba(255,255,255,0.07)'}`,
        boxShadow: hov ? '0 16px 48px rgba(128,64,245,0.14)' : '0 2px 16px rgba(0,0,0,0.15)',
        transform: hov ? 'translateY(-3px)' : 'none',
        transition: 'background 0.2s, border-color 0.2s, box-shadow 0.2s, transform 0.2s',
      }}
    >
      <div className="cliente-info">
        <motion.div
          className="cliente-avatar"
          animate={{ scale: hov ? 1.08 : 1 }}
          transition={{ duration: 0.2 }}
        >
          {initials}
        </motion.div>
        <div className="cliente-details">
          <h3>{client.name}</h3>
          {client.email && (
            <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginBottom: 4 }}>
              {client.email}
            </div>
          )}
          <div className="cliente-stats">
            <span className="stat-item">
              <CheckCircle size={14} color="var(--success-color)" /> {client.activeProjects} entregas
            </span>
            {client.pendingDeliveries > 0 && (
              <span className="stat-item warning">
                <Clock size={14} /> {client.pendingDeliveries} pendentes
              </span>
            )}
          </div>
        </div>
      </div>

      <button className="btn-open-cliente" onClick={() => onOpen(client.id)}>
        Abrir Cliente <ChevronRight size={16} />
      </button>
    </motion.div>
  );
});

export default function Clientes() {
  const navigate = useNavigate();
  const [searchTerm, setSearchTerm] = useState('');
  const [clients, setClients] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function load() {
      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, full_name, company_name, email')
        .order('full_name', { ascending: true });

      if (!profiles?.length) { setLoading(false); return; }

      const ids = profiles.map(p => p.id);

      const { data: deliveryCounts } = await supabase
        .from('deliveries')
        .select('client_id, status')
        .in('client_id', ids);

      const countMap = {};
      for (const d of deliveryCounts || []) {
        if (!countMap[d.client_id]) countMap[d.client_id] = { total: 0, pending: 0 };
        countMap[d.client_id].total++;
        if (d.status === 'pending') countMap[d.client_id].pending++;
      }

      setClients(profiles.map(p => ({
        id: p.id,
        name: p.company_name || p.full_name || p.email || 'Sem nome',
        email: p.email || '',
        activeProjects: countMap[p.id]?.total ?? 0,
        pendingDeliveries: countMap[p.id]?.pending ?? 0,
        status: 'Ativo',
      })));
      setLoading(false);
    }
    load();
  }, []);

  const filtered = clients.filter(c =>
    c.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    c.email.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="clientes-container">
      <div className="clientes-header">
        <div>
          <h1>Gerenciar Clientes</h1>
          <p>Selecione um cliente para visualizar ou enviar entregas.</p>
        </div>

        <div className="search-wrapper">
          <Search size={18} className="search-icon" />
          <input
            type="text"
            placeholder="Buscar cliente..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="search-input"
          />
        </div>
      </div>

      {loading && (
        <div style={{ color: 'var(--text-secondary)', fontSize: 13, padding: '24px 0' }}>
          Carregando clientes...
        </div>
      )}

      <motion.div className="clientes-grid" layout>
        <AnimatePresence mode="popLayout">
          {filtered.map(client => (
            <ClientCard
              key={client.id}
              client={client}
              onOpen={(id) => navigate(`/admin/clientes/${id}`)}
            />
          ))}

          {!loading && filtered.length === 0 && (
            <motion.div
              key="empty"
              className="empty-state"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              style={{ gridColumn: '1/-1', textAlign: 'center', padding: '48px 0', color: 'var(--text-secondary)' }}
            >
              <UserPlus size={32} style={{ marginBottom: 12, opacity: 0.4 }} />
              <div>{searchTerm ? 'Nenhum cliente encontrado.' : 'Nenhum cliente cadastrado ainda.'}</div>
              <div style={{ fontSize: 12, marginTop: 6 }}>
                {!searchTerm && 'Clientes aparecem aqui após criarem conta no portal.'}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
    </div>
  );
}
