import { useRevealContainer } from '../hooks/useReveal'
import styles from './Diferenciais.module.css'

const ITEMS = [
  {
    title: 'Especialização, não generalismo',
    body: 'Atendemos exclusivamente negócios locais que precisam de presença digital com padrão premium. Essa escolha deliberada nos permite entregar com profundidade o que agências generalistas entregam superficialmente.',
    wide: false,
  },
  {
    title: 'Estética como instrumento estratégico',
    body: 'Cada decisão visual tem função comercial. Design não é decoração — é comunicação de autoridade. Construímos interfaces que justificam o preço que você cobra antes que qualquer palavra seja dita.',
    wide: false,
  },
  {
    title: 'Processo sem ambiguidade',
    body: 'Etapas claras, prazos reais, comunicação direta. Nenhum jargão de agência. Nenhuma reunião sem propósito. Você sabe exatamente em que estágio seu projeto está em cada momento.',
    wide: false,
  },
  {
    title: 'Parceria além da entrega',
    body: 'Não entregamos um projeto e encerramos o contato. Somos um estúdio que acompanha o que constrói — porque uma presença digital precisa evoluir junto com o negócio.',
    wide: false,
  },
  {
    title: 'Atenção total em cada projeto',
    body: 'Estamos em fase de crescimento estratégico — e é exatamente por isso que cada cliente recebe dedicação integral. Não existe fila de projetos no piloto automático aqui. Cada entrega é tratada como se fosse a única.',
    wide: true,
  },
]

export default function Diferenciais() {
  const ref = useRevealContainer()

  return (
    <section>
      <div className="section-wrap" ref={ref}>
        <div className="reveal">
          <span className="label">POSICIONAMENTO</span>
          <h2 className={styles.h2}>
            Não somos a agência que faz tudo.<br />
            Somos o estúdio que faz o que importa.
          </h2>
        </div>

        <div className={styles.grid}>
          {ITEMS.map((item, i) => (
            <div
              key={item.title}
              className={`${styles.item} ${item.wide ? styles.wide : ''} reveal reveal-d${(i % 2) + 1}`}
            >
              <span className={styles.dash}>—</span>
              <h3 className={styles.title}>{item.title}</h3>
              <p className={styles.body}>{item.body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
