import { useRevealContainer } from '../hooks/useReveal'
import styles from './Planos.module.css'

const PLANOS = [
  {
    nome: 'START',
    desc: 'Sistema de aquisição inicial para negócios locais. Focado em validação e estruturação básica de presença digital.',
    setup: 'R$ 1.497',
    recorrencia: 'R$ 397/mês',
    setupFeatures: [
      'PIXELRY CORE (Base)',
      'Integração direta WhatsApp',
      'Configuração Rastreamento'
    ],
    recorrenciaFeatures: [
      'Hospedagem e Manutenção',
      'Monitoramento de Rastreamento',
      'Relatório de Performance'
    ],
    destaque: false
  },
  {
    nome: 'PRO',
    desc: 'Máquina de aquisição previsível. A estrutura definitiva para negócios que precisam escalar a captação de leads e a agenda.',
    setup: 'R$ 2.997',
    recorrencia: 'R$ 497/mês',
    setupFeatures: [
      'PIXELRY CORE (Alta Conversão)',
      'Setup de SEO e Google Meu Negócio',
      'Rastreamento Avançado (Pixel/GA4)'
    ],
    recorrenciaFeatures: [
      'Leitura Contínua de Dados',
      'Otimização de Conversão',
      'Reunião Estratégica Mensal'
    ],
    destaque: true
  },
  {
    nome: 'ELITE',
    desc: 'Infraestrutura premium para clínicas e empresas consolidadas com alto volume de captação e escala constante.',
    setup: 'R$ 4.997',
    recorrencia: 'R$ 997/mês',
    setupFeatures: [
      'Múltiplas LPs Estratégicas',
      'Automações e Fluxos Dedicados',
      'Criação de Painel de Dados'
    ],
    recorrenciaFeatures: [
      'Lapidação Contínua de Funil',
      'Monitoramento Executivo',
      'Acompanhamento Quinzenal/Prioritário'
    ],
    destaque: false
  }
]

export default function Planos() {
  const ref = useRevealContainer()

  return (
    <section id="planos">
      <div className="section-wrap" ref={ref}>
        <div className="reveal" style={{ textAlign: 'center' }}>
          <span className="label" style={{ justifyContent: 'center' }}>ENGENHARIA E PRECIFICAÇÃO</span>
          <h2 className={styles.h2}>
            Planos estruturados para gerar<br />
            previsibilidade no seu negócio.
          </h2>
        </div>

        <div className={styles.grid}>
          {PLANOS.map((p, i) => (
            <div key={p.nome} className={`${styles.card} ${p.destaque ? styles.destaque : ''} reveal reveal-d${(i % 3) + 1}`}>
              {p.destaque && <div className={styles.badge}>MAIS RECOMENDADO</div>}
              <h3 className={styles.nome}>{p.nome}</h3>
              <p className={styles.desc}>{p.desc}</p>
              <div className={styles.valores}>
                <div className={styles.valorItem}>
                  <span>Setup</span>
                  <strong>{p.setup}</strong>
                </div>
                <div className={styles.valorItem}>
                  <span>Acompanhamento</span>
                  <strong>{p.recorrencia}</strong>
                </div>
              </div>
              <div className={styles.featuresWrapper}>
                <div className={styles.featuresGroup}>
                  <p className={styles.featureTitle}>INCLUSO NO SETUP:</p>
                  <ul className={styles.features}>
                    {p.setupFeatures.map(f => (
                      <li key={f}>{f}</li>
                    ))}
                  </ul>
                </div>
                <div className={styles.featuresGroup}>
                  <p className={styles.featureTitle}>NA MENSALIDADE:</p>
                  <ul className={styles.features}>
                    {p.recorrenciaFeatures.map(f => (
                      <li key={f}>{f}</li>
                    ))}
                  </ul>
                </div>
              </div>
              <a href={`https://wa.me/556193720900?text=${encodeURIComponent('Olá Erick! Quero saber mais sobre a implementação do plano ' + p.nome + '.')}`} target="_blank" rel="noreferrer" className={styles.btn}>
                Aplicar para o plano {p.nome} →
              </a>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
