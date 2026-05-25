import React, { Suspense, useEffect } from 'react'
import { Routes, Route, useLocation } from 'react-router-dom'
import Nav          from './components/Nav'
import Hero         from './components/Hero'
import Problema     from './components/Problema'
import Servicos     from './components/Servicos'
import Footer       from './components/Footer'
import StickyCta    from './components/StickyCta'
import CookieConsent from './components/CookieConsent'

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

export default function App() {
  const location = useLocation()

  // Scroll para o elemento do hash após navegação (ex: /#servicos)
  useEffect(() => {
    if (location.hash) {
      const id = location.hash.slice(1) // remove o '#'
      const el = document.getElementById(id)
      if (el) {
        el.scrollIntoView({ behavior: 'smooth' })
      } else {
        // Elemento ainda não foi renderizado (lazy load), tenta após um delay
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

  return (
    <>
      <Nav />
      <main>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route 
            path="/privacidade" 
            element={
              <Suspense fallback={<div style={{ minHeight: '100dvh', background: 'var(--bg)' }}></div>}>
                <PoliticaPrivacidade />
              </Suspense>
            } 
          />
          <Route 
            path="/termos" 
            element={
              <Suspense fallback={<div style={{ minHeight: '100dvh', background: 'var(--bg)' }}></div>}>
                <TermosUso />
              </Suspense>
            } 
          />
        </Routes>
      </main>
      <Footer />
      <StickyCta />
      <CookieConsent />
    </>
  )
}
