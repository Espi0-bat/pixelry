import React, { useState, useEffect, useRef, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  ChevronLeft, Plus, Download, UploadCloud, Send,
  Mail, Phone, Globe, AtSign, User, StickyNote, Pencil, Save, X,
  Music2, Briefcase, Users, Link2, HardDrive, FileText, Image, File, Trash2,
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

// Componente isolado para o input do chat — evita re-render da página inteira ao digitar
const ChatInput = React.memo(function ChatInput({ onSend, disabled }) {
  const [value, setValue] = useState('');
  const handleSend = () => {
    const content = value.trim();
    if (!content || disabled) return;
    setValue('');
    onSend(content);
  };
  return (
    <div className="chat-input-area">
      <input
        type="text"
        placeholder="Digite uma mensagem para o cliente..."
        className="chat-input"
        value={value}
        onChange={e => setValue(e.target.value)}
        onKeyDown={e => { if (e.key === 'Enter') handleSend(); }}
        disabled={disabled}
      />
      <button className="btn-primary btn-send" onClick={handleSend} disabled={disabled || !value.trim()}>
        <Send size={18} />
      </button>
    </div>
  );
});

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

  const [clientFiles, setClientFiles] = useState([]);
  const [loadingFiles, setLoadingFiles] = useState(false);
  const [driveLinks, setDriveLinks] = useState([]);
  const [driveLinkForm, setDriveLinkForm] = useState({ label: '', url: '' });
  const [savingDriveLink, setSavingDriveLink] = useState(false);

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
        setDriveLinks(ci.drive_links || []);
      }
      setLoadingClient(false);
    }
    load();
  }, [id]);

  useEffect(() => {
    let mounted = true;
    supabase
      .from('deliveries')
      .select('id, title, status, type, created_at, file_url')
      .eq('client_id', id)
      .order('created_at', { ascending: false })
      .then(({ data }) => { if (mounted) { setDeliveries(data || []); setLoadingDeliveries(false); } });
    return () => { mounted = false; };
  }, [id]);

  useEffect(() => {
    if (activeTab !== 'documentos') return;
    let mounted = true;
    setLoadingFiles(true);
    supabase
      .from('client_files')
      .select('id, name, type, file_url, size_label, created_at')
      .eq('client_id', id)
      .order('created_at', { ascending: false })
      .then(({ data }) => { if (mounted) { setClientFiles(data || []); setLoadingFiles(false); } });
    return () => { mounted = false; };
  }, [activeTab, id]);

  useEffect(() => {
    if (activeTab !== 'chat') return;
    let mounted = true;
    setLoadingMessages(true);
    supabase
      .from('messages')
      .select('id, content, from_client, created_at')
      .eq('client_id', id)
      .order('created_at', { ascending: true })
      .then(({ data }) => { if (mounted) { setMessages(data || []); setLoadingMessages(false); } });
    return () => { mounted = false; };
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
      .update({ contact_info: { ...newContact, drive_links: driveLinks } })
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

  const sendMessage = useCallback(async (content) => {
    if (!content || sendingMsg) return;
    setSendingMsg(true);
    const { data } = await supabase
      .from('messages')
      .insert({ client_id: id, content, from_client: false })
      .select('id, content, from_client, created_at')
      .single();
    if (data) setMessages(prev => [...prev, data]);
    setSendingMsg(false);
  }, [id, sendingMsg]);

  const addDriveLink = async () => {
    if (!driveLinkForm.url.trim()) return;
    setSavingDriveLink(true);
    const newLinks = [...driveLinks, { id: Date.now(), label: driveLinkForm.label.trim() || driveLinkForm.url.trim(), url: driveLinkForm.url.trim() }];
    const ci = client?.contact_info || {};
    await supabase.from('profiles').update({ contact_info: { ...ci, drive_links: newLinks } }).eq('id', id);
    setDriveLinks(newLinks);
    setDriveLinkForm({ label: '', url: '' });
    setSavingDriveLink(false);
  };

  const removeDriveLink = async (linkId) => {
    const newLinks = driveLinks.filter(l => l.id !== linkId);
    const ci = client?.contact_info || {};
    await supabase.from('profiles').update({ contact_info: { ...ci, drive_links: newLinks } }).eq('id', id);
    setDriveLinks(newLinks);
  };

  const getFileIcon = (name) => {
    const ext = (name || '').split('.').pop().toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg'].includes(ext)) return Image;
    if (['pdf', 'doc', 'docx', 'txt'].includes(ext)) return FileText;
    return File;
  };

  const getDriveLinkMeta = (url) => {
    if (url.includes('drive.google')) return { icon: HardDrive, color: '#4285F4' };
    if (url.includes('dropbox')) return { icon: HardDrive, color: '#0061FF' };
    if (url.includes('notion')) return { icon: StickyNote, color: '#fff' };
    return { icon: Link2, color: 'var(--primary-color)' };
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
      <h3 className="docs-section-title">Arquivos Enviados pelo Cliente</h3>
      {loadingFiles ? (
        <p style={{ color: 'var(--text-secondary)', fontSize: 13 }}>Carregando arquivos...</p>
      ) : clientFiles.length === 0 ? (
        <div className="upload-area">
          <UploadCloud size={32} className="upload-icon" />
          <p>Nenhum arquivo enviado pelo cliente ainda.</p>
        </div>
      ) : (
        <div className="docs-list">
          {clientFiles.map(f => {
            const Icon = getFileIcon(f.name);
            return (
              <div key={f.id} className="doc-item">
                <div className="doc-icon"><Icon size={22} /></div>
                <div className="doc-info">
                  <h4>{f.name}</h4>
                  <span>{f.type}{f.size_label ? ` · ${f.size_label}` : ''} · {new Date(f.created_at).toLocaleDateString('pt-BR')}</span>
                </div>
                <button className="btn-icon" title="Abrir arquivo" onClick={() => window.open(f.file_url, '_blank')}>
                  <Download size={16} />
                </button>
              </div>
            );
          })}
        </div>
      )}
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
      <ChatInput onSend={sendMessage} disabled={sendingMsg} />
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

      {/* Links de Pastas */}
      <div className="info-card-header" style={{ marginTop: 40 }}>
        <h3>Links de Pastas</h3>
      </div>
      {driveLinks.length > 0 && (
        <div className="drive-links-list">
          {driveLinks.map(link => {
            const { icon: DIcon, color } = getDriveLinkMeta(link.url);
            return (
              <div key={link.id} className="drive-link-item">
                <div className="drive-link-icon" style={{ color }}>
                  <DIcon size={20} />
                </div>
                <a href={link.url} target="_blank" rel="noreferrer" className="drive-link-label">
                  {link.label}
                </a>
                <button className="btn-icon" style={{ width: 32, height: 32 }} title="Remover" onClick={() => removeDriveLink(link.id)}>
                  <Trash2 size={14} />
                </button>
              </div>
            );
          })}
        </div>
      )}
      {driveLinks.length === 0 && (
        <p style={{ color: 'var(--text-secondary)', fontSize: 13, marginBottom: 16 }}>Nenhum link adicionado.</p>
      )}
      <div className="drive-link-form">
        <input
          className="info-input"
          placeholder="Nome (ex: Fotos do Projeto)"
          value={driveLinkForm.label}
          onChange={e => setDriveLinkForm(p => ({ ...p, label: e.target.value }))}
        />
        <input
          className="info-input"
          placeholder="URL (ex: https://drive.google.com/...)"
          value={driveLinkForm.url}
          onChange={e => setDriveLinkForm(p => ({ ...p, url: e.target.value }))}
          onKeyDown={e => { if (e.key === 'Enter') addDriveLink(); }}
        />
        <button className="btn-primary" onClick={addDriveLink} disabled={savingDriveLink || !driveLinkForm.url.trim()}>
          <Plus size={15} /> {savingDriveLink ? 'Salvando...' : 'Adicionar'}
        </button>
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
