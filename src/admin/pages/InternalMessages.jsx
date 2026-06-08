import React, { useEffect, useRef, useState, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Send, MessageSquare, Loader2, ArrowLeft } from 'lucide-react';
import { useOutletContext } from 'react-router-dom';
import { supabase, hasMinRole } from '../../config/supabase';
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

function getInitials(profile) {
  const name = profile?.full_name || profile?.email || '?';
  return name.slice(0, 1).toUpperCase();
}

export default function InternalMessages() {
  const ctx = useOutletContext() || {};
  const userRole = ctx.userRole;
  const authUser = ctx.user;

  const [contacts, setContacts]       = useState([]);
  const [selected, setSelected]       = useState(null);
  const [messages, setMessages]       = useState([]);
  const [newMsg, setNewMsg]           = useState('');
  const [loadingContacts, setLoadingContacts] = useState(true);
  const [loadingMsgs, setLoadingMsgs] = useState(false);
  const [sending, setSending]         = useState(false);
  const [unread, setUnread]           = useState({});
  const [showContacts, setShowContacts] = useState(true);
  const bottomRef = useRef(null);
  const channelRef = useRef(null);

  const openContact = useCallback(async (contact) => {
    setSelected(contact);
    setShowContacts(false);
    setLoadingMsgs(true);
    setMessages([]);

    // Mark received messages as read
    if (authUser?.id) {
      await supabase
        .from('internal_messages')
        .update({ read_at: new Date().toISOString() })
        .eq('from_id', contact.id)
        .eq('to_id', authUser.id)
        .is('read_at', null);
      setUnread(prev => ({ ...prev, [contact.id]: 0 }));
    }

    const { data } = await supabase
      .from('internal_messages')
      .select('*')
      .or(`and(from_id.eq.${authUser.id},to_id.eq.${contact.id}),and(from_id.eq.${contact.id},to_id.eq.${authUser.id})`)
      .order('created_at', { ascending: true });
    setMessages(data || []);
    setLoadingMsgs(false);
  }, [authUser?.id]);

  useEffect(() => {
    if (!authUser?.id) return;
    let query = supabase
      .from('profiles')
      .select('id, full_name, email, avatar_url, job_title, role');

    const isAdminLevel = hasMinRole(userRole, 'manager');
    if (isAdminLevel) {
      query = query.in('role', ['employee', 'manager', 'super_admin']).neq('id', authUser.id);
    } else {
      query = query.in('role', ['manager', 'super_admin']);
    }

    query.then(({ data }) => {
      setContacts(data || []);
      setLoadingContacts(false);
      if (data?.length === 1) openContact(data[0]);
    });
  }, [authUser?.id, userRole, openContact]);

  // Realtime subscription
  useEffect(() => {
    if (!authUser?.id) return;
    if (channelRef.current) supabase.removeChannel(channelRef.current);

    const channel = supabase
      .channel(`internal-messages-${authUser.id}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'internal_messages',
      }, (payload) => {
        const msg = payload.new;
        const myId = authUser.id;
        const isRelevant = (msg.from_id === myId || msg.to_id === myId);
        if (!isRelevant) return;

        const otherId = msg.from_id === myId ? msg.to_id : msg.from_id;

        setSelected(prev => {
          if (prev?.id === otherId || msg.from_id === myId) {
            setMessages(m => [...m, msg]);
          } else {
            setUnread(u => ({ ...u, [otherId]: (u[otherId] || 0) + 1 }));
          }
          return prev;
        });
      })
      .subscribe();

    channelRef.current = channel;
    return () => { supabase.removeChannel(channel); };
  }, [authUser?.id]);

  // Scroll to bottom when messages update
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  async function handleSend(e) {
    e.preventDefault();
    if (!newMsg.trim() || !selected || !authUser?.id || sending) return;
    setSending(true);
    const content = newMsg.trim();
    setNewMsg('');
    await supabase.from('internal_messages').insert({
      from_id: authUser.id,
      to_id: selected.id,
      content,
    });
    setSending(false);
  }

  return (
    <div className="chat-layout">

      {/* ── Contacts sidebar ── */}
      <div className={`chat-contacts${!showContacts ? ' mobile-hidden' : ''}`}>
        <div className="chat-contacts-header">
          <h2 className="chat-title">Mensagens</h2>
          <span className="chat-role-badge">
            {hasMinRole(userRole, 'manager') ? 'Equipe' : 'Suporte'}
          </span>
        </div>

        {loadingContacts ? (
          <div className="chat-state"><Loader2 size={16} className="spin" /> Carregando...</div>
        ) : contacts.length === 0 ? (
          <div className="chat-state">Nenhum contato.</div>
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
              <div className="contact-role">{c.job_title || (hasMinRole(c.role, 'manager') ? 'Admin' : 'Funcionário')}</div>
            </div>
            {unread[c.id] > 0 && (
              <span className="contact-unread">{unread[c.id]}</span>
            )}
          </button>
        ))}
      </div>

      {/* ── Chat area ── */}
      <div className={`chat-area${showContacts ? ' mobile-hidden' : ''}`}>
        {!selected ? (
          <div className="chat-placeholder">
            <MessageSquare size={40} strokeWidth={1.5} className="chat-placeholder-icon" />
            <p>Selecione uma conversa para começar.</p>
          </div>
        ) : (
          <>
            {/* Chat header */}
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
                <div className="chat-header-role">{selected.job_title || (hasMinRole(selected.role, 'manager') ? 'Admin' : 'Funcionário')}</div>
              </div>
            </div>

            {/* Messages */}
            <div className="chat-messages">
              {loadingMsgs ? (
                <div className="chat-state center"><Loader2 size={18} className="spin" /> Carregando...</div>
              ) : messages.length === 0 ? (
                <div className="chat-state center">Nenhuma mensagem ainda. Comece a conversa!</div>
              ) : (
                <AnimatePresence initial={false}>
                  {messages.map((msg, idx) => {
                    const isMe = msg.from_id === authUser.id;
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
                            {msg.content}
                          </div>
                        </motion.div>
                      </React.Fragment>
                    );
                  })}
                </AnimatePresence>
              )}
              <div ref={bottomRef} />
            </div>

            {/* Input */}
            <form className="chat-input-bar" onSubmit={handleSend}>
              <input
                className="chat-input"
                type="text"
                placeholder="Escreva uma mensagem..."
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
