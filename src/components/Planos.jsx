import { useState } from 'react'
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
    ]
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
    ]
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
    ]
  }
]

export default function Planos() {
  const ref = useRevealContainer()
  const [activeIndex, setActiveIndex] = useState(1); // Começa com o plano PRO (meio) em destaque

  const nextSlide = () => {
    setActiveIndex((prev) => (prev + 1) % PLANOS.length);
  };

  const prevSlide = () => {
    setActiveIndex((prev) => (prev - 1 + PLANOS.length) % PLANOS.length);
  };

  const getPositionClass = (index) => {
    const diff = index - activeIndex;
    
    // Matemática para a posição no coverflow circular
    if (diff === 0) return styles.activeConfig;
    if (diff === 1 || (diff === -(PLANOS.length - 1))) return styles.rightConfig;
    if (diff === -1 || (diff === PLANOS.length - 1)) return styles.leftConfig;
    
    return styles.hiddenConfig; // Para projetos adicionais (se > 3 itens no futuro)
  };

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

        <div className={`${styles.carouselContainer} reveal reveal-d1`}>
          <div className={styles.carouselCards}>
            {PLANOS.map((p, i) => {
              const positionClass = getPositionClass(i);
              const isDestaque = i === activeIndex;

              return (
                 // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
                <div 
                  key={p.nome} 
                  className={`${styles.cardCover} ${positionClass}`}
                  onClick={() => setActiveIndex(i)}
                >
                  <div className={`${styles.card} ${isDestaque ? styles.destaque : ''}`}>
                    {p.nome === 'PRO' && <div className={styles.badge}>MAIS RECOMENDADO</div>}
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
                    {isDestaque && (
                      <a 
                        href={`https://wa.me/556193720900?text=${encodeURIComponent('Olá Erick! Quero saber mais sobre a implementação do plano ' + p.nome + '.')}`} 
                        target="_blank" 
                        rel="noreferrer" 
                        className={styles.btn}
                      >
                        Aplicar para o plano {p.nome} →
                      </a>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
          
          <div className={styles.navControls}>
            <button className={styles.navBtn} onClick={prevSlide} aria-label="Plano anterior">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="15 18 9 12 15 6"></polyline>
              </svg>
            </button>
            <button className={styles.navBtn} onClick={nextSlide} aria-label="Próximo plano">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="9 18 15 12 9 6"></polyline>
              </svg>
            </button>
          </div>
        </div>
      </div>
    </section>
  )
}
