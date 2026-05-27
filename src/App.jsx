import React, { Suspense, useEffect, useState } from 'react'
import { Routes, Route, useLocation, Navigate } from 'react-router-dom'
import Nav          from './components/Nav'
import Hero         from './components/Hero'
import Problema     from './components/Problema'
import Servicos     from './components/Servicos'
import Footer       from './components/Footer'
import StickyCta    from './components/StickyCta'
import CookieConsent from './components/CookieConsent'
import LoginModal   from './components/LoginModal'
import { isSupabaseConfigured, supabase, ADMIN_EMAIL } from './config/supabase'

// Lazy Loading para componentes abaixo da dobra (ganho de performance substancial de LCP e FCP)
const Core = React.lazy(() => import('./components/Core'))
const Processo = React.lazy(() => import('./components/Processo'))
const Diferenciais = React.lazy(() => import('./components/Diferenciais'))
const Showcase = React.lazy(() => import('./components/Showcase'))
const Cases = React.lazy(() => import('./components/Cases'))
const ParaQuem = React.lazy(() => import('./components/ParaQuem'))
const Manifesto = React.lazy(() => import('./components/Manifesto'))
const Planos = React.lazy(() => import('./components/Planos'))
const Faq = React.lazy(() => import('./components/Faq'))
const CtaFinal = React.lazy(() => import('./components/CtaFinal'))
const PoliticaPrivacidade = React.lazy(() => import('./pages/PoliticaPrivacidade'))
const TermosUso = React.lazy(() => import('./pages/TermosUso'))
const ClientPortal = React.lazy(() => import('./pages/ClientPortal'))

// Admin panel — lazy loaded
const AdminLogin      = React.lazy(() => import('./admin/pages/AdminLogin'))
const AdminLayout     = React.lazy(() => import('./admin/layouts/AdminLayout'))
const Dashboard       = React.lazy(() => import('./admin/pages/Dashboard'))
const Clientes        = React.lazy(() => import('./admin/pages/Clientes'))
const ClienteDetalhes = React.lazy(() => import('./admin/pages/ClienteDetalhes'))
const Entregas        = React.lazy(() => import('./admin/pages/Entregas'))
const Status          = React.lazy(() => import('./admin/pages/Status'))
const Kanban          = React.lazy(() => import('./admin/pages/Kanban'))

const Home = () => (
  <>
    <Hero />
    <Problema />
    <Servicos />
    <Suspense fallback={<div style={{ minHeight: '100dvh', background: 'var(--bg)' }}></div>}>
      <Core />
      <Processo />
      <Diferenciais />
      <Showcase />
      <Cases />
      <ParaQuem />
      <Manifesto />
      <Planos />
      <Faq />
      <CtaFinal />
    </Suspense>
  </>
)

const PORTAL_FALLBACK = <div style={{ minHeight: '100dvh', background: 'var(--bg)' }} />

export default function App() {
  const location = useLocation()
  const [user, setUser] = useState(null)
  const [authLoading, setAuthLoading] = useState(true)

  // Inicializa sessão e escuta mudanças de auth
  useEffect(() => {
    if (!isSupabaseConfigured || !supabase) {
      setAuthLoading(false)
      return
    }
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null)
      setAuthLoading(false)
    })
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null)
    })
    return () => subscription.unsubscribe()
  }, [])

  // Scroll para o elemento do hash após navegação (ex: /#servicos)
  useEffect(() => {
    if (location.hash) {
      const id = location.hash.slice(1)
      const el = document.getElementById(id)
      if (el) {
        el.scrollIntoView({ behavior: 'smooth' })
      } else {
        const timer = setTimeout(() => {
          const elDelayed = document.getElementById(id)
          if (elDelayed) elDelayed.scrollIntoView({ behavior: 'smooth' })
        }, 300)
        return () => clearTimeout(timer)
      }
    } else if (location.pathname === '/') {
      window.scrollTo({ top: 0, behavior: 'smooth' })
    }
  }, [location])

  const handleLogout = async () => {
    if (supabase) await supabase.auth.signOut()
    setUser(null)
  }

  const isAdmin = location.pathname.startsWith('/admin')

  // Portal do cliente (renomeado de /admin para /portal)
  const portalElement = authLoading
    ? PORTAL_FALLBACK
    : !user
      ? (
        <div style={{ minHeight: '100dvh', background: 'var(--bg)' }}>
          <LoginModal
            isOpen={true}
            onClose={() => {}}
            onLoginSuccess={(_session, usr) => setUser(usr)}
          />
        </div>
      )
      : (
        <Suspense fallback={PORTAL_FALLBACK}>
          <ClientPortal user={user} onLogout={handleLogout} />
        </Suspense>
      )

  // Painel admin — mostra login se não autenticado, redireciona se e-mail errado
  const adminElement = authLoading
    ? PORTAL_FALLBACK
    : !user
      ? <Suspense fallback={PORTAL_FALLBACK}><AdminLogin onLogin={usr => setUser(usr)} /></Suspense>
      : user.email !== ADMIN_EMAIL
        ? <Navigate to="/" replace />
        : <Suspense fallback={PORTAL_FALLBACK}><AdminLayout user={user} onLogout={handleLogout} /></Suspense>

  return (
    <>
      {!isAdmin && <Nav />}
      <main>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route
            path="/privacidade"
            element={
              <Suspense fallback={PORTAL_FALLBACK}>
                <PoliticaPrivacidade />
              </Suspense>
            }
          />
          <Route
            path="/termos"
            element={
              <Suspense fallback={PORTAL_FALLBACK}>
                <TermosUso />
              </Suspense>
            }
          />
          <Route path="/portal" element={portalElement} />
          <Route path="/admin" element={adminElement}>
            <Route index element={<Navigate to="/admin/dashboard" replace />} />
            <Route path="dashboard" element={<Suspense fallback={PORTAL_FALLBACK}><Dashboard /></Suspense>} />
            <Route path="clientes" element={<Suspense fallback={PORTAL_FALLBACK}><Clientes /></Suspense>} />
            <Route path="clientes/:id" element={<Suspense fallback={PORTAL_FALLBACK}><ClienteDetalhes /></Suspense>} />
            <Route path="entregas" element={<Suspense fallback={PORTAL_FALLBACK}><Entregas /></Suspense>} />
            <Route path="status" element={<Suspense fallback={PORTAL_FALLBACK}><Status /></Suspense>} />
            <Route path="kanban" element={<Suspense fallback={PORTAL_FALLBACK}><Kanban /></Suspense>} />
          </Route>
        </Routes>
      </main>
      {!isAdmin && <Footer />}
      {!isAdmin && <StickyCta />}
      {!isAdmin && <CookieConsent />}
    </>
  )
}
