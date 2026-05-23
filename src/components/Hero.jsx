import { useEffect, useRef } from 'react'
import styles from './Hero.module.css'
import { WA_LINK_HERO as WA_LINK, WaIconHero as WaIcon } from './common/WhatsApp'

export default function Hero() {
  const canvasRef = useRef(null)
  const mouseRef  = useRef({ x: 0.5, y: 0.5 })
  const targetRef = useRef({ x: 0.5, y: 0.5 })

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext('2d')
    const DOT_SPACING = 40
    const DOT_R = 1.4
    const GLOW_RADIUS = 200

    let dots = []
    let animId
    let time = 0

    function buildDots(W, H) {
      dots = []
      const cols = Math.ceil(W / DOT_SPACING) + 1
      const rows = Math.ceil(H / DOT_SPACING) + 1
      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
          dots.push({
            x: c * DOT_SPACING,
            y: r * DOT_SPACING,
            phase: Math.random() * Math.PI * 2,
            speed: 0.35 + Math.random() * 0.45,
          })
        }
      }
    }

    function resize() {
      canvas.width  = canvas.offsetWidth
      canvas.height = canvas.offsetHeight
      if (window.innerWidth <= 900) {
        dots = []
        return
      }
      buildDots(canvas.width, canvas.height)
    }

    function draw() {
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      if (dots.length === 0) {
        animId = requestAnimationFrame(draw)
        return
      }
      time += 0.010
      mouseRef.current.x += (targetRef.current.x - mouseRef.current.x) * 0.06
      mouseRef.current.y += (targetRef.current.y - mouseRef.current.y) * 0.06
      const mx = mouseRef.current.x * canvas.width
      const my = mouseRef.current.y * canvas.height

      for (const d of dots) {
        const wave  = Math.sin(time * d.speed + d.phase)
        let alpha   = 0.07 + wave * 0.04
        let radius  = DOT_R * (0.75 + wave * 0.25)
        const dx    = d.x - mx
        const dy    = d.y - my
        const dist  = Math.sqrt(dx * dx + dy * dy)
        if (dist < GLOW_RADIUS) {
          const t = 1 - dist / GLOW_RADIUS
          alpha  += t * 0.55
          radius += t * 1.4
        }
        ctx.beginPath()
        ctx.arc(d.x, d.y, radius, 0, Math.PI * 2)
        const hue   = 265 + (dist / GLOW_RADIUS) * 30
        const light = 70  - (dist / GLOW_RADIUS) * 20
        ctx.fillStyle = `hsla(${hue}, 90%, ${light}%, ${Math.min(alpha, 0.85)})`
        ctx.fill()
      }
      animId = requestAnimationFrame(draw)
    }

    const section = canvas.closest('section') || canvas.parentElement
    const onMove = (e) => {
      const rect = canvas.getBoundingClientRect()
      targetRef.current.x = (e.clientX - rect.left) / rect.width
      targetRef.current.y = (e.clientY - rect.top)  / rect.height
    }
    section.addEventListener('mousemove', onMove)
    const ro = new ResizeObserver(resize)
    ro.observe(canvas)
    resize()
    draw()

    return () => {
      cancelAnimationFrame(animId)
      ro.disconnect()
      section.removeEventListener('mousemove', onMove)
    }
  }, [])

  return (
    <section className={styles.hero}>
      <canvas ref={canvasRef} className={styles.canvas} aria-hidden="true" />
      <div className={styles.glow} aria-hidden="true" />

      <div className={styles.dashboardWrap} aria-hidden="true">
        <div className={styles.dashboard}>
          <div className={styles.dashHeader}>
            <span className={styles.dashTitle}>Desempenho de Aquisição</span>
            <span className={styles.dashStatus}>SISTEMA ATIVO</span>
          </div>
          <div className={styles.dashMetrics}>
            <div className={styles.dashMetric}>
              <div className={styles.dashMetricLabel}>Leads Qualificados</div>
              <div className={styles.dashMetricValue}>+34%</div>
            </div>
            <div className={styles.dashMetric}>
              <div className={styles.dashMetricLabel}>Custo por Aquisição</div>
              <div className={styles.dashMetricValue}>-18%</div>
            </div>
          </div>
          <div className={styles.dashChart}>
            <div className={styles.dashBar} />
            <div className={styles.dashBar} />
            <div className={styles.dashBar} />
            <div className={styles.dashBar} />
            <div className={styles.dashBar} />
            <div className={styles.dashBar} />
          </div>
        </div>
      </div>

      <div className={styles.content}>
        <p className={styles.eyebrow}>
          <span className={styles.eyebrowDot} />
          ESPECIALISTAS EM ESTRUTURAS DE AQUISIÇÃO PARA CLÍNICAS E NEGÓCIOS LOCAIS
        </p>

        <h1 className={styles.h1}>
          Transformamos a presença digital{' '}
          <br className={styles.brDesktop} />
          de empresas em uma estrutura que{' '}
          <br className={styles.brDesktop} />
          <span className="grad-text">gera clientes de forma previsível.</span>
        </h1>

        <p className={styles.sub}>
          Cansado de uma presença digital fragmentada que não traz retorno? Implementamos o sistema 
          técnico que organiza sua captação e enche sua agenda.
        </p>

        <div className={styles.ctas}>
          <div className={styles.ctaGroupPrimary}>
            <a href={WA_LINK} target="_blank" rel="noreferrer" className="btn-hero-cta">
              <WaIcon />
              Agendar Diagnóstico
            </a>
            
            <p className={styles.microcopy}>Análise técnica do seu funil atual. Resposta rápida.</p>
            
            <div className={styles.proof}>
              <span className={styles.proofDot} />
              Disponível em Brasília — DF
            </div>
          </div>

          <div className={styles.ctaGroupSecondary}>
            <a href="#servicos" className="btn-secondary" aria-label="Rolar para os serviços da Pixelry">
              Ver serviços ↓
            </a>
            <a href="#portal" className="btn-secondary btn-client-area" aria-label="Abrir área do cliente Pixelry">
              Área do Cliente
            </a>
          </div>
        </div>

        {/* Dashboard inline — visible only on mobile */}
        <div className={styles.dashboardMobile} aria-hidden="true">
          <div className={styles.dashHeader}>
            <span className={styles.dashTitle}>Desempenho de Aquisição</span>
            <span className={styles.dashStatus}>SISTEMA ATIVO</span>
          </div>
          <div className={styles.dashMetrics}>
            <div className={styles.dashMetric}>
              <div className={styles.dashMetricLabel}>Leads Qualificados</div>
              <div className={styles.dashMetricValue}>+34%</div>
            </div>
            <div className={styles.dashMetric}>
              <div className={styles.dashMetricLabel}>Custo por Aquisição</div>
              <div className={styles.dashMetricValue}>-18%</div>
            </div>
          </div>
          <div className={styles.dashChart}>
            <div className={styles.dashBar} />
            <div className={styles.dashBar} />
            <div className={styles.dashBar} />
            <div className={styles.dashBar} />
            <div className={styles.dashBar} />
            <div className={styles.dashBar} />
          </div>
        </div>

      </div>
    </section>
  )
}
