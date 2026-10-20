import { useEffect, useRef, useState } from 'react'
import styles from './Hero.module.css'
import { WA_LINK_HERO as WA_LINK } from './common/WhatsApp'
import LeadCaptureModal from './LeadCaptureModal'

const PHRASE = 'antes da consulta.'

function Typewriter() {
  const [text, setText] = useState(PHRASE)
  useEffect(() => {
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)')
    let timer
    let position = 0
    let deleting = false
    const tick = () => {
      position += deleting ? -1 : 1
      setText(PHRASE.slice(0, position))
      let delay = deleting ? 45 : 105
      if (position === PHRASE.length) { deleting = true; delay = 3600 }
      if (position === 0) { deleting = false; delay = 650 }
      timer = window.setTimeout(tick, delay)
    }
    const start = () => {
      window.clearTimeout(timer)
      if (preference.matches) { setText(PHRASE); return }
      position = 0
      deleting = false
      setText('')
      timer = window.setTimeout(tick, 450)
    }
    start()
    preference.addEventListener('change', start)
    return () => { window.clearTimeout(timer); preference.removeEventListener('change', start) }
  }, [])
  return <em className={styles.accent}>
    <span className={styles.screenReader}>{PHRASE}</span>
    <span className={styles.typeSlot} aria-hidden="true">
      <span className={styles.typeMeasure}>{PHRASE}</span>
      <span className={styles.typeText}>{text}<span className={styles.caret} /></span>
    </span>
  </em>
}

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
    if (!ctx) return
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
      cancelAnimationFrame(animId)
      canvas.width  = canvas.offsetWidth
      canvas.height = canvas.offsetHeight
      if (window.innerWidth <= 900) {
        dots = []
        return
      }
      buildDots(canvas.width, canvas.height)
      draw()
    }

    function draw() {
      ctx.clearRect(0, 0, canvas.width, canvas.height)
      if (dots.length === 0) {
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

    return () => {
      cancelAnimationFrame(animId)
      ro.disconnect()
      section.removeEventListener('mousemove', onMove)
    }
  }, [])


  return (
    <section className={styles.hero} aria-labelledby="hero-title">
      <canvas ref={canvasRef} className={styles.canvas} aria-hidden="true" />
      <div className={styles.glow} aria-hidden="true" />
      <div className={styles.cyanGlow} aria-hidden="true" />
      <div className={styles.content}>
        <p className={styles.eyebrow}><span /> Estratégia digital para clínicas</p>
        <h1 id="hero-title" className={styles.h1}>
          O cuidado começa<br />
          <Typewriter />
        </h1>
        <p className={styles.sub}>
          Aproximamos sua clínica de quem precisa dela.<br className={styles.desktopBreak} />
          Com estratégia, design e uma presença digital que inspira confiança.
        </p>

        <div className={styles.ctas}>
          <button type="button" onClick={() => setModalOpen(true)} className={styles.primary}>
            Vamos conversar <span aria-hidden="true">↗</span>
          </button>
          <a href="#projeto-destaque" className={styles.secondary}>
            Conheça nossos projetos <span aria-hidden="true">↓</span>
          </a>
        </div>
      </div>

      <LeadCaptureModal isOpen={modalOpen} onClose={() => setModalOpen(false)} waLink={WA_LINK} source="hero_cta" />
    </section>
  )
}
