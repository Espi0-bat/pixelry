import { useState } from 'react'
import { useRevealContainer } from '../hooks/useReveal'
import styles from './Faq.module.css'

const FAQS = [
  {
    q: 'Quanto tempo leva para criar um site profissional?',
    a: 'Projetos completos levam entre 2 a 4 semanas, dependendo do escopo e da agilidade na troca de informações. Trabalhamos com cronograma claro desde a primeira reunião — sem prazo aberto.',
  },
  {
    q: 'Meu negócio é pequeno. Realmente preciso de um site?',
    a: 'O tamanho do negócio não define a necessidade de presença digital — o padrão do serviço define. Se você cobra bem e entrega bem, seu site precisa comunicar isso antes que o cliente te ligue. Um negócio pequeno com presença digital profissional parece maior e cobra mais com menos objeção.',
  },
  {
    q: 'Qual a diferença entre a PIXELRY e outras agências?',
    a: 'Agências genéricas atendem volume. Nós atendemos profundidade. Cada projeto passa por diagnóstico estratégico, é construído com código limpo e acompanhado após entrega. Não vendemos pacotes prontos — vendemos estrutura digital pensada para o seu negócio específico.',
  },
  {
    q: 'Vou precisar entender de tecnologia para gerenciar meu site?',
    a: 'Não. Entregamos o projeto funcional, treinamos você (ou sua equipe) nas partes que precisam de atualização rotineira e permanecemos disponíveis para suporte. O objetivo é que você gerencie o conteúdo sem depender de nós para cada pequena mudança.',
  },
  {
    q: 'Como funciona o processo de pagamento?',
    a: 'Trabalhamos com parcelamento em etapas: uma entrada para iniciar o projeto e o restante na entrega. Para projetos maiores, estruturamos o pagamento em fases conforme as entregas. Tudo documentado antes de começar.',
  },
  {
    q: 'E se eu não gostar do resultado?',
    a: 'Todo projeto tem rodadas de revisão definidas no contrato. Trabalhamos com aprovação etapa por etapa justamente para evitar surpresas no final. Se algo não estiver alinhado com o que foi acordado, ajustamos sem custo adicional.',
  },
]

export default function Faq() {
  const [open, setOpen] = useState(null)
  const ref = useRevealContainer()

  return (
    <section id="faq">
      <div className="section-wrap" ref={ref}>
        <div className="reveal">
          <span className="label">DÚVIDAS</span>
          <h2 className={styles.h2}>
            Perguntas que todo dono de negócio<br />
            faz antes de investir em digital.
          </h2>
        </div>

        <div className={styles.list}>
          {FAQS.map((faq, i) => {
            const isOpen = open === i
            return (
              <div
                key={i}
                className={`${styles.item} reveal reveal-d${(i % 3) + 1}`}
              >
                <button
                  className={styles.trigger}
                  onClick={() => setOpen(isOpen ? null : i)}
                  aria-expanded={isOpen}
                >
                  <span className={styles.q}>{faq.q}</span>
                  <span className={`${styles.icon} ${isOpen ? styles.iconOpen : ''}`}>
                    +
                  </span>
                </button>
                <div className={`${styles.body} ${isOpen ? styles.bodyOpen : ''}`}>
                  <p>{faq.a}</p>
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </section>
  )
}
