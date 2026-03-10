import styles from './Footer.module.css'

const WA_LINK = 'https://wa.me/5561991410161?text=Olá!%20Vim%20pelo%20site%20da%20PIXELRY%20e%20gostaria%20de%20saber%20mais%20sobre%20os%20serviços.'

const WaIcon = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347z"/>
    <path d="M12 0C5.373 0 0 5.373 0 12c0 2.127.558 4.126 1.528 5.857L.057 23.882a.5.5 0 0 0 .614.612l6.162-1.624A11.944 11.944 0 0 0 12 24c6.627 0 12-5.373 12-12S18.627 0 12 0zm0 22c-1.886 0-3.655-.523-5.168-1.43l-.369-.22-3.812 1.004 1.021-3.72-.24-.382A9.945 9.945 0 0 1 2 12C2 6.477 6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z"/>
  </svg>
)

export default function Footer() {
  return (
    <footer className={styles.footer}>
      <div className={styles.top}>
        {/* Brand */}
        <div className={styles.brand}>
          <span className={styles.logo}>PIXELRY</span>
          <p className={styles.tagline}>
            Estúdio digital focado em presença profissional<br />
            para negócios locais em Brasília — DF.
          </p>
          <a href={WA_LINK} target="_blank" rel="noreferrer" className={styles.waLink}>
            <WaIcon />
            (61) 99141-0161
          </a>
        </div>

        {/* Nav */}
        <nav className={styles.nav} aria-label="Footer navigation">
          <p className={styles.navTitle}>Navegação</p>
          <a href="#servicos" className={styles.navLink}>Serviços</a>
          <a href="#processo" className={styles.navLink}>Processo</a>
          <a href="#contato"  className={styles.navLink}>Contato</a>
        </nav>

        {/* Contact */}
        <div className={styles.contact}>
          <p className={styles.navTitle}>Contato</p>
          <a href={WA_LINK} target="_blank" rel="noreferrer" className={styles.navLink}>
            WhatsApp
          </a>
          <span className={styles.navLink}>Brasília — DF</span>
          <span className={styles.soon}>Instagram · Em breve</span>
        </div>
      </div>

      <div className={styles.bottom}>
        <span className={styles.copy}>© 2025 PIXELRY · Todos os direitos reservados</span>
        <span className={styles.copy}>Padrão sem concessão.</span>
      </div>
    </footer>
  )
}
