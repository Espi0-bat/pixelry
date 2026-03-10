import { useEffect, useState } from 'react'
import styles from './Nav.module.css'

const WA_LINK = 'https://wa.me/5561991410161?text=Olá!%20Vim%20pelo%20site%20da%20PIXELRY%20e%20gostaria%20de%20conversar%20sobre%20meu%20projeto.'

export default function Nav() {
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40)
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <nav className={`${styles.nav} ${scrolled ? styles.scrolled : ''}`}>
      <span className={styles.logo}>PIXELRY</span>
      <a href={WA_LINK} target="_blank" rel="noreferrer" className={styles.cta}>
        <span className={styles.ctaFull}>Falar agora →</span>
        <span className={styles.ctaMobile}>WhatsApp →</span>
      </a>
    </nav>
  )
}
