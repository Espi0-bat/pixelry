import { useEffect, useRef, useState } from 'react';
import { Outlet, NavLink, useNavigate, useLocation } from 'react-router-dom';
import { Home, Users, FolderUp, Activity, LogOut, Kanban, Menu, X, Target, UserCircle2, MessageSquare, FileArchive, Headphones } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import { supabase } from '../../config/supabase';
import logoImg from '../../components/images/pixelryicone.jpeg';
import AdminGlowEffects from '../components/AdminGlowEffects';
import ProfilePanel from '../components/ProfilePanel';
import './AdminLayout.css';

const DOT_SPACING = 40;
const DOT_R = 1.4;
const GLOW_RADIUS = 160;
const TARGET_FPS = 30;
const FRAME_INTERVAL = 1000 / TARGET_FPS;

function getRoleFromEmail(email = '') {
  if (email.includes('moutinhoezer') || email.includes('erickvin49')) return 'super_admin';
  if (email.includes('sofiagramelich')) return 'manager';
  return 'employee';
}

export default function AdminLayout({ user, onLogout }) {
  const navigate = useNavigate();
  const location = useLocation();
  const canvasRef = useRef(null);
  const mouseRef  = useRef({ x: 0.5, y: 0.5 });
  const targetRef = useRef({ x: 0.5, y: 0.5 });
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const [avatarUrl, setAvatarUrl] = useState(null);
  const [userRole, setUserRole] = useState(() => getRoleFromEmail(user?.email));
  const [userProfile, setUserProfile] = useState(null);
  const theme = userRole === 'manager' ? 'rose'
    : userRole === 'employee' ? 'slate'
    : user?.email?.includes('erickvin49') ? 'gold'
    : 'obsidian';
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
    let lastFrameTime = 0;
    let paused = false;

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

    function draw(timestamp) {
      rafId = requestAnimationFrame(draw);
      if (paused) return;
      // Throttle to TARGET_FPS
      if (timestamp - lastFrameTime < FRAME_INTERVAL) return;
      lastFrameTime = timestamp;

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
          const th = themeRef.current;
          const hue = th === 'gold' ? 45 + (dist / GLOW_RADIUS) * 15
            : th === 'rose' ? 330 - (dist / GLOW_RADIUS) * 20
            : 265 - (dist / GLOW_RADIUS) * 75;
          const sat   = th === 'gold' ? 100 : 85;
          const light = th === 'gold' ? 55 - (dist / GLOW_RADIUS) * 15 : 70 - (dist / GLOW_RADIUS) * 20;
          ctx.fillStyle = `hsla(${hue}, ${sat}%, ${light}%, ${Math.min(alpha, 0.85)})`;
        } else {
          const th = themeRef.current;
          ctx.fillStyle = th === 'gold'
            ? `hsla(45, 90%, 52%, ${alpha})`
            : th === 'rose'
            ? `hsla(330, 80%, 70%, ${alpha})`
            : `hsla(265, 60%, 65%, ${alpha})`;
        }
        ctx.beginPath();
        ctx.arc(d.x, d.y, radius, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    function resize() {
      const W = canvas.offsetWidth;
      const H = canvas.offsetHeight;
      canvas.width = W;
      canvas.height = H;
      buildDots(W, H);
    }

    function handleVisibility() {
      paused = document.hidden;
    }

    document.addEventListener('visibilitychange', handleVisibility);
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);
    resize();
    rafId = requestAnimationFrame(draw);
    return () => {
      ro.disconnect();
      cancelAnimationFrame(rafId);
      document.removeEventListener('visibilitychange', handleVisibility);
    };
  }, []);

  // Carrega perfil completo (avatar, role, job_title); redireciona clientes para o portal
  useEffect(() => {
    if (!user?.id) return;
    supabase
      .from('profiles')
      .select('avatar_url, role, job_title, full_name')
      .eq('id', user.id)
      .single()
      .then(({ data }) => {
        if (data?.avatar_url) setAvatarUrl(data.avatar_url);
        if (data?.role) {
          setUserRole(data.role);
          if (data.role === 'client') navigate('/portal');
        }
        setUserProfile(data);
      });
  }, [user?.id]);

  const handleLogout = async () => {
    if (onLogout) {
      await onLogout();
    } else {
      await supabase.auth.signOut();
    }
    navigate('/admin');
  };

  const closeMenu = () => setIsMobileMenuOpen(false);

  useEffect(() => {
    setIsMobileMenuOpen(false);
  }, [location.pathname]);

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
          {['super_admin', 'manager'].includes(userRole) ? (
            <>
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
              <NavLink to="/admin/metas" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} onClick={closeMenu}>
                <Target size={18} /><span>Metas</span>
              </NavLink>
              <div className="sidebar-nav-divider" />
              <NavLink to="/admin/equipe" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} onClick={closeMenu}>
                <UserCircle2 size={18} /><span>Equipe</span>
              </NavLink>
              <NavLink to="/admin/mensagens" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} onClick={closeMenu}>
                <MessageSquare size={18} /><span>Mensagens</span>
              </NavLink>
              <NavLink to="/admin/suporte" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} onClick={closeMenu}>
                <Headphones size={18} /><span>Suporte</span>
              </NavLink>
            </>
          ) : (
            <>
              <NavLink to="/admin" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} end onClick={closeMenu}>
                <Home size={18} /><span>Meu Dashboard</span>
              </NavLink>
              <NavLink to="/admin/mensagens" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} onClick={closeMenu}>
                <MessageSquare size={18} /><span>Mensagens</span>
              </NavLink>
              <NavLink to="/admin/arquivos" className={({isActive}) => isActive ? 'nav-item active' : 'nav-item'} onClick={closeMenu}>
                <FileArchive size={18} /><span>Arquivos</span>
              </NavLink>
            </>
          )}
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
              <input type="text" placeholder="Buscar clientes ou projetos..." aria-label="Buscar clientes ou projetos" />
            </div>
          </div>
          <ProfilePanel
            user={user}
            avatarUrl={avatarUrl}
            onAvatarUpdate={setAvatarUrl}
            onLogout={handleLogout}
            userRole={userRole}
          />
        </header>
        <div className="content-area">
          <AnimatePresence mode="wait">
            <motion.div
              key={location.pathname}
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -8 }}
              transition={{ duration: 0.22, ease: 'easeOut' }}
              style={{ height: '100%' }}
            >
              <Outlet context={{ userRole, userProfile, user }} />
            </motion.div>
          </AnimatePresence>
        </div>
      </main>
    </div>
  );
}
