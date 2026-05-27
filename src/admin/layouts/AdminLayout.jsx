import { useEffect, useRef, useState } from 'react';
import { Outlet, NavLink, useNavigate } from 'react-router-dom';
import { Home, Users, FolderUp, Activity, LogOut, Kanban, Menu, X } from 'lucide-react';
import { supabase } from '../../config/supabase';
import logoImg from '../../components/images/pixelryicone.jpeg';
import AdminGlowEffects from '../components/AdminGlowEffects';
import './AdminLayout.css';

const DOT_SPACING = 40;
const DOT_R = 1.4;
const GLOW_RADIUS = 200;

export default function AdminLayout({ user, onLogout }) {
  const navigate = useNavigate();
  const canvasRef = useRef(null);
  const mouseRef  = useRef({ x: 0.5, y: 0.5 });
  const targetRef = useRef({ x: 0.5, y: 0.5 });
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const theme = user?.email?.includes('erickvin49') ? 'gold' : 'obsidian';
  const themeRef = useRef(theme);
  themeRef.current = theme;

  useEffect(() => {
    const handleMouseMove = (e) => {
      const canvas = canvasRef.current;
      if (canvas) {
        const r = canvas.getBoundingClientRect();
        targetRef.current = { x: (e.clientX - r.left) / r.width, y: (e.clientY - r.top) / r.height };
      }
    };
    window.addEventListener('mousemove', handleMouseMove);
    return () => window.removeEventListener('mousemove', handleMouseMove);
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    let dots = [];
    let time = 0;
    let rafId;

    function buildDots(W, H) {
      dots = [];
      if (W <= 900) return;
      const cols = Math.ceil(W / DOT_SPACING) + 1;
      const rows = Math.ceil(H / DOT_SPACING) + 1;
      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
          dots.push({ x: c * DOT_SPACING, y: r * DOT_SPACING, phase: Math.random() * Math.PI * 2, speed: 0.35 + Math.random() * 0.45 });
        }
      }
    }

    function draw() {
      const W = canvas.width;
      const H = canvas.height;
      time += 0.010;
      mouseRef.current.x += (targetRef.current.x - mouseRef.current.x) * 0.06;
      mouseRef.current.y += (targetRef.current.y - mouseRef.current.y) * 0.06;
      ctx.clearRect(0, 0, W, H);
      const mx = mouseRef.current.x * W;
      const my = mouseRef.current.y * H;
      for (const d of dots) {
        const wave = Math.sin(time * d.speed + d.phase);
        let alpha = 0.07 + wave * 0.04;
        let radius = DOT_R * (0.75 + wave * 0.25);
        const dist = Math.hypot(d.x - mx, d.y - my);
        if (dist < GLOW_RADIUS) {
          const t = 1 - dist / GLOW_RADIUS;
          alpha += t * 0.55;
          radius += t * 1.4;
          const isGold = themeRef.current === 'gold';
          const hue   = isGold ? 45 + (dist / GLOW_RADIUS) * 15 : 265 - (dist / GLOW_RADIUS) * 75;
          const sat   = isGold ? 100 : 85;
          const light = isGold ? 55 - (dist / GLOW_RADIUS) * 15 : 70 - (dist / GLOW_RADIUS) * 20;
          ctx.fillStyle = `hsla(${hue}, ${sat}%, ${light}%, ${Math.min(alpha, 0.85)})`;
        } else {
          const isGold = themeRef.current === 'gold';
          ctx.fillStyle = isGold
            ? `hsla(45, 90%, 52%, ${alpha})`
            : `hsla(265, 60%, 65%, ${alpha})`;
        }
        ctx.beginPath();
        ctx.arc(d.x, d.y, radius, 0, Math.PI * 2);
        ctx.fill();
      }
      rafId = requestAnimationFrame(draw);
    }

    function resize() {
      const W = canvas.offsetWidth;
      const H = canvas.offsetHeight;
      canvas.width = W;
      canvas.height = H;
      buildDots(W, H);
    }

    const ro = new ResizeObserver(resize);
    ro.observe(canvas);
    resize();
    rafId = requestAnimationFrame(draw);
    return () => { ro.disconnect(); cancelAnimationFrame(rafId); };
  }, []);

  const handleLogout = async () => {
    if (onLogout) {
      await onLogout();
    } else {
      await supabase.auth.signOut();
    }
    navigate('/admin');
  };

  const initials = user?.email
    ? user.email.substring(0, 2).toUpperCase()
    : 'AD';

  const closeMenu = () => setIsMobileMenuOpen(false);

  return (
    <div className={`admin-layout theme-${theme}`}>
      <canvas ref={canvasRef} className="bg-canvas" aria-hidden="true" />
      <AdminGlowEffects theme={theme} />

      {isMobileMenuOpen && (
        <div className="mobile-overlay" onClick={closeMenu} />
      )}

      <aside className={`sidebar${isMobileMenuOpen ? ' open' : ''}`}>
        <div className="sidebar-header">
          <NavLink to="/" title="Ir para o site principal" onClick={closeMenu}>
            <img src={logoImg} alt="Pixelry Logo" className="logo-real" style={{ cursor: 'pointer' }} />
          </NavLink>
          <h2>Pixelry Admin</h2>
        </div>

        <nav className="sidebar-nav">
          <NavLink to="/admin" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} end onClick={closeMenu}>
            <Home size={18} /><span>Dashboard</span>
          </NavLink>
          <NavLink to="/admin/clientes" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} onClick={closeMenu}>
            <Users size={18} /><span>Clientes</span>
          </NavLink>
          <NavLink to="/admin/entregas" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} onClick={closeMenu}>
            <FolderUp size={18} /><span>Entregas</span>
          </NavLink>
          <NavLink to="/admin/status" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} onClick={closeMenu}>
            <Activity size={18} /><span>Status</span>
          </NavLink>
          <NavLink to="/admin/kanban" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} onClick={closeMenu}>
            <Kanban size={18} /><span>Kanban</span>
          </NavLink>
        </nav>

        <div className="sidebar-footer">
          <div className="version-badge">v2.0.0 • PIXELRY</div>
          <button className="nav-item logout-btn" onClick={handleLogout}>
            <LogOut size={18} /><span>Sair do Painel</span>
          </button>
        </div>
      </aside>

      <main className="main-content">
        <header className="topbar">
          <div className="topbar-left">
            <button className="hamburger-btn" onClick={() => setIsMobileMenuOpen(o => !o)} aria-label="Menu">
              {isMobileMenuOpen ? <X size={22} /> : <Menu size={22} />}
            </button>
            <div className="topbar-search">
              <input type="text" placeholder="Buscar clientes ou projetos..." />
            </div>
          </div>
          <div className="topbar-user">
            <div className="avatar">{initials}</div>
            <span style={{ color: 'var(--text-secondary)', fontSize: 13 }}>
              {user?.email || 'Administrador'}
            </span>
          </div>
        </header>
        <div className="content-area">
          <Outlet />
        </div>
      </main>
    </div>
  );
}
