import Nav          from './components/Nav'
import Hero         from './components/Hero'
import Problema     from './components/Problema'
import Servicos     from './components/Servicos'
import Core         from './components/Core'
import Processo     from './components/Processo'
import Diferenciais from './components/Diferenciais'
import Showcase     from './components/Showcase'
import ParaQuem     from './components/ParaQuem'
import Manifesto    from './components/Manifesto'
import Planos       from './components/Planos'
import Faq          from './components/Faq'
import CtaFinal     from './components/CtaFinal'
import Footer       from './components/Footer'
import StickyCta    from './components/StickyCta'

export default function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Problema />
        <Servicos />
        <Core />
        <Processo />
        <Diferenciais />
        <Showcase />
        <ParaQuem />
        <Manifesto />
        <Planos />
        <Faq />
        <CtaFinal />
      </main>
      <Footer />
      <StickyCta />
    </>
  )
}
