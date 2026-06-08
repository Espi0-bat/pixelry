import React, { useEffect, useRef, useState, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Send, Headphones, Loader2, ArrowLeft } from 'lucide-react';
import { supabase } from '../../config/supabase';
import './InternalMessages.css';

function formatTime(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  const now = new Date();
  const isToday = d.toDateString() === now.toDateString();
  if (isToday) return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }) + ' ' +
    d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}

function renderMsgContent(content) {
  const urlRegex = /(https?:\/\/[^\s]+)/g;
  const imageExts = /\.(png|jpg|jpeg|gif|webp|svg)(\?.*)?$/i;
  const parts = content.split(urlRegex);
  return parts.map((part, i) => {
    if (urlRegex.test(part)) {
      urlRegex.lastIndex = 0;
      if (imageExts.test(part)) {
        return (
          <a key={i} href={part} target="_blank" rel="noopener noreferrer">
            <img
              src={part}
              alt="anexo"
              style={{ maxWidth: '100%', maxHeight: 220, borderRadius: 8, display: 'block', marginTop: 6, cursor: 'pointer' }}
            />
          </a>
        );
      }
      const fileName = decodeURIComponent(part.split('/').pop().split('?')[0]);
      return (
        <a key={i} href={part} target="_blank" rel="noopener noreferrer"
          style={{ color: 'var(--primary)', textDecoration: 'underline', wordBreak: 'break-all', fontSize: 13 }}>
          📎 {fileName}
        </a>
      );
    }
    const text = part.replace(/📎 Arquivo anexado: [^\n]*/g, '').trim();
    return text ? <span key={i} style={{ whiteSpace: 'pre-wrap' }}>{text}</span> : null;
  });
}

function getInitials(profile) {
  const name = profile?.full_name || profile?.email || '?';
  return name.slice(0, 1).toUpperCase();
}

export default function Suporte() {
  const [contacts, setContacts]         = useState([]);
  const [selected, setSelected]         = useState(null);
  const [messages, setMessages]         = useState([]);
  const [newMsg, setNewMsg]             = useState('');
  const [loadingContacts, setLoadingContacts] = useState(true);
  const [loadingMsgs, setLoadingMsgs]   = useState(false);
  const [sending, setSending]           = useState(false);
  const [showContacts, setShowContacts] = useState(true);
  const bottomRef  = useRef(null);
  const channelRef = useRef(null);

  const openContact = useCallback(async (contact) => {
    setSelected(contact);
    setShowContacts(false);
    setLoadingMsgs(true);
    setMessages([]);

    const { data } = await supabase
      .from('messages')
      .select('id, content, from_client, created_at')
      .eq('client_id', contact.id)
      .order('created_at', { ascending: true });

    setMessages(data || []);
    setLoadingMsgs(false);
    setContacts(prev => prev.map(c => c.id === contact.id ? { ...c, unread: 0 } : c));
  }, []);

  // Load clients that have conversations
  useEffect(() => {
    async function load() {
      const { data: msgs } = await supabase
        .from('messages')
        .select('client_id, content, from_client, created_at')
        .order('created_at', { ascending: false });

      if (!msgs?.length) { setLoadingContacts(false); return; }

      const byClient = {};
      for (const msg of msgs) {
        if (!byClient[msg.client_id]) {
          byClient[msg.client_id] = { lastMsg: msg, unread: 0 };
        }
        if (msg.from_client) byClient[msg.client_id].unread++;
      }

      const clientIds = Object.keys(byClient);
      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, full_name, email, avatar_url')
        .in('id', clientIds);

      const list = (profiles || [])
        .map(p => ({
          ...p,
          lastMsg: byClient[p.id]?.lastMsg,
          unread:  byClient[p.id]?.unread || 0,
        }))
        .sort((a, b) =>
          new Date(b.lastMsg?.created_at || 0) - new Date(a.lastMsg?.created_at || 0)
        );

      setContacts(list);
      setLoadingContacts(false);
      if (list.length === 1) openContact(list[0]);
    }
    load();
  }, [openContact]);

  // Realtime — new client messages
  useEffect(() => {
    if (channelRef.current) supabase.removeChannel(channelRef.current);

    const channel = supabase
      .channel('suporte-admin-inbox')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'messages',
      }, (payload) => {
        const msg = payload.new;
        if (!msg.from_client) return;

        setSelected(prev => {
          if (prev?.id === msg.client_id) {
            setMessages(m => [...m, msg]);
          } else {
            setContacts(cs => {
              const exists = cs.some(c => c.id === msg.client_id);
              if (exists) {
                return cs.map(c =>
                  c.id === msg.client_id
                    ? { ...c, unread: (c.unread || 0) + 1, lastMsg: msg }
                    : c
                );
              }
              // New client appeared — add placeholder and reload
              supabase.from('profiles')
                .select('id, full_name, email, avatar_url')
                .eq('id', msg.client_id)
                .single()
                .then(({ data: p }) => {
                  if (p) setContacts(cs2 => [{ ...p, lastMsg: msg, unread: 1 }, ...cs2]);
                });
              return cs;
            });
          }
          return prev;
        });
      })
      .subscribe();

    channelRef.current = channel;
    return () => { supabase.removeChannel(channel); };
  }, []);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  async function handleSend(e) {
    e.preventDefault();
    if (!newMsg.trim() || !selected || sending) return;
    setSending(true);
    const content = newMsg.trim();
    setNewMsg('');
    const { data } = await supabase
      .from('messages')
      .insert({ client_id: selected.id, content, from_client: false })
      .select('id, content, from_client, created_at')
      .single();
    if (data) setMessages(prev => [...prev, data]);
    setSending(false);
  }

  return (
    <div className="chat-layout">

      {/* ── Contacts sidebar ── */}
      <div className={`chat-contacts${!showContacts ? ' mobile-hidden' : ''}`}>
        <div className="chat-contacts-header">
          <h2 className="chat-title">Suporte</h2>
          <span className="chat-role-badge">Clientes</span>
        </div>

        {loadingContacts ? (
          <div className="chat-state"><Loader2 size={16} className="spin" /> Carregando...</div>
        ) : contacts.length === 0 ? (
          <div className="chat-state">Nenhuma conversa ainda.</div>
        ) : contacts.map(c => (
          <button
            key={c.id}
            className={`contact-row${selected?.id === c.id ? ' active' : ''}`}
            onClick={() => openContact(c)}
          >
            <div className="contact-avatar">
              {c.avatar_url ? <img src={c.avatar_url} alt={c.full_name} /> : getInitials(c)}
            </div>
            <div className="contact-info">
              <div className="contact-name">{c.full_name || c.email}</div>
              <div className="contact-role" style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 150 }}>
                {c.lastMsg?.content?.slice(0, 35) || 'Sem mensagens'}
              </div>
            </div>
            {c.unread > 0 && (
              <span className="contact-unread">{c.unread}</span>
            )}
          </button>
        ))}
      </div>

      {/* ── Chat area ── */}
      <div className={`chat-area${showContacts ? ' mobile-hidden' : ''}`}>
        {!selected ? (
          <div className="chat-placeholder">
            <Headphones size={40} strokeWidth={1.5} className="chat-placeholder-icon" />
            <p>Selecione uma conversa para responder.</p>
          </div>
        ) : (
          <>
            <div className="chat-header">
              <button className="chat-back-btn" onClick={() => setShowContacts(true)} aria-label="Voltar">
                <ArrowLeft size={16} />
              </button>
              <div className="chat-header-avatar">
                {selected.avatar_url
                  ? <img src={selected.avatar_url} alt={selected.full_name} />
                  : getInitials(selected)
                }
              </div>
              <div>
                <div className="chat-header-name">{selected.full_name || selected.email}</div>
                <div className="chat-header-role">Cliente</div>
              </div>
            </div>

            <div className="chat-messages">
              {loadingMsgs ? (
                <div className="chat-state center"><Loader2 size={18} className="spin" /> Carregando...</div>
              ) : messages.length === 0 ? (
                <div className="chat-state center">Nenhuma mensagem ainda.</div>
              ) : (
                <AnimatePresence initial={false}>
                  {messages.map((msg, idx) => {
                    const isMe = !msg.from_client;
                    const prevMsg = messages[idx - 1];
                    const showTime = !prevMsg ||
                      new Date(msg.created_at) - new Date(prevMsg.created_at) > 5 * 60 * 1000;
                    return (
                      <React.Fragment key={msg.id}>
                        {showTime && (
                          <div className="msg-time-divider">{formatTime(msg.created_at)}</div>
                        )}
                        <motion.div
                          className={`msg-bubble-wrap${isMe ? ' me' : ''}`}
                          initial={{ opacity: 0, y: 6 }}
                          animate={{ opacity: 1, y: 0 }}
                          transition={{ duration: 0.18 }}
                        >
                          <div className={`msg-bubble${isMe ? ' me' : ''}`}>
                            {renderMsgContent(msg.content)}
                          </div>
                        </motion.div>
                      </React.Fragment>
                    );
                  })}
                </AnimatePresence>
              )}
              <div ref={bottomRef} />
            </div>

            <form className="chat-input-bar" onSubmit={handleSend}>
              <input
                className="chat-input"
                type="text"
                placeholder="Responder ao cliente..."
                value={newMsg}
                onChange={e => setNewMsg(e.target.value)}
                autoFocus
              />
              <button type="submit" className="chat-send" disabled={!newMsg.trim() || sending}>
                {sending ? <Loader2 size={16} className="spin" /> : <Send size={16} />}
              </button>
            </form>
          </>
        )}
      </div>
    </div>
  );
}
