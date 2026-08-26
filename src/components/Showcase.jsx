import { useRevealContainer } from '../hooks/useReveal'
import styles from './Showcase.module.css'

function DesktopMockup() {
  return (
    // Ilustração de interface — o texto miúdo é figurativo, não conteúdo
    <div className={styles.browser} aria-hidden="true">
      <div className={styles.bar}>
        <span className={`${styles.dot} ${styles.dotRed}`}   />
        <span className={`${styles.dot} ${styles.dotYellow}`}/>
        <span className={`${styles.dot} ${styles.dotGreen}`} />
        <span className={styles.url}>pixelry.com.br/clinica</span>
      </div>
      <div className={styles.browserBody}>
        {/* Nav */}
        <div className={styles.bNav}>
          <div className={styles.bNavLogo} />
          <div className={styles.bNavLinks}>
            <div className={styles.bNavLink} />
            <div className={styles.bNavLink} />
            <div className={styles.bNavBtn} />
          </div>
        </div>
        {/* Hero */}
        <div className={styles.heroBlock}>
          <div className={styles.heroText}>
            <div className={styles.heroLabel} />
            <div className={styles.heroH1} />
            <div className={styles.heroH1Short} />
            <div className={styles.heroCta} />
          </div>
        </div>
        {/* Metrics strip */}
        <div className={styles.metricsStrip}>
          <div className={styles.metric}>
            <span className={styles.metricVal}>+340%</span>
            <span className={styles.metricLabel}>leads/mês</span>
          </div>
          <div className={styles.metricDiv} />
          <div className={styles.metric}>
            <span className={styles.metricVal}>97</span>
            <span className={styles.metricLabel}>PageSpeed</span>
          </div>
          <div className={styles.metricDiv} />
          <div className={styles.metric}>
            <span className={styles.metricVal}>4,8%</span>
            <span className={styles.metricLabel}>conv. rate</span>
          </div>
        </div>
        {/* Cards row */}
        <div className={styles.twoCol}>
          <div className={styles.block} />
          <div className={styles.block} />
          <div className={styles.blockSm} />
          <div className={styles.blockSm} />
        </div>
      </div>
    </div>
  )
}

function MobileMockup() {
  return (
    <div className={styles.phone} aria-hidden="true">
      <span className={styles.notch} />
      <div className={styles.phoneBody}>
        {/* Mobile hero */}
        <div className={styles.pHero}>
          <div className={styles.pHeroLabel} />
          <div className={styles.pHeroH1} />
          <div className={styles.pHeroH1} style={{ width: '72%' }} />
        </div>
        {/* CTA button */}
        <div className={styles.pCtaBtn} />
        {/* Content blocks */}
        <div className={styles.pBlock} />
        <div className={styles.pBlockSm} />
        <div className={styles.pBlockSm} />
        <div className={styles.pBlock} />
        {/* Bottom stat */}
        <div className={styles.pStat}>
          <span className={styles.pStatVal}>4.8★</span>
          <span className={styles.pStatTxt}>Google</span>
        </div>
      </div>
    </div>
  )
}

export default function Showcase() {
  const ref = useRevealContainer()

  return (
    <div className={styles.bg}>
      <div className={styles.inner} ref={ref}>
        <header className={`${styles.header} reveal`}>
          <span className="label">DIREÇÃO VISUAL</span>
          <h2 className={styles.h2}>Este site é a nossa prova de conceito.</h2>
          <p className={styles.sub}>
            O padrão visual, a estrutura e a atenção ao detalhe que você vê aqui são o que levamos para cada projeto. Cada entrega segue os mesmos critérios de uma firma de engenharia: estrutura antes de estética, conversão antes de decoração. Abaixo, a direção visual que orienta cada entrega da PIXELRY.
          </p>
        </header>

        <div className={`${styles.row} reveal reveal-d1`}>
          {/* Desktop card */}
          <div className={styles.card}>
            <div className={styles.cardInner}>
              <DesktopMockup />
            </div>
            <p className={styles.caption}>Desktop · Layout estruturado</p>
          </div>

          {/* Mobile card */}
          <div className={styles.card}>
            <div className={`${styles.cardInner} ${styles.cardCenter}`}>
              <MobileMockup />
            </div>
            <p className={styles.caption}>Mobile · Responsivo</p>
          </div>
        </div>
      </div>
    </div>
  )
}
