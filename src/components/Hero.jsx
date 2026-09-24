import { useEffect, useRef, useState } from 'react'
import styles from './Hero.module.css'
import { WA_LINK_HERO as WA_LINK, WaIconHero as WaIcon } from './common/WhatsApp'
import LeadCaptureModal from './LeadCaptureModal'

const heroImage = `${import.meta.env.BASE_URL}assets/pixelry-recepcao.webp`

export default function Hero() {
  const [modalOpen, setModalOpen] = useState(false)
  const canvasRef = useRef(null)
  const mouseRef  = useRef({ x: 0.5, y: 0.5 })
  const targetRef = useRef({ x: 0.5, y: 0.5 })

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return
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
    <section className={styles.hero} aria-labelledby="hero-title">
      {/* Malha de pontos que acende sob o cursor e brilho pulsante: o efeito
          original do hero, preservado. Não roda em telas <=900px nem com
          prefers-reduced-motion. */}
      <canvas ref={canvasRef} className={styles.canvas} aria-hidden="true" />
      <div className={styles.glow} aria-hidden="true" />

      <div className={styles.content}>
        <p className={styles.eyebrow}>
          <span className={styles.pixel} aria-hidden="true" />
          MARKETING E PRESENÇA DIGITAL PARA CLÍNICAS
        </p>

        <h1 id="hero-title" className={styles.h1}>
          Conectamos sua clínica{' '}
          <span className={styles.highlight}>a quem precisa do seu cuidado.</span>
        </h1>

        <p className={styles.sub}>
          Unimos estratégia, design e tecnologia para sua clínica ser encontrada,
          transmitir confiança e transformar interesse em pedidos de agendamento.
        </p>

        <div className={styles.ctas}>
          <button type="button" onClick={() => setModalOpen(true)} className={`btn-hero-cta ${styles.primary}`}>
            <WaIcon />
            Quero um diagnóstico da minha clínica
          </button>
          <p className={styles.microcopy}>Vamos identificar o próximo passo para sua presença digital.</p>
          <a href="#cases" className={styles.projectLink}>
            Conheça nossos projetos <span aria-hidden="true">↗</span>
          </a>
        </div>
      </div>

      {/* O arquivo original tem bordas retas e margem escura embutidas; por isso
          a versão recortada, que fecha com a moldura em qualquer tamanho. */}
      <div className={styles.visual}>
        <img src={heroImage} width="726" height="546" alt="Cena conceitual de acolhimento na recepção de uma clínica" fetchpriority="high" loading="eager" />
      </div>

      <div className={styles.foot}>
        <span>PIXELRY <span className={styles.slash} aria-hidden="true">/</span> CADA CONEXÃO IMPORTA.</span>
        <span>ESTRATÉGIA · DESIGN · TECNOLOGIA — BRASÍLIA, DF</span>
      </div>

      <LeadCaptureModal isOpen={modalOpen} onClose={() => setModalOpen(false)} waLink={WA_LINK} source="hero_cta" />
    </section>
  )
}
