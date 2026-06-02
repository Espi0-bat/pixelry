import { useRevealContainer } from '../hooks/useReveal'
import styles from './Servicos.module.css'

const SERVICES = [
  {
    num: '01',
    title: 'PIXELRY CORE',
    body: 'A base de tudo. Uma landing page que não é só bonita — é construída para converter. Cada elemento tem função: o botão do WhatsApp está no lugar certo, o texto faz o lead entender por que você em 10 segundos, e o rastreamento diz exatamente de onde veio cada contato.',
    badge: 'ESTRUTURA PRINCIPAL',
    wide: false,
  },
  {
    num: '02',
    title: 'Rastreamento Técnico & Leitura de Dados',
    body: 'Rastreamento confiável como infraestrutura. Instalamos configurações de tags e eventos (GA4 & Meta Pixel) para você enxergar de onde vêm seus leads, permitindo decisões guiadas por dados reais, não intuições.',
    badge: null,
    wide: false,
  },
  {
    num: '03',
    title: 'Otimização de Google Meu Negócio (SEO Local)',
    body: 'Domínio nas pesquisas da sua região. Perfil completo com palavras-chave relevantes, conectando sua infraestrutura para garantir que clientes no momento de decisão encontrem você em vez da concorrência.',
    badge: null,
    wide: false,
  },
  {
    num: '04',
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
            O que construímos.<br />
            Por que funciona. Sem rodeios.
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
