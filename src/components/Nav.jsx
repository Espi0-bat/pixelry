import { useEffect, useState } from 'react'
import styles from './Nav.module.css'
import logoImg from './images/pixelryicone.jpeg'
import { WA_LINK_NAV as WA_LINK, WaIconNav as WaIcon } from './common/WhatsApp'
import PillNav from './PillNav'

export default function Nav() {
  const [scrolled, setScrolled] = useState(false)
  const [activeHref, setActiveHref] = useState('#')

  useEffect(() => {
    const onScroll = () => {
      setScrolled(window.scrollY > 40)
    }
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <nav className={`${styles.nav} ${scrolled ? styles.scrolled : ''}`}>
      <div style={{ display: 'flex', alignItems: 'center' }}>
        <PillNav
          logo={logoImg}
          logoAlt="PIXELRY"
          items={[
            { label: 'Início', href: '#' },
            { label: 'Serviços', href: '#servicos' },
            { label: 'Planos', href: '#planos' },
            { label: 'FAQ', href: '#faq' }
          ]}
          activeHref={activeHref}
          baseColor="#101022"
          pillColor="#070710"
          hoveredPillTextColor="#00D8FF"
          pillTextColor="#f0f0fa"
        />
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
        <a href={WA_LINK} target="_blank" rel="noreferrer" className={styles.cta}>
          <WaIcon />
          <span className={styles.ctaFull}>INICIAR DIAGNÓSTICO</span>
          <span className={styles.ctaMobile}>AGENDAR</span>
        </a>
      </div>
    </nav>
  )
}

