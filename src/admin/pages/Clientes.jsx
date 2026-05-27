import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, ChevronRight, CheckCircle, Clock, UserPlus } from 'lucide-react';
import { supabase } from '../../config/supabase';
import './Clientes.css';

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

      <div className="clientes-grid">
        {filtered.map(client => (
          <div key={client.id} className="cliente-card animate-in">
            <div className="cliente-info">
              <div className="cliente-avatar">
                {client.name.substring(0, 2).toUpperCase()}
              </div>
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

            <button className="btn-open-cliente" onClick={() => navigate(`/admin/clientes/${client.id}`)}>
              Abrir Cliente <ChevronRight size={16} />
            </button>
          </div>
        ))}

        {!loading && filtered.length === 0 && (
          <div className="empty-state animate-in" style={{ gridColumn: '1/-1', textAlign: 'center', padding: '48px 0', color: 'var(--text-secondary)' }}>
            <UserPlus size={32} style={{ marginBottom: 12, opacity: 0.4 }} />
            <div>{searchTerm ? 'Nenhum cliente encontrado.' : 'Nenhum cliente cadastrado ainda.'}</div>
            <div style={{ fontSize: 12, marginTop: 6 }}>
              {!searchTerm && 'Clientes aparecem aqui após criarem conta no portal.'}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
