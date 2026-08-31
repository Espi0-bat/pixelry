import { useEffect, useRef, useState } from 'react';
import { Camera, LogOut, User, X, KeyRound } from 'lucide-react';
import { supabase } from '../../config/supabase';
import ChangePassword from '../../components/ChangePassword';
import './ProfilePanel.css';

export default function ProfilePanel({ user, avatarUrl, onAvatarUpdate, onLogout, userRole }) {
  const [open, setOpen]         = useState(false);
  const [uploading, setUploading] = useState(false);
  const [preview, setPreview]   = useState(avatarUrl);
  const [showChangePw, setShowChangePw] = useState(false);
  const panelRef = useRef(null);
  const fileRef  = useRef(null);

  const initials = user?.email
    ? user.email.substring(0, 2).toUpperCase()
    : 'AD';

  const displayName = (() => {
    const e = user?.email || '';
    if (e.includes('moutinhoezer')) return 'Ezer';
    if (e.includes('erickvin49'))   return 'CK';
    if (e.includes('sofiagramelich')) return 'Sofia';
    return e.split('@')[0];
  })();

  const roleLabel = {
    super_admin: 'CEO · Pixelry',
    manager:     'Gerente',
    employee:    'Designer',
  }[userRole] || 'Admin';

  // Sync preview when prop changes
  useEffect(() => { setPreview(avatarUrl); }, [avatarUrl]);

  // Close on outside click
  useEffect(() => {
    function handler(e) {
      if (panelRef.current && !panelRef.current.contains(e.target)) setOpen(false);
    }
    if (open) document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  async function handleUpload(e) {
    const file = e.target.files?.[0];
    if (!file || !user?.id) return;
    setUploading(true);

    // Mostra preview local imediatamente
    const localUrl = URL.createObjectURL(file);
    setPreview(localUrl);

    const ext  = file.name.split('.').pop().toLowerCase();
    const path = `${user.id}.${ext}`;

    const { error: upErr } = await supabase.storage
      .from('avatars')
      .upload(path, file, { upsert: true, contentType: file.type });

    if (upErr) {
      console.error('Upload error:', upErr);
      setPreview(avatarUrl);
      setUploading(false);
      return;
    }

    const { data: { publicUrl } } = supabase.storage
      .from('avatars')
      .getPublicUrl(path);

    const bustedUrl = `${publicUrl}?t=${Date.now()}`;

    const { error: dbErr } = await supabase
      .from('profiles')
      .update({ avatar_url: publicUrl, updated_at: new Date().toISOString() })
      .eq('id', user.id);

    if (dbErr) {
      console.error('Erro ao salvar avatar:', dbErr);
      await supabase.storage.from('avatars').remove([path]);
      setPreview(avatarUrl);
      setUploading(false);
      return;
    }

    setPreview(bustedUrl);
    onAvatarUpdate?.(bustedUrl);
    setUploading(false);
  }

  return (
    <div className="pp-wrap" ref={panelRef}>
      {/* Avatar trigger */}
      <button
        className="pp-trigger"
        onClick={() => setOpen(o => !o)}
        aria-label="Abrir perfil"
        aria-expanded={open}
      >
        {preview ? (
          <img src={preview} alt={displayName} className="pp-avatar-img" />
        ) : (
          <div className="pp-avatar-initials">{initials}</div>
        )}
        <span className="pp-trigger-dot" />
      </button>

      {/* Dropdown panel */}
      {open && (
        <div className="pp-panel">
          <button className="pp-close" onClick={() => setOpen(false)}>
            <X size={14} />
          </button>

          {/* Header do perfil */}
          <div className="pp-header">
            <div className="pp-photo-area">
              {preview ? (
                <img src={preview} alt={displayName} className="pp-photo" />
              ) : (
                <div className="pp-photo pp-photo-fallback">{initials}</div>
              )}
              <button
                className={`pp-upload-btn${uploading ? ' uploading' : ''}`}
                onClick={() => fileRef.current?.click()}
                disabled={uploading}
                title="Trocar foto"
              >
                {uploading ? (
                  <span className="pp-spinner" />
                ) : (
                  <Camera size={14} />
                )}
              </button>
              <input
                ref={fileRef}
                type="file"
                accept="image/jpeg,image/png,image/webp"
                className="pp-file-input"
                onChange={handleUpload}
              />
            </div>

            <div className="pp-info">
              <span className="pp-name">{displayName}</span>
              <span className="pp-email">{user?.email}</span>
              <span className="pp-role">
                <User size={10} /> {roleLabel}
              </span>
            </div>
          </div>

          <div className="pp-divider" />

          <button className="pp-action" onClick={() => { setOpen(false); setShowChangePw(true); }}>
            <KeyRound size={14} /> Alterar senha
          </button>

          <button className="pp-logout" onClick={onLogout}>
            <LogOut size={14} /> Sair do painel
          </button>
        </div>
      )}

      {showChangePw && <ChangePassword onClose={() => setShowChangePw(false)} />}
    </div>
  );
}
