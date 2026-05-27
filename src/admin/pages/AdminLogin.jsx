import { useRef, useState } from 'react';
import { shatterElement } from '../utils/shatterEffect';
import { supabase, ADMIN_EMAIL } from '../../config/supabase';
import './AdminLogin.css';

export default function AdminLogin({ onLogin }) {
  const cardRef = useRef(null);
  const [isLoggingIn, setIsLoggingIn] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [mode, setMode] = useState('login');

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (isLoggingIn) return;
    setError('');

    if (email !== ADMIN_EMAIL) {
      setError('Acesso restrito à equipe Pixelry.');
      return;
    }

    setIsLoggingIn(true);

    let authError = null;

    if (mode === 'login') {
      const { data, error: signInError } = await supabase.auth.signInWithPassword({ email, password });
      authError = signInError;
      if (!signInError && data.user) {
        await new Promise(r => setTimeout(r, 200));
        if (cardRef.current) {
          shatterElement(cardRef.current, {
            particleSize: 10,
            totalDuration: 1400,
            flashDuration: 180,
            onComplete: () => onLogin(data.user),
          });
        } else {
          onLogin(data.user);
        }
        return;
      }
    } else {
      const { data, error: signUpError } = await supabase.auth.signUp({ email, password });
      authError = signUpError;
      if (!signUpError && data.user) {
        await new Promise(r => setTimeout(r, 200));
        if (cardRef.current) {
          shatterElement(cardRef.current, {
            particleSize: 10,
            totalDuration: 1400,
            flashDuration: 180,
            onComplete: () => onLogin(data.user),
          });
        } else {
          onLogin(data.user);
        }
        return;
      }
    }

    setError(authError?.message || 'Erro ao autenticar. Tente novamente.');
    setIsLoggingIn(false);
  };

  return (
    <div className="login-container">
      <div className="login-bg-grid"></div>

      <div
        className={`login-card animate-in${isLoggingIn ? ' login-card--shattering' : ''}`}
        ref={cardRef}
      >
        <div className="login-header">
          <img src="/novalogo.jpg" alt="Pixelry" className="login-logo" />
          <h1 className="login-title">Pixelry Admin</h1>
          <p className="login-subtitle">
            {mode === 'login' ? 'Acesso restrito à equipe' : 'Criar conta de administrador'}
          </p>
        </div>

        <form onSubmit={handleSubmit}>
          <div className="login-form-group">
            <label className="login-label">E-mail corporativo</label>
            <input
              type="email"
              placeholder="admin@pixelry.com.br"
              className="login-input"
              required
              disabled={isLoggingIn}
              value={email}
              onChange={e => setEmail(e.target.value)}
            />
          </div>
          <div className="login-form-group" style={{ marginBottom: error ? '16px' : '32px' }}>
            <label className="login-label">Senha</label>
            <input
              type="password"
              placeholder="••••••••"
              className="login-input"
              required
              disabled={isLoggingIn}
              value={password}
              onChange={e => setPassword(e.target.value)}
              minLength={6}
            />
          </div>

          {error && (
            <div style={{
              marginBottom: 20,
              padding: '10px 14px',
              borderRadius: 8,
              background: 'rgba(244,63,94,0.1)',
              border: '1px solid rgba(244,63,94,0.3)',
              color: '#f43f5e',
              fontSize: 13,
              fontFamily: 'DM Sans, sans-serif',
            }}>
              {error}
            </div>
          )}

          <button
            type="submit"
            className={`login-button${isLoggingIn ? ' login-button--loading' : ''}`}
            disabled={isLoggingIn}
          >
            {isLoggingIn ? (
              <span className="login-button-dots">
                <span></span><span></span><span></span>
              </span>
            ) : mode === 'login' ? 'Entrar no Painel' : 'Criar conta e entrar'}
          </button>
        </form>

        <button
          type="button"
          onClick={() => { setMode(m => m === 'login' ? 'register' : 'login'); setError(''); }}
          style={{
            marginTop: 20,
            width: '100%',
            background: 'transparent',
            border: 'none',
            color: 'rgba(255,255,255,0.35)',
            fontSize: 12,
            cursor: 'pointer',
            fontFamily: 'DM Sans, sans-serif',
          }}
        >
          {mode === 'login'
            ? 'Primeira vez? Criar conta de administrador'
            : 'Já tenho conta — fazer login'}
        </button>
      </div>
    </div>
  );
}
