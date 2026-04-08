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
              Muitos negócios têm demanda retida e agendas com buracos simplesmente por falha de infraestrutura digital.
            </h2>
            <p className={styles.body}>
              Não é falta de mercado. É falta de sistema. Clínicas e negócios de alto 
              padrão perdem diariamente visitantes que não viram contatos, desperdiçam 
              leads por falhas ou fricções de jornada, e continuam reféns de indicações boca a boca.
              Quando a presença digital não é tratada como um sistema de aquisição previsível, 
              você perde clientes para concorrentes muito menos qualificados, porém mais organizados.
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
