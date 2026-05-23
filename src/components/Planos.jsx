import { useState } from 'react'
import { useRevealContainer } from '../hooks/useReveal'
import { buildWhatsAppLink } from '../config/contact'
import styles from './Planos.module.css'

const PLANOS = [
  {
    nome: 'START',
    desc: 'Máquina de conversão rápida e direta. Ideal para profissionais e negócios que buscam validação através de uma infraestrutura digital robusta.',
    setup: 'R$ 2.500,00',
    recorrencia: 'R$ 250,00/mês',
    setupFeatures: [
      'Landing Page em React/Vite (01 página)',
      'Design focado em conversão mobile',
      'Tagueamento estrutural (Pixel e GA4)',
      'Botão de WhatsApp inteligente'
    ],
    recorrenciaFeatures: [
      'Cloud Hosting Premium de Alta Performance',
      'Hub PIXELRY: Dashboard de Métricas Essenciais',
      'Manutenção Preventiva e Suporte Técnico Especializado'
    ]
  },
  {
    nome: 'PRO',
    desc: 'O padrão de agência premium. Engenharia avançada para clínicas médicas, estéticas e hotelaria que exigem escala, dados e autoridade.',
    setup: 'R$ 3.800,00',
    recorrencia: 'R$ 400,00/mês',
    setupFeatures: [
      'Layout premium (Bento Grid e Parallax)',
      'Design editorial exclusivo',
      'Engenharia de Tagueamento (API Meta)',
      'Setup do Ecossistema Logado'
    ],
    recorrenciaFeatures: [
      'Hub PIXELRY Pro: Portal do Cliente com Criptografia',
      'Analytics Avançado: Dados e Conversões em Tempo Real',
      'Gestão Centralizada de Demandas e Abertura de Chamados'
    ]
  },
  {
    nome: 'ELITE',
    desc: 'A infraestrutura definitiva de Vendas. O ecossistema completo para operações de alto volume e consolidação de mercado.',
    setup: 'R$ 5.000,00',
    recorrencia: 'R$ 900,00/mês',
    setupFeatures: [
      'Toda a arquitetura do pacote PRO',
      'Auditoria de leads e atendimento comercial',
      'Desenvolvimento de Scripts de Vendas (WhatsApp)'
    ],
    recorrenciaFeatures: [
      'Hub PIXELRY Elite: O Ecossistema Definitivo',
      'Data Room Privada e Auditoria de Tráfego/Leads',
      'Engenharia de Elite com SLA de Atendimento Prioritário (< 24h)',
      'Consultoria Estratégica Executiva (Reunião Mensal)'
    ]
  }
]

export default function Planos() {
  const ref = useRevealContainer()
  const [activeIndex, setActiveIndex] = useState(1); // Começa com o plano PRO (meio) em destaque

  // --- SWIPE LOGIC ---
  const [touchStartX, setTouchStartX] = useState(null);
  const [touchEndX, setTouchEndX] = useState(null);
  const minSwipeDistance = 50;

  const onTouchStart = (e) => {
    setTouchEndX(null);
    setTouchStartX(e.targetTouches[0].clientX);
  };

  const onTouchMove = (e) => {
    setTouchEndX(e.targetTouches[0].clientX);
  };

  const onTouchEnd = () => {
    if (!touchStartX || !touchEndX) return;
    const distance = touchStartX - touchEndX;
    const isLeftSwipe = distance > minSwipeDistance;
    const isRightSwipe = distance < -minSwipeDistance;
    
    if (isLeftSwipe) {
      nextSlide();
    } else if (isRightSwipe) {
      prevSlide();
    }
  };

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
          <div 
            className={styles.carouselCards}
            onTouchStart={onTouchStart}
            onTouchMove={onTouchMove}
            onTouchEnd={onTouchEnd}
          >
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
                        <p className={styles.featureTitle}>ACOMPANHAMENTO MENSAL:</p>
                        <ul className={styles.features}>
                          {p.recorrenciaFeatures.map(f => (
                            <li key={f}>{f}</li>
                          ))}
                        </ul>
                      </div>
                    </div>
                    {isDestaque && (
                      <a 
                        href={buildWhatsAppLink('Olá Erick! Quero saber mais sobre a implementação do plano ' + p.nome + '.')} 
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
