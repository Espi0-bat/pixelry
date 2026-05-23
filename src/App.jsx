import React, { Suspense, useEffect, useState } from 'react'
import Nav          from './components/Nav'
import Hero         from './components/Hero'
import Problema     from './components/Problema'
import Servicos     from './components/Servicos'
import Footer       from './components/Footer'
import StickyCta    from './components/StickyCta'
import LoginModal   from './components/LoginModal'
import { isSupabaseConfigured, supabase } from './config/supabase'

const BASE_URL = import.meta.env.BASE_URL || '/'

// Lazy Loading para componentes abaixo da dobra (ganho de performance substancial de LCP e FCP)
const Core = React.lazy(() => import('./components/Core'))
const Processo = React.lazy(() => import('./components/Processo'))
const Diferenciais = React.lazy(() => import('./components/Diferenciais'))
const Showcase = React.lazy(() => import('./components/Showcase'))
const ParaQuem = React.lazy(() => import('./components/ParaQuem'))
const Manifesto = React.lazy(() => import('./components/Manifesto'))
const Planos = React.lazy(() => import('./components/Planos'))
const Faq = React.lazy(() => import('./components/Faq'))
const CtaFinal = React.lazy(() => import('./components/CtaFinal'))
const ClientPortal = React.lazy(() => import('./pages/ClientPortal'))

export default function App() {
  const [locationKey, setLocationKey] = useState(() => `${window.location.pathname}${window.location.hash}`)
  const [authReady, setAuthReady] = useState(false)
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [currentUser, setCurrentUser] = useState(null)
  const [isLoginModalOpen, setIsLoginModalOpen] = useState(false)

  useEffect(() => {
    const syncLocation = () => setLocationKey(`${window.location.pathname}${window.location.hash}`)

    window.addEventListener('hashchange', syncLocation)
    window.addEventListener('popstate', syncLocation)

    return () => {
      window.removeEventListener('hashchange', syncLocation)
      window.removeEventListener('popstate', syncLocation)
    }
  }, [])

  const isPortal =
    locationKey.includes('#portal') ||
    window.location.hash === '#portal' ||
    window.location.pathname.replace(/\/$/, '').endsWith('/portal')

  useEffect(() => {
    if (!isSupabaseConfigured) {
      setAuthReady(true)
      return
    }

    let mounted = true

    const syncSession = (session) => {
      if (!mounted) return
      setCurrentUser(session?.user ?? null)
      setIsAuthenticated(Boolean(session))
      setAuthReady(true)
    }

    supabase.auth.getSession().then(({ data }) => {
      syncSession(data.session)
    })

    const { data: authListener } = supabase.auth.onAuthStateChange((_event, session) => {
      syncSession(session)
    })

    return () => {
      mounted = false
      authListener.subscription.unsubscribe()
    }
  }, [])

  useEffect(() => {
    if (authReady && isPortal && !isAuthenticated) {
      setIsLoginModalOpen(true)
    }
  }, [authReady, isPortal, isAuthenticated])

  const handleLoginSuccess = (_session, user) => {
    setCurrentUser(user)
    setIsAuthenticated(true)
    setIsLoginModalOpen(false)
  }

  const handleCloseModal = () => {
    setIsLoginModalOpen(false)

    if (window.location.hash === '#portal' && !isAuthenticated) {
      window.location.hash = ''
    }
  }

  const handlePortalLogout = async () => {
    if (supabase) {
      await supabase.auth.signOut()
    }
    setIsAuthenticated(false)
    setCurrentUser(null)
    setIsLoginModalOpen(false)
    window.location.href = BASE_URL
  }

  if (isPortal && !authReady) {
    return <div style={{ minHeight: '100dvh', background: 'var(--bg)' }}></div>
  }

  if (isPortal && isAuthenticated) {
    return (
      <Suspense fallback={<div style={{ minHeight: '100dvh', background: 'var(--bg)' }}></div>}>
        <ClientPortal user={currentUser} onLogout={handlePortalLogout} />
      </Suspense>
    )
  }

  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Problema />
        <Servicos />
        <Suspense fallback={<div style={{ minHeight: '100dvh', background: 'var(--bg)' }}></div>}>
          <Core />
          <Processo />
          <Diferenciais />
          <Showcase />
          <ParaQuem />
          <Manifesto />
          <Planos />
          <Faq />
          <CtaFinal />
        </Suspense>
      </main>
      <Footer />
      <StickyCta />
      <LoginModal 
        isOpen={isLoginModalOpen} 
        onClose={handleCloseModal} 
        onLoginSuccess={handleLoginSuccess} 
      />
    </>
  )
}
