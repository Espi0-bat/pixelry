import { useRevealContainer } from '../hooks/useReveal'
import styles from './ParaQuem.module.css'

const SEGMENTS = [
  'Clínicas e consultórios',
  'Escritórios e prestadores',
  'Cafeterias e restaurantes',
  'Barbearias e salões premium',
  'Estúdios e espaços criativos',
  'Marcas locais em expansão',
]

export default function ParaQuem() {
  const ref = useRevealContainer()

  return (
    <section>
      <div className="section-wrap" ref={ref}>
        <div className={styles.grid}>
          <div className="reveal">
            <span className="label">PERFIL IDEAL</span>
            <h2 className={styles.h2}>
              Para negócios com substância que ainda não têm a presença digital que merecem.
            </h2>
            <p className={styles.sub}>
              Se você tem clientes satisfeitos, um serviço de alto padrão e uma reputação
              construída com consistência — mas sua presença digital ainda não comunica
              esse nível — é exatamente esse gap que a PIXELRY resolve.
            </p>
          </div>

          <div className={`${styles.segGrid} reveal reveal-d2`}>
            {SEGMENTS.map((s) => (
              <div key={s} className={styles.seg}>
                {s}
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
