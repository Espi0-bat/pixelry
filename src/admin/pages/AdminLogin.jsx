import { useState } from 'react';
import { isSupabaseConfigured, supabase, ADMIN_EMAILS } from '../../config/supabase';
import PasswordInput from '../../components/PasswordInput';
import ForgotPassword from '../../components/ForgotPassword';
import logoImg from '../../components/images/pixelryicone.jpeg';
import './AdminLogin.css';

export default function AdminLogin({ onLogin }) {
  const [isLoggingIn, setIsLoggingIn] = useState(false);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [mode, setMode] = useState('login'); // 'login' | 'forgot'

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (isLoggingIn) return;
    setError('');

    if (!isSupabaseConfigured || !supabase) {
      setError('O portal ainda não está conectado ao Supabase neste deploy.');
      return;
    }

    setIsLoggingIn(true);

    const { data, error: signInError } = await supabase.auth.signInWithPassword({ email, password });

    if (signInError) {
      setError('E-mail ou senha incorretos.');
      setIsLoggingIn(false);
      return;
    }

    if (!ADMIN_EMAILS.includes(data.user.email)) {
      await supabase.auth.signOut();
      setError('Acesso restrito à equipe Pixelry.');
      setIsLoggingIn(false);
      return;
    }

    onLogin(data.user);
  };

  return (
    <div className="login-container">
      <div className="login-bg-grid"></div>

      <div className="login-card animate-in">
        <div className="login-header">
          <img src={logoImg} alt="Pixelry" className="login-logo" />
          <h1 className="login-title">Pixelry Admin</h1>
          <p className="login-subtitle">
            {mode === 'forgot' ? 'Recuperação de senha' : 'Acesso restrito à equipe'}
          </p>
        </div>

        {mode === 'forgot' ? (
          <ForgotPassword defaultEmail={email} onBack={() => setMode('login')} />
        ) : (
          <form onSubmit={handleSubmit}>
            <div className="login-form-group">
              <label className="login-label" htmlFor="admin-email">E-mail corporativo</label>
              <input
                id="admin-email"
                type="email"
                placeholder="admin@pixelry.com.br"
                className="login-input"
                required
                disabled={isLoggingIn}
                value={email}
                autoComplete="email"
                onChange={e => setEmail(e.target.value)}
              />
            </div>
            <div className="login-form-group" style={{ marginBottom: error ? '16px' : '24px' }}>
              <label className="login-label" htmlFor="admin-password">Senha</label>
              <PasswordInput
                id="admin-password"
                className="login-input"
                placeholder="••••••••"
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
              }} role="alert">
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
              ) : 'Entrar no Painel'}
            </button>

            <button
              type="button"
              className="login-forgot"
              onClick={() => { setError(''); setMode('forgot'); }}
            >
              Esqueci minha senha
            </button>
          </form>
        )}

      </div>
    </div>
  );
}
