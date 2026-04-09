import React, { Suspense } from 'react'
import Nav          from './components/Nav'
import Hero         from './components/Hero'
import Problema     from './components/Problema'
import Servicos     from './components/Servicos'
import Footer       from './components/Footer'
import StickyCta    from './components/StickyCta'

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

export default function App() {
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
    </>
  )
}
