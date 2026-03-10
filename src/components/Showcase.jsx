import { useRevealContainer } from '../hooks/useReveal'
import styles from './Showcase.module.css'

function DesktopMockup() {
  return (
    <div className={styles.browser}>
      <div className={styles.bar}>
        <span className={`${styles.dot} ${styles.dotRed}`}   />
        <span className={`${styles.dot} ${styles.dotYellow}`}/>
        <span className={`${styles.dot} ${styles.dotGreen}`} />
        <span className={styles.url} />
      </div>
      <div className={styles.browserBody}>
        <div className={styles.heroBlock} />
        <div className={styles.twoCol}>
          <div className={styles.block} />
          <div className={styles.block} />
          <div className={styles.blockSm} />
          <div className={styles.blockSm} />
          <div className={styles.blockSm} />
          <div className={styles.blockSm} />
        </div>
      </div>
    </div>
  )
}

function MobileMockup() {
  return (
    <div className={styles.phone}>
      <span className={styles.notch} />
      <div className={styles.phoneBody}>
        <div className={styles.pHero} />
        <div className={styles.pBlock} />
        <div className={styles.pBlockSm} />
        <div className={styles.pBlockSm} />
        <div className={styles.pBlock} />
        <div className={styles.pBlockSm} />
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
          <h2 className={styles.h2}>Este site é o nosso portfólio.</h2>
          <p className={styles.sub}>
            O padrão visual, a estrutura e a atenção ao detalhe que você vê aqui são o que levamos para cada projeto. Estamos construindo nossos primeiros casos com o mesmo nível de critério. Abaixo, a direção visual que orienta cada entrega da PIXELRY.
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
