import { useState } from 'react'
import { useRevealContainer } from '../hooks/useReveal'
import { buildWhatsAppLink } from '../config/contact'
import styles from './Planos.module.css'

const PLANOS = [
  {
    nome: 'START',
    desc: 'Para quem precisa de uma base sólida de captação digital. Estrutura de conversão pronta, rastreamento completo e WhatsApp integrado. Sem enrolação.',
    setup: 'R$ 2.500,00',
    recorrencia: 'R$ 387,00/mês',
    setupFeatures: [
      'Landing Page em React/Vite (01 página)',
      'Design focado em conversão mobile',
      'Tagueamento completo (Meta Pixel + GA4 + GTM)',
      'Botão de WhatsApp com mensagem pré-redigida'
    ],
    recorrenciaFeatures: [
      'Hospedagem cloud gerenciada pela PIXELRY',
      'Manutenção técnica: formulários, tracking e WhatsApp ativos',
      'Suporte técnico em dias úteis (SLA 24h úteis)'
    ]
  },
  {
    nome: 'PRO',
    desc: 'Para clínicas e negócios que querem mais do que um site — um sistema com acompanhamento ativo, otimização contínua e consultoria mensal.',
    setup: 'R$ 3.800,00',
    recorrencia: 'R$ 497,00/mês',
    setupFeatures: [
      'Site com até 4 páginas (principal + complementares)',
      'Tagueamento avançado com eventos customizados por conversão',
      'Google Meu Negócio — revisão e otimização completa',
      'Performance técnica premium (React · mobile-first · animações)'
    ],
    recorrenciaFeatures: [
      'CRO — Monitoramento e Otimização de Conversão mensal',
      'Auditoria de Tracking (Meta Pixel + GA4 verificados todo mês)',
      'Consultoria Mensal: Call de 1h + Relatório + Briefing pós-call',
      'Hospedagem premium e infraestrutura gerenciada'
    ]
  },
  {
    nome: 'ELITE',
    desc: 'Para quem quer a PIXELRY como parceira estratégica completa. Acesso direto aos sócios, mentoria de vendas, roadmap trimestral e testes A/B ativos.',
    setup: 'R$ 5.000,00',
    recorrencia: 'R$ 1.500,00/mês',
    setupFeatures: [
      'Site completo com múltiplas landing pages',
      'Backend, APIs e integrações customizadas',
      'Tagueamento avançado de alto nível + experiência visual premium',
      'Automações de resposta e sistema de agendamento online'
    ],
    recorrenciaFeatures: [
      'Tudo do PRO + Contato direto prioritário (SLA até 2h úteis)',
      'Roadmap Trimestral de Crescimento Estruturado',
      'Testes A/B Ativos com relatório de resultado',
      'Mentoria de Vendas com Erick + Reuniões Semanais Opcionais'
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
            O que construímos.<br />
            Por que funciona. Sem rodeios.
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
                <button
                  key={p.nome}
                  type="button"
                  className={`${styles.cardCover} ${positionClass}`}
                  onClick={() => setActiveIndex(i)}
                  aria-pressed={i === activeIndex}
                  aria-label={`Ver plano ${p.nome}`}
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
                </button>
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
