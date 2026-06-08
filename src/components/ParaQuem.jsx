import { useRevealContainer } from '../hooks/useReveal'
import styles from './ParaQuem.module.css'

const SEGMENTS = [
  'Clínicas Médicas',
  'Dentistas e Odontologia',
  'Clínicas de Estética Avançada',
  'Profissionais Liberais',
  'Consultoria de Alto Ticket',
  'Negócios Locais com Agenda',
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
              Para quem já é bom no que faz, mas o site não mostra isso.
            </h2>
            <p className={styles.sub}>
              Você atende bem. Seus clientes voltam. Você recebe indicação.
              Mas se alguém te pesquisar no Google agora — o que vai aparecer?
              É isso que resolvemos.
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
