import { useRevealContainer } from '../hooks/useReveal'
import styles from './ProjetoDestaque.module.css'

const BASE_URL = import.meta.env.BASE_URL || '/'

export default function ProjetoDestaque() {
  const ref = useRevealContainer()

  return (
    <section id="projeto-destaque" className={styles.section} aria-labelledby="projeto-destaque-title">
      <div className={styles.inner} ref={ref}>
        <header className={styles.header}>
          <span className={styles.label}>Projeto em destaque <span>01</span></span>
          <h2 id="projeto-destaque-title" className={styles.h2}>
            Uma presença médica construída{' '}<br />
            <span className="type-accent">para transmitir confiança.</span>
          </h2>
        </header>

        <a
          href="https://espi0-bat.github.io/site-rogerio/"
          target="_blank"
          rel="noopener noreferrer"
          className={styles.card}
        >
          <div className={styles.visual}>
            <div className={styles.frame}>
              <img
                src={`${BASE_URL}assets/portfolio/dr-rogerio-site.webp`}
                alt="Página inicial do site institucional do Doutor Rogério Furtado"
                width="1440"
                height="1000"
                loading="eager"
              />
            </div>
            <span className={styles.cornerNote} aria-hidden="true">PIXELRY® — 2026</span>
          </div>

          <div className={styles.info}>
            <div className={styles.infoText}>
              <p className={styles.segment}>Site institucional · Saúde</p>
              <h3 className={styles.name}>Doutor Rogério</h3>
              <p className={styles.desc}>
                Uma experiência digital clara e acolhedora, pensada para apresentar sua trajetória e facilitar o agendamento de consultas.
              </p>
            </div>
            <span className={styles.link}>
              Visitar o site <span aria-hidden="true">↗</span>
            </span>
          </div>
        </a>
      </div>
    </section>
  )
}
