import { useEffect, useState } from 'react'
import styles from './Nav.module.css'
import logoImg from './images/pixelryicone.jpeg'
import { WA_LINK_NAV as WA_LINK, WaIconNav as WaIcon } from './common/WhatsApp'

export default function Nav() {
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40)
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <nav className={`${styles.nav} ${scrolled ? styles.scrolled : ''}`}>
      <div className={styles.brand}>
        <img src={logoImg} alt="PIXELRY" className={styles.logoImage} />
        <span className={styles.logoText}>PIXELRY</span>
      </div>
      <a href={WA_LINK} target="_blank" rel="noreferrer" className={styles.cta}>
        <WaIcon />
        <span className={styles.ctaFull}>INICIAR DIAGNÓSTICO</span>
        <span className={styles.ctaMobile}>AGENDAR</span>
      </a>
    </nav>
  )
}
