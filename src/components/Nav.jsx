import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import styles from './Nav.module.css'
import logoImg from './images/pixelryicone.jpeg'

export default function Nav() {
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40)
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <nav className={`${styles.nav} ${scrolled ? styles.scrolled : ''}`} aria-label="Principal">
      <Link to="/" className={styles.logo} aria-label="Página inicial da Pixelry">
        <img src={logoImg} alt="" className={styles.logoMark} />
        <span className={styles.wordmark}>PIXELRY</span>
      </Link>

      <Link to="/portal" className={styles.portalLink}>
        Área do cliente <span aria-hidden="true">↗</span>
      </Link>
    </nav>
  )
}
