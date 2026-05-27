import { useState, useEffect, useRef } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  ChevronLeft, Plus, Download, UploadCloud, Send,
  Mail, Phone, Globe, AtSign, User, StickyNote, Pencil, Save, X,
  Music2, Briefcase, Users,
} from 'lucide-react';
import { supabase } from '../../config/supabase';
import './ClienteDetalhes.css';

const STATUS_MAP = {
  pending:    { label: 'Aguardando Revisão', color: '#f59e0b' },
  approved:   { label: 'Aprovado',           color: '#10b981' },
  revision:   { label: 'Ajuste Solicitado',  color: '#f43f5e' },
  production: { label: 'Em Produção',        color: '#00D8FF' },
};

const EMPTY_CONTACT = {
  responsavel: '', emails: [], whatsapp: '',
  instagram: '', tiktok: '', linkedin: '', facebook: '', site: '', notas: '',
};

const OPTIONAL_FIELDS = ['whatsapp', 'instagram', 'tiktok', 'linkedin', 'facebook', 'site'];


export default function ClienteDetalhes() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [activeTab, setActiveTab] = useState('resumo');

  const [client, setClient] = useState(null);
  const [deliveries, setDeliveries] = useState([]);
  const [messages, setMessages] = useState([]);
  const [loadingClient, setLoadingClient] = useState(true);
  const [loadingDeliveries, setLoadingDeliveries] = useState(false);
  const [loadingMessages, setLoadingMessages] = useState(false);

  const [editMode, setEditMode] = useState(false);
  const [contactData, setContactData] = useState(EMPTY_CONTACT);
  const [emailsRaw, setEmailsRaw] = useState('');
  const [enabledFields, setEnabledFields] = useState({});
  const [pendingEnabled, setPendingEnabled] = useState({});
  const [savingContact, setSavingContact] = useState(false);

  const [chatMsg, setChatMsg] = useState('');
  const [sendingMsg, setSendingMsg] = useState(false);
  const chatBottomRef = useRef(null);

  useEffect(() => {
    async function load() {
      const { data } = await supabase
        .from('profiles')
        .select('id, full_name, company_name, email, avatar_url, contact_info')
        .eq('id', id)
        .single();

      if (data) {
        setClient(data);
        const ci = data.contact_info || {};
        const contact = {
          responsavel: ci.responsavel || data.full_name || '',
          emails: ci.emails || (data.email ? [data.email] : []),
          whatsapp: ci.whatsapp || '',
          instagram: ci.instagram || '',
          tiktok: ci.tiktok || '',
          linkedin: ci.linkedin || '',
          facebook: ci.facebook || '',
          site: ci.site || '',
          notas: ci.notas || '',
        };
        setContactData(contact);
        setEmailsRaw((contact.emails || []).join('\n'));
        const enabled = OPTIONAL_FIELDS.reduce((acc, f) => ({ ...acc, [f]: !!(contact[f]) }), {});
        setEnabledFields(enabled);
        setPendingEnabled(enabled);
      }
      setLoadingClient(false);
    }
    load();
  }, [id]);

  useEffect(() => {
    if (activeTab !== 'entregas') return;
    setLoadingDeliveries(true);
    supabase
      .from('deliveries')
      .select('id, title, status, type, created_at, file_url')
      .eq('client_id', id)
      .order('created_at', { ascending: false })
      .then(({ data }) => { setDeliveries(data || []); setLoadingDeliveries(false); });
  }, [activeTab, id]);

  useEffect(() => {
    if (activeTab !== 'chat') return;
    setLoadingMessages(true);
    supabase
      .from('messages')
      .select('id, content, from_client, created_at')
      .eq('client_id', id)
      .order('created_at', { ascending: true })
      .then(({ data }) => { setMessages(data || []); setLoadingMessages(false); });
  }, [activeTab, id]);

  useEffect(() => {
    chatBottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  const handleSaveContact = async () => {
    setSavingContact(true);
    const updatedEmails = emailsRaw.split('\n').map(e => e.trim()).filter(Boolean);
    const newContact = {
      ...contactData,
      emails: updatedEmails,
      ...Object.fromEntries(OPTIONAL_FIELDS.map(f => [f, pendingEnabled[f] ? contactData[f] : ''])),
    };
    await supabase
      .from('profiles')
      .update({ contact_info: newContact })
      .eq('id', id);
    setContactData(newContact);
    setEmailsRaw(updatedEmails.join('\n'));
    setEnabledFields(pendingEnabled);
    setEditMode(false);
    setSavingContact(false);
  };

  const handleCancelContact = () => {
    const ci = client?.contact_info || {};
    setContactData({
      responsavel: ci.responsavel || client?.full_name || '',
      emails: ci.emails || (client?.email ? [client.email] : []),
      whatsapp: ci.whatsapp || '',
      instagram: ci.instagram || '',
      tiktok: ci.tiktok || '',
      linkedin: ci.linkedin || '',
      facebook: ci.facebook || '',
      site: ci.site || '',
      notas: ci.notas || '',
    });
    setEmailsRaw((ci.emails || []).join('\n'));
    setPendingEnabled(enabledFields);
    setEditMode(false);
  };

  const sendMessage = async () => {
    const content = chatMsg.trim();
    if (!content || sendingMsg) return;
    setSendingMsg(true);
    setChatMsg('');
    const { data } = await supabase
      .from('messages')
      .insert({ client_id: id, content, from_client: false })
      .select('id, content, from_client, created_at')
      .single();
    if (data) setMessages(prev => [...prev, data]);
    setSendingMsg(false);
  };

  const handleNewDelivery = () => navigate('/admin/entregas');

  if (loadingClient) {
    return (
      <div style={{ padding: 48, color: 'var(--text-secondary)', fontSize: 14 }}>
        Carregando cliente...
      </div>
    );
  }

  if (!client) {
    return (
      <div style={{ padding: 48 }}>
        <button className="btn-back" onClick={() => navigate('/admin/clientes')}>
          <ChevronLeft size={20} /> Voltar
        </button>
        <p style={{ color: 'var(--text-secondary)', marginTop: 24 }}>Cliente não encontrado.</p>
      </div>
    );
  }

  const clientName = client.company_name || client.full_name || client.email || 'Sem nome';
  const pendingCount = deliveries.filter(d => d.status === 'pending').length;

  const SocialField = ({ field, label, icon, iconClass, children, linkView }) => {
    const isEnabled = editMode ? pendingEnabled[field] : enabledFields[field];
    if (!editMode && !isEnabled) return null;
    return (
      <div className={`info-item${!isEnabled && editMode ? ' info-item-disabled' : ''}`}>
        <div className={`info-icon-wrap ${iconClass}`}>{icon}</div>
        <div className="info-body">
          <div className="info-field-header">
            <label>{label}</label>
            {editMode && (
              <button
                className={`field-toggle ${isEnabled ? 'toggle-on' : 'toggle-off'}`}
                onClick={() => setPendingEnabled(prev => ({ ...prev, [field]: !prev[field] }))}
                type="button"
              >
                <span className="toggle-knob" />
              </button>
            )}
          </div>
          {isEnabled ? (editMode ? children : linkView) : (
            <span className="field-disabled-hint">Campo desativado</span>
          )}
        </div>
      </div>
    );
  };

  const renderResumo = () => (
    <div className="tab-pane animate-in">
      <div className="stats-grid">
        <div className="stat-card">
          <span className="stat-label">Entregas</span>
          <span className="stat-value">{deliveries.length}</span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Pendentes</span>
          <span className="stat-value warning">{pendingCount}</span>
        </div>
        <div className="stat-card">
          <span className="stat-label">Status</span>
          <span className="stat-value success">Ativo</span>
        </div>
      </div>
      <div className="recent-activity">
        <h3>E-mail de acesso ao portal</h3>
        <p style={{ color: 'var(--text-secondary)', fontSize: 14 }}>
          {client.email || '—'}
        </p>
      </div>
    </div>
  );

  const renderEntregas = () => (
    <div className="tab-pane animate-in">
      {loadingDeliveries && (
        <p style={{ color: 'var(--text-secondary)', fontSize: 13 }}>Carregando entregas...</p>
      )}
      <div className="entregas-list">
        {!loadingDeliveries && deliveries.length === 0 && (
          <p style={{ color: 'var(--text-secondary)', fontSize: 13 }}>
            Nenhuma entrega para este cliente ainda.
          </p>
        )}
        {deliveries.map(d => {
          const s = STATUS_MAP[d.status] || STATUS_MAP.production;
          return (
            <div key={d.id} className="entrega-card">
              <div className="entrega-info">
                <h4>{d.title}</h4>
                <p>{d.type} · {new Date(d.created_at).toLocaleDateString('pt-BR')}</p>
                <span className="badge" style={{ background: `${s.color}18`, color: s.color, border: `1px solid ${s.color}44` }}>
                  {s.label}
                </span>
              </div>
              <div className="entrega-actions">
                {d.file_url && (
                  <button className="btn-icon" onClick={() => window.open(d.file_url, '_blank')}>
                    <Download size={18} />
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );

  const renderDocumentos = () => (
    <div className="tab-pane animate-in">
      <div className="upload-area">
        <UploadCloud size={32} className="upload-icon" />
        <p>Contratos e documentos internos do cliente</p>
      </div>
      <p style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 12 }}>
        Use a página Entregas para enviar arquivos ao cliente.
      </p>
    </div>
  );

  const renderChat = () => (
    <div className="tab-pane chat-container animate-in">
      <div className="chat-messages">
        {loadingMessages && (
          <p style={{ color: 'var(--text-secondary)', fontSize: 13 }}>Carregando mensagens...</p>
        )}
        {!loadingMessages && messages.length === 0 && (
          <p style={{ color: 'var(--text-secondary)', fontSize: 13 }}>Nenhuma mensagem ainda.</p>
        )}
        {messages.map(m => (
          <div key={m.id} className={`message ${m.from_client ? 'received' : 'sent'}`}>
            {m.from_client && <div className="msg-avatar">{clientName.substring(0, 2).toUpperCase()}</div>}
            <div className="msg-bubble">
              <p>{m.content}</p>
              <span className="msg-time">
                {new Date(m.created_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}
              </span>
            </div>
          </div>
        ))}
        <div ref={chatBottomRef} />
      </div>
      <div className="chat-input-area">
        <input
          type="text"
          placeholder="Digite uma mensagem para o cliente..."
          className="chat-input"
          value={chatMsg}
          onChange={e => setChatMsg(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter') sendMessage(); }}
          disabled={sendingMsg}
        />
        <button className="btn-primary btn-send" onClick={sendMessage} disabled={sendingMsg || !chatMsg.trim()}>
          <Send size={18} />
        </button>
      </div>
    </div>
  );

  const renderInformacoes = () => (
    <div className="tab-pane animate-in">
      <div className="info-card-header">
        <h3>Dados de Contato</h3>
        {!editMode ? (
          <button className="btn-edit" onClick={() => setEditMode(true)}>
            <Pencil size={15} /> Editar
          </button>
        ) : (
          <div className="edit-actions">
            <button className="btn-cancel" onClick={handleCancelContact} disabled={savingContact}>
              <X size={15} /> Cancelar
            </button>
            <button className="btn-save" onClick={handleSaveContact} disabled={savingContact}>
              <Save size={15} /> {savingContact ? 'Salvando...' : 'Salvar'}
            </button>
          </div>
        )}
      </div>

      <div className="info-grid">
        <div className="info-item">
          <div className="info-icon-wrap info-icon-purple"><User size={18} /></div>
          <div className="info-body">
            <label>Responsável</label>
            {editMode ? (
              <input className="info-input" value={contactData.responsavel}
                onChange={e => setContactData(p => ({ ...p, responsavel: e.target.value }))} />
            ) : <span>{contactData.responsavel || '—'}</span>}
          </div>
        </div>

        <div className="info-item info-item-full">
          <div className="info-icon-wrap info-icon-blue"><Mail size={18} /></div>
          <div className="info-body">
            <label>E-mails Corporativos</label>
            {editMode ? (
              <textarea className="info-input info-textarea" value={emailsRaw}
                onChange={e => setEmailsRaw(e.target.value)}
                placeholder="Um e-mail por linha" rows={3} />
            ) : (
              <div className="email-list">
                {(contactData.emails || []).length > 0
                  ? contactData.emails.map((email, i) => (
                    <a key={i} href={`mailto:${email}`} className="email-badge">
                      <Mail size={13} /> {email}
                    </a>
                  ))
                  : <span>—</span>}
              </div>
            )}
          </div>
        </div>

        <SocialField field="whatsapp" label="WhatsApp"
          icon={<Phone size={18} />} iconClass="info-icon-green"
          linkView={contactData.whatsapp
            ? <a href={`https://wa.me/${contactData.whatsapp.replace(/\D/g, '')}`} target="_blank" rel="noreferrer" className="info-link">{contactData.whatsapp}</a>
            : <span>—</span>}>
          <input className="info-input" value={contactData.whatsapp}
            onChange={e => setContactData(p => ({ ...p, whatsapp: e.target.value }))} />
        </SocialField>

        <SocialField field="instagram" label="Instagram"
          icon={<AtSign size={18} />} iconClass="info-icon-pink"
          linkView={contactData.instagram
            ? <a href={`https://instagram.com/${contactData.instagram.replace('@', '')}`} target="_blank" rel="noreferrer" className="info-link">{contactData.instagram}</a>
            : <span>—</span>}>
          <input className="info-input" value={contactData.instagram}
            onChange={e => setContactData(p => ({ ...p, instagram: e.target.value }))} />
        </SocialField>

        <SocialField field="tiktok" label="TikTok"
          icon={<Music2 size={18} />} iconClass="info-icon-orange"
          linkView={contactData.tiktok
            ? <a href={`https://tiktok.com/@${contactData.tiktok.replace('@', '')}`} target="_blank" rel="noreferrer" className="info-link">{contactData.tiktok}</a>
            : <span>—</span>}>
          <input className="info-input" value={contactData.tiktok}
            onChange={e => setContactData(p => ({ ...p, tiktok: e.target.value }))} placeholder="@usuario" />
        </SocialField>

        <SocialField field="linkedin" label="LinkedIn"
          icon={<Briefcase size={18} />} iconClass="info-icon-blue"
          linkView={contactData.linkedin
            ? <a href={`https://linkedin.com/in/${contactData.linkedin}`} target="_blank" rel="noreferrer" className="info-link">linkedin.com/in/{contactData.linkedin}</a>
            : <span>—</span>}>
          <input className="info-input" value={contactData.linkedin}
            onChange={e => setContactData(p => ({ ...p, linkedin: e.target.value }))} />
        </SocialField>

        <SocialField field="facebook" label="Facebook"
          icon={<Users size={18} />} iconClass="info-icon-indigo"
          linkView={contactData.facebook
            ? <a href={`https://facebook.com/${contactData.facebook}`} target="_blank" rel="noreferrer" className="info-link">facebook.com/{contactData.facebook}</a>
            : <span>—</span>}>
          <input className="info-input" value={contactData.facebook}
            onChange={e => setContactData(p => ({ ...p, facebook: e.target.value }))} />
        </SocialField>

        <SocialField field="site" label="Site"
          icon={<Globe size={18} />} iconClass="info-icon-cyan"
          linkView={contactData.site
            ? <a href={contactData.site} target="_blank" rel="noreferrer" className="info-link">{contactData.site}</a>
            : <span>—</span>}>
          <input className="info-input" value={contactData.site}
            onChange={e => setContactData(p => ({ ...p, site: e.target.value }))} />
        </SocialField>

        <div className="info-item info-item-full">
          <div className="info-icon-wrap info-icon-yellow"><StickyNote size={18} /></div>
          <div className="info-body">
            <label>Notas Internas</label>
            {editMode ? (
              <textarea className="info-input info-textarea" value={contactData.notas}
                onChange={e => setContactData(p => ({ ...p, notas: e.target.value }))} rows={4} />
            ) : <span className="info-notas">{contactData.notas || '—'}</span>}
          </div>
        </div>
      </div>
    </div>
  );

  return (
    <div className="cliente-detalhes-container">
      <div className="cd-header">
        <div className="cd-header-left">
          <button className="btn-back" onClick={() => navigate('/admin/clientes')}>
            <ChevronLeft size={20} /> Voltar
          </button>
          <h1>{clientName}</h1>
        </div>
        <button className="btn-primary" onClick={handleNewDelivery}>
          <Plus size={18} /> Nova Entrega
        </button>
      </div>

      <div className="cd-tabs">
        {['informacoes', 'resumo', 'entregas', 'documentos', 'chat'].map(tab => (
          <button
            key={tab}
            className={`tab-btn ${activeTab === tab ? 'active' : ''}`}
            onClick={() => setActiveTab(tab)}
          >
            {tab === 'informacoes' && 'Informações'}
            {tab === 'resumo' && 'Resumo'}
            {tab === 'entregas' && 'Entregas'}
            {tab === 'documentos' && 'Documentos'}
            {tab === 'chat' && 'Chat'}
          </button>
        ))}
      </div>

      <div className="cd-content">
        {activeTab === 'informacoes' && renderInformacoes()}
        {activeTab === 'resumo' && renderResumo()}
        {activeTab === 'entregas' && renderEntregas()}
        {activeTab === 'documentos' && renderDocumentos()}
        {activeTab === 'chat' && renderChat()}
      </div>
    </div>
  );
}
