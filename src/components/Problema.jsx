import { useRevealContainer } from '../hooks/useReveal'
import styles from './Problema.module.css'

export default function Problema() {
  const ref = useRevealContainer()

  return (
    <section>
      <div className="section-wrap" ref={ref}>
        <div className={styles.grid}>
          <div className="reveal">
            <span className="label">O DIAGNÓSTICO</span>
            <h2 className={styles.h2}>
              Um negócio pode ser referência no mercado e invisível no digital.
            </h2>
            <p className={styles.body}>
              Não é falta de qualidade. É lacuna de posicionamento digital. Clínicas,
              escritórios e estabelecimentos de alto padrão investem anos construindo
              reputação — e em segundos comprometem essa credibilidade quando um potencial
              cliente pesquisa o nome e encontra inconsistência de marca, ausência de site
              ou uma presença que não reflete o nível real do serviço entregue.
              O primeiro contato hoje é digital. E ele precisa converter antes de qualquer
              reunião ou ligação.
            </p>
          </div>

          <div className="reveal reveal-d2">
            <blockquote className={styles.quote}>
              <p>A percepção digital da sua marca está vendendo ou descartando clientes antes que você saiba que eles existiam.</p>
            </blockquote>
          </div>
        </div>
      </div>
    </section>
  )
}
