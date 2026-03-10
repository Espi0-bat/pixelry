import { useRevealContainer } from '../hooks/useReveal'
import styles from './Servicos.module.css'

const SERVICES = [
  {
    num: '01',
    title: 'Sites de Alta Conversão',
    body: 'Não construímos páginas — construímos ativos digitais. Cada site é projetado para comunicar autoridade, eliminar objeções e converter visitantes em clientes qualificados antes do primeiro contato direto.',
    badge: null,
    wide: false,
  },
  {
    num: '02',
    title: 'Posicionamento de Marca Digital',
    body: 'Unificamos todos os pontos de contato digitais — site, perfis, identidade visual e comunicação — em uma presença coesa que transmite o padrão real do seu negócio e justifica o preço que você cobra.',
    badge: null,
    wide: false,
  },
  {
    num: '03',
    title: 'Consultoria Estratégica e RPA',
    body: 'Auditamos sua presença atual, identificamos as lacunas que estão custando clientes e entregamos um plano de ação claro. Com certificação em automação de processos (RPA), integramos eficiência operacional à sua estratégia digital.',
    badge: 'CERTIFICADO RPA',
    wide: false,
  },
  {
    num: '04',
    title: 'Tráfego Pago com Destino Qualificado',
    body: 'Campanhas estratégicas ativadas apenas quando a estrutura está sólida. Investimento direcionado para o público certo, com páginas preparadas para converter — não apenas atrair cliques.',
    badge: 'EXPANSÃO',
    wide: true,
  },
  {
    num: '05',
    title: 'Gestão de Marca nas Redes',
    body: 'Consistência visual e estratégica em cada publicação. Não vendemos volume de conteúdo — entregamos presença de marca que reforça autoridade e mantém seu negócio relevante para quem já é cliente e para quem ainda vai ser.',
    badge: 'SOB CONSULTA',
    wide: false,
  },
]

export default function Servicos() {
  const ref = useRevealContainer()

  return (
    <section id="servicos">
      <div className="section-wrap" ref={ref}>
        <div className="reveal">
          <span className="label">SOLUÇÕES</span>
          <h2 className={styles.h2}>
            Cada entrega é projetada para gerar<br />
            credibilidade, autoridade e resultado.
          </h2>
        </div>

        <div className={styles.grid}>
          {SERVICES.map((s, i) => (
            <article
              key={s.num}
              className={`${styles.card} ${s.wide ? styles.wide : ''} reveal reveal-d${(i % 3) + 1}`}
            >
              <span className={styles.num}>{s.num}</span>
              {s.badge && (
                <span className={`${styles.badge} ${s.badge === 'CERTIFICADO RPA' ? styles.badgeRpa : ''}`}>
                  {s.badge}
                </span>
              )}
              <h3 className={styles.title}>{s.title}</h3>
              <p className={styles.body}>{s.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}
