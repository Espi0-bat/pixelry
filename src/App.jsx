import React, { Suspense, useEffect, useState } from 'react'
import Nav          from './components/Nav'
import Hero         from './components/Hero'
import Problema     from './components/Problema'
import Servicos     from './components/Servicos'
import Footer       from './components/Footer'
import StickyCta    from './components/StickyCta'
import LoginModal   from './components/LoginModal'

const PORTAL_SESSION_KEY = 'pixelry_portal_session'
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
  const [isAuthenticated, setIsAuthenticated] = useState(() => {
    return window.sessionStorage.getItem(PORTAL_SESSION_KEY) === 'true'
  })
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
    if (isPortal && !isAuthenticated) {
      setIsLoginModalOpen(true)
    }
  }, [isPortal, isAuthenticated])

  const handleLoginSuccess = (email) => {
    console.log(`Logged in as: ${email}`)
    window.sessionStorage.setItem(PORTAL_SESSION_KEY, 'true')
    setIsAuthenticated(true)
    setIsLoginModalOpen(false)
  }

  const handleCloseModal = () => {
    setIsLoginModalOpen(false)

    if (window.location.hash === '#portal' && !isAuthenticated) {
      window.location.hash = ''
    }
  }

  const handlePortalLogout = () => {
    window.sessionStorage.removeItem(PORTAL_SESSION_KEY)
    setIsAuthenticated(false)
    setIsLoginModalOpen(false)
    window.location.href = BASE_URL
  }

  if (isPortal && isAuthenticated) {
    return (
      <Suspense fallback={<div style={{ minHeight: '100vh', background: 'var(--bg)' }}></div>}>
        <ClientPortal onLogout={handlePortalLogout} />
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
        <Suspense fallback={<div style={{ minHeight: '100vh', background: 'var(--bg)' }}></div>}>
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
