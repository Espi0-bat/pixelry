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
              Você tem clientes satisfeitos. Mas ainda depende de indicação.
            </h2>
            <p className={styles.body}>
              Isso não é problema de mercado — é problema de sistema.
              Clínicas que atendem bem perdem pacientes todo dia porque o site não
              converte, o botão do WhatsApp está escondido, e nenhum dado diz de
              onde vem (ou por que some) o lead.
              Você não precisa de mais seguidores. Precisa de uma estrutura que
              não perde ninguém que já demonstrou interesse.
            </p>
          </div>

          <div className="reveal reveal-d2">
            <blockquote className={styles.quote}>
              <p>Horários vazios e dependência excessiva de indicação são os sintomas mais caros de uma presença digital sem engenharia.</p>
            </blockquote>
          </div>
        </div>
      </div>
    </section>
  )
}
