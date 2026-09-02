import { Code2, BarChart3, MapPin, TrendingUp } from 'lucide-react'
import { useRevealContainer } from '../hooks/useReveal'
import styles from './Servicos.module.css'

const SERVICES = [
  {
    num: '01',
    icon: Code2,
    title: 'PIXELRY CORE',
    body: 'A base de tudo. Uma landing page que não é só bonita — é construída para converter. Cada elemento tem função: o botão do WhatsApp está no lugar certo, o texto faz o lead entender por que você é a escolha certa em menos de 10 segundos, e o rastreamento diz exatamente de onde veio cada contato.',
    badge: 'ESTRUTURA PRINCIPAL',
    wide: false,
  },
  {
    num: '02',
    icon: BarChart3,
    title: 'Rastreamento Técnico & Leitura de Dados',
    body: 'Rastreamento confiável como infraestrutura. Instalamos GA4, Meta Pixel e GTM para você enxergar de onde vêm seus leads. Você para de adivinhar e começa a decidir com o que o dado diz.',
    badge: null,
    wide: false,
  },
  {
    num: '03',
    icon: MapPin,
    title: 'Perfil da Empresa no Google (SEO Local)',
    body: 'Domínio nas pesquisas da sua região. Perfil completo — o antigo Google Meu Negócio — com palavras-chave relevantes, conectado à sua infraestrutura para garantir que clientes no momento de decisão encontrem você em vez da concorrência.',
    badge: null,
    wide: false,
  },
  {
    num: '04',
    icon: TrendingUp,
    title: 'Tráfego Pago (PIXELRY ADS)',
    body: 'Aceleração estratégica ativada apenas quando o CORE está validado e funcional. Injetamos tráfego qualificado na sua estrutura para validar ofertas e escalar suas conversões sem investir no vazio.',
    badge: 'ACELERAÇÃO',
    wide: true,
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
            Cada serviço tem função.<br />
            Nenhum é decorativo.
          </h2>
        </div>

        <div className={styles.grid}>
          {SERVICES.map((s, i) => (
            <article
              key={s.num}
              className={`${styles.card} ${s.wide ? styles.wide : ''} reveal reveal-d${(i % 3) + 1}`}
            >
              <div className={styles.cardTop}>
                <span className={styles.num}>{s.num}</span>
                {s.badge && (
                  <span className={styles.badge}>{s.badge}</span>
                )}
              </div>
              <div className={styles.iconWrap} aria-hidden="true">
                <s.icon size={22} strokeWidth={1.5} />
              </div>
              <h3 className={styles.title}>{s.title}</h3>
              <p className={styles.body}>{s.body}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  )
}
