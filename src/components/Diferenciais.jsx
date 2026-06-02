import { useRevealContainer } from '../hooks/useReveal'
import styles from './Diferenciais.module.css'

const ITEMS = [
  {
    title: 'Especializados, não generalistas',
    body: 'Só atendemos negócios locais de serviço. Não tentamos fazer de tudo — então o que fazemos, fazemos bem.',
    wide: false,
  },
  {
    title: 'Engenharia aplicada, não enfeite visual',
    body: 'Cada decisão nossa tem função comercial. Não tratamos páginas como artes — as tratamos como máquinas de atração de agenda. Construímos estruturas de rastreamento que justificam o seu investimento com dados reais.',
    wide: false,
  },
  {
    title: 'Processo sem surpresa',
    body: 'Você sabe o que acontece em cada semana. Nenhuma entrega "surpresa". Nenhum prazo que some. Comunicamos o que está acontecendo porque você pagou para saber.',
    wide: false,
  },
  {
    title: 'Parceria orientada a resultados',
    body: 'Não entregamos um site e encerramos o contato. Somos uma empresa de tecnologia que realiza a leitura dos dados do que constrói — porque o sistema digital precisa evoluir e escalar as suas vendas continuamente.',
    wide: false,
  },
  {
    title: 'Não trabalhamos com todo mundo',
    body: 'Antes de fechar qualquer projeto, fazemos um diagnóstico. Se não fizer sentido para os dois lados, a gente fala abertamente. Sem pressão.',
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
            Trabalhamos com poucos clientes.<br />
            De propósito.
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
