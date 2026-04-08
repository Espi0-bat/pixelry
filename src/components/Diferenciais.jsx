import { useRevealContainer } from '../hooks/useReveal'
import styles from './Diferenciais.module.css'

const ITEMS = [
  {
    title: 'Especialização, não generalismo',
    body: 'Atendemos exclusivamente negócios locais que precisam de presença digital com padrão premium. Essa escolha deliberada nos permite entregar com profundidade o que agências generalistas entregam superficialmente.',
    wide: false,
  },
  {
    title: 'Engenharia aplicada, não enfeite visual',
    body: 'Cada decisão nossa tem função comercial. Não tratamos páginas como artes — as tratamos como máquinas de atração de agenda. Construímos estruturas de rastreamento que justificam o seu investimento com dados reais.',
    wide: false,
  },
  {
    title: 'Processo sem ambiguidade',
    body: 'Etapas claras, prazos reais, comunicação direta. Nenhum jargão de agência. Nenhuma reunião sem propósito. Você sabe exatamente em que estágio seu projeto está em cada momento.',
    wide: false,
  },
  {
    title: 'Parceria orientada a resultados',
    body: 'Não entregamos um site e encerramos o contato. Somos uma empresa de tecnologia que realiza a leitura dos dados do que constrói — porque o sistema digital precisa evoluir e escalar as suas vendas continuamente.',
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
            Somos a estrutura que traz previsibilidade.
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
