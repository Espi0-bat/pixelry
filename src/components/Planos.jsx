import { useState } from 'react'
import { useRevealContainer } from '../hooks/useReveal'
import { buildWhatsAppLink } from '../config/contact'
import styles from './Planos.module.css'
import LeadCaptureModal from './LeadCaptureModal'

const WA_MESSAGES = {
  START: 'Oi Erick! Me interessei no plano START da Pixelry — landing page de conversão com rastreamento completo. Posso aplicar?',
  PRO:   'Oi Erick! Quero o plano PRO da Pixelry. Além do site, quero acompanhamento mensal, automação e consultoria. Podemos conversar sobre minha clínica?',
  ELITE: 'Oi Erick! Tenho interesse no plano ELITE da Pixelry. Quero a Pixelry como parceira estratégica completa. Quando podemos conversar?',
  AI:    'Oi Erick! Quero saber mais sobre o módulo de Agente de IA para WhatsApp da Pixelry. Podemos conversar?',
  ADS:   'Oi Erick! Quero saber mais sobre o PIXELRY ADS — gestão de tráfego pago. Podemos conversar?',
  SM:    'Oi Erick! Quero saber mais sobre o módulo de Social Media da Pixelry. Podemos conversar?',
}

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
    desc: 'Para clínicas que querem mais do que um site — um sistema com automação de atendimento, acompanhamento ativo e consultoria mensal.',
    setup: 'R$ 3.800,00',
    recorrencia: 'R$ 697,00/mês',
    setupFeatures: [
      'Site com até 4 páginas (principal + complementares)',
      'Tagueamento avançado com eventos customizados por conversão',
      'Perfil da Empresa no Google — revisão e otimização completa',
      'Performance técnica premium (React · mobile-first · animações)',
      'Atendimento automatizado — qualificação de lead e lembrete de consulta'
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
    setup: 'R$ 5.500,00',
    recorrencia: 'R$ 1.997,00/mês',
    setupFeatures: [
      'Site completo com múltiplas landing pages',
      'Backend, APIs e integrações customizadas',
      'Tagueamento avançado de alto nível + experiência visual premium',
      'Atendimento automatizado + sistema de agendamento online integrado'
    ],
    recorrenciaFeatures: [
      'Tudo do PRO + Contato direto prioritário (SLA até 2h úteis)',
      'Roadmap Trimestral de Crescimento Estruturado',
      'Testes A/B Ativos com relatório de resultado',
      'Mentoria de Vendas com Erick + Reuniões Semanais Opcionais',
      'Prioridade de acesso ao módulo Agente de IA'
    ]
  }
]

const MODULOS = [
  {
    key: 'AI',
    tag: 'NOVO',
    tagColor: 'cyan',
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2a2 2 0 0 1 2 2c0 .74-.4 1.39-1 1.73V7h1a7 7 0 0 1 7 7h1a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1h-1v1a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-1H2a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1h1a7 7 0 0 1 7-7h1V5.73A2 2 0 0 1 10 4a2 2 0 0 1 2-2z"/>
        <circle cx="7.5" cy="14.5" r="1.5"/>
        <circle cx="16.5" cy="14.5" r="1.5"/>
      </svg>
    ),
    nome: 'Agente de IA',
    subtitulo: 'Atendimento autônomo via WhatsApp',
    desc: 'O agente entende o contexto de cada conversa, qualifica o lead e encaminha no momento certo — sem depender de alguém disponível para responder.',
    bullets: [
      'Qualifica leads sem intervenção humana',
      'Responde 24h por dia, todos os dias',
      'Apoia o agendamento até a confirmação'
    ],
    requisito: 'Exclusivo para PRO e ELITE',
    cta: 'Quero o agente',
    waKey: 'AI'
  },
  {
    key: 'ADS',
    tag: null,
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M22 12h-4l-3 9L9 3l-3 9H2"/>
      </svg>
    ),
    nome: 'PIXELRY ADS',
    subtitulo: 'Tráfego pago gerenciado',
    desc: 'Campanhas no Meta Ads e Google Ads com estratégia, direção criativa e relatório mensal. O combustível que alimenta o sistema.',
    requisito: 'Requer o CORE ativo',
    cta: 'Quero tráfego',
    waKey: 'ADS'
  },
  {
    key: 'SM',
    tag: null,
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M18 2h-3a5 5 0 0 0-5 5v3H7v4h3v8h4v-8h3l1-4h-4V7a1 1 0 0 1 1-1h3z"/>
      </svg>
    ),
    nome: 'Social Media',
    subtitulo: 'Gestão de redes sociais',
    desc: 'Calendário editorial, produção de conteúdo e gestão das redes. Presença orgânica somada ao sistema de captação.',
    requisito: 'Complementa qualquer plano',
    cta: 'Quero conteúdo',
    waKey: 'SM'
  }
]

export default function Planos() {
  const ref = useRevealContainer()
  const [activeIndex, setActiveIndex] = useState(1)
  const [modalOpen, setModalOpen] = useState(false)
  const [currentPlan, setCurrentPlan] = useState(null)
  const [waMsg, setWaMsg] = useState('')

  const [touchStartX, setTouchStartX] = useState(null)
  const [touchEndX, setTouchEndX] = useState(null)
  const minSwipeDistance = 50

  const onTouchStart = (e) => { setTouchEndX(null); setTouchStartX(e.targetTouches[0].clientX) }
  const onTouchMove = (e) => { setTouchEndX(e.targetTouches[0].clientX) }
  const onTouchEnd = () => {
    if (!touchStartX || !touchEndX) return
    const distance = touchStartX - touchEndX
    if (distance > minSwipeDistance) nextSlide()
    else if (distance < -minSwipeDistance) prevSlide()
  }

  const nextSlide = () => setActiveIndex((prev) => (prev + 1) % PLANOS.length)
  const prevSlide = () => setActiveIndex((prev) => (prev - 1 + PLANOS.length) % PLANOS.length)

  const getPositionClass = (index) => {
    const diff = index - activeIndex
    if (diff === 0) return styles.activeConfig
    if (diff === 1 || diff === -(PLANOS.length - 1)) return styles.rightConfig
    if (diff === -1 || diff === PLANOS.length - 1) return styles.leftConfig
    return styles.hiddenConfig
  }

  const openModal = (planName, msgKey) => {
    setCurrentPlan(planName)
    setWaMsg(WA_MESSAGES[msgKey] || WA_MESSAGES[planName] || '')
    setModalOpen(true)
  }

  return (
    <section id="planos">
      <div className="section-wrap" ref={ref}>

        {/* Header */}
        <div className="reveal" style={{ textAlign: 'center' }}>
          <span className="label" style={{ justifyContent: 'center' }}>SISTEMA E INVESTIMENTO</span>
          <h2 className={styles.h2}>
            Três formas de estruturar.<br />
            Um único objetivo: agenda cheia.
          </h2>
        </div>

        {/* Coverflow carousel */}
        <div className={`${styles.carouselContainer} reveal reveal-d1`}>
          <div
            className={styles.carouselCards}
            onTouchStart={onTouchStart}
            onTouchMove={onTouchMove}
            onTouchEnd={onTouchEnd}
          >
            {PLANOS.map((p, i) => {
              const positionClass = getPositionClass(i)
              const isDestaque = i === activeIndex

              // Wrapper sempre <div>, nunca <button>: no desktop cada card
              // exibe o próprio CTA, e botão dentro de botão é HTML inválido.
              // O clique para trazer o card à frente é conveniência de ponteiro
              // do coverflow mobile — no teclado, quem navega são as setas.
              return (
                <div
                  key={p.nome}
                  className={`${styles.cardCover} ${positionClass} ${p.nome === 'PRO' ? styles.isPro : ''}`}
                  onClick={isDestaque ? undefined : () => setActiveIndex(i)}
                >
                <div className={`${styles.card} ${isDestaque ? styles.destaque : ''}`}>
                  {p.nome === 'PRO' && <div className={styles.badge}>MAIS RECOMENDADO</div>}
                  <h3 className={styles.nome}>{p.nome}</h3>
                  <p className={styles.desc}>{p.desc}</p>
                  <div className={styles.featuresWrapper}>
                    <div className={styles.featuresGroup}>
                      <p className={styles.featureTitle}>INCLUSO NO SETUP:</p>
                      <ul className={styles.features}>
                        {p.setupFeatures.map(f => <li key={f}>{f}</li>)}
                      </ul>
                    </div>
                    <div className={styles.featuresGroup}>
                      <p className={styles.featureTitle}>ACOMPANHAMENTO MENSAL:</p>
                      <ul className={styles.features}>
                        {p.recorrenciaFeatures.map(f => <li key={f}>{f}</li>)}
                      </ul>
                    </div>
                  </div>
                  {/* CTA sempre presente. No coverflow mobile os cards laterais
                      escondem o seu por CSS (visibility), o que também o tira da
                      ordem de tabulação. */}
                  <button
                    type="button"
                    className={styles.btn}
                    onClick={(e) => { e.stopPropagation(); openModal(p.nome, p.nome) }}
                  >
                    Aplicar para o plano {p.nome} →
                  </button>
                </div>
                </div>
              )
            })}
          </div>

          <div className={styles.navControls}>
            <button className={styles.navBtn} onClick={prevSlide} aria-label="Plano anterior">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="15 18 9 12 15 6"/>
              </svg>
            </button>
            <button className={styles.navBtn} onClick={nextSlide} aria-label="Próximo plano">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="9 18 15 12 9 6"/>
              </svg>
            </button>
          </div>
        </div>

        {/* Módulos Adicionais */}
        <div className={`${styles.modulosSection} reveal reveal-d2`}>
          <div className={styles.modulosHeader}>
            <span className={styles.modulosLabel}>MÓDULOS OPCIONAIS</span>
            <h3 className={styles.modulosTitle}>Amplie o sistema conforme o negócio cresce.</h3>
            <p className={styles.modulosSubtitle}>
              Módulos cobrados sempre em linha separada — nunca embutidos no plano. Cada um tem função específica dentro do sistema.
            </p>
          </div>

          <div className={styles.modulosGrid}>
            {MODULOS.map((m) => {
              const isHero = m.key === 'AI'

              return (
                <div
                  key={m.key}
                  className={`${styles.moduloCard} ${isHero ? styles.moduloHero : styles.moduloCompacto}`}
                >
                  {m.tag && (
                    <span className={`${styles.moduloTag} ${m.tagColor === 'cyan' ? styles.moduloTagCyan : ''}`}>
                      {m.tag}
                    </span>
                  )}

                  <div className={styles.moduloTopo}>
                    <div className={styles.moduloIcon}>{m.icon}</div>
                    <div className={styles.moduloTitulos}>
                      <h4 className={styles.moduloNome}>{m.nome}</h4>
                      <p className={styles.moduloSub}>{m.subtitulo}</p>
                    </div>
                  </div>

                  <p className={styles.moduloDesc}>{m.desc}</p>

                  {m.bullets && (
                    <ul className={styles.moduloBullets}>
                      {m.bullets.map(b => <li key={b}>{b}</li>)}
                    </ul>
                  )}

                  <div className={styles.moduloRodape}>
                    <span className={styles.moduloRequisito}>{m.requisito}</span>
                    <button
                      type="button"
                      className={styles.moduloBtn}
                      onClick={() => openModal(m.nome, m.waKey)}
                    >
                      {m.cta} →
                    </button>
                  </div>
                </div>
              )
            })}
          </div>
        </div>

      </div>

      <LeadCaptureModal
        isOpen={modalOpen}
        onClose={() => { setModalOpen(false); setCurrentPlan(null); setWaMsg('') }}
        waLink={waMsg ? buildWhatsAppLink(waMsg) : ''}
        source={currentPlan ? 'planos_' + currentPlan.toLowerCase().replace(/\s/g, '_') : 'planos'}
      />
    </section>
  )
}
