import { useEffect, useRef } from 'react'
import styles from './Hero.module.css'

const WA_LINK = 'https://wa.me/5561991410161?text=Olá!%20Vim%20pelo%20site%20da%20PIXELRY%20e%20gostaria%20de%20saber%20mais%20sobre%20os%20serviços.'

const WaIcon = () => (
  <svg className="wa-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347z"/>
    <path d="M12 0C5.373 0 0 5.373 0 12c0 2.127.558 4.126 1.528 5.857L.057 23.882a.5.5 0 0 0 .614.612l6.162-1.624A11.944 11.944 0 0 0 12 24c6.627 0 12-5.373 12-12S18.627 0 12 0zm0 22c-1.886 0-3.655-.523-5.168-1.43l-.369-.22-3.812 1.004 1.021-3.72-.24-.382A9.945 9.945 0 0 1 2 12C2 6.477 6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z"/>
  </svg>
)

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
      buildDots(canvas.width, canvas.height)
    }

    function draw() {
      ctx.clearRect(0, 0, canvas.width, canvas.height)
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

      <div className={styles.geoWrap} aria-hidden="true">
        <div className={`${styles.geo} ${styles.geo1}`} />
        <div className={`${styles.geo} ${styles.geo2}`} />
        <div className={`${styles.geo} ${styles.geo3}`} />
        <div className={`${styles.geo} ${styles.geo4}`} />
      </div>

      <div className={styles.content}>
        <p className={styles.eyebrow}>
          <span className={styles.eyebrowDot} />
          ESTÚDIO DIGITAL · BRASÍLIA — DF
        </p>

        <h1 className={styles.h1}>
          Sua marca já tem valor.<br />
          O digital precisa<br />
          <span className="grad-text">comunicar isso com precisão.</span>
        </h1>

        <p className={styles.sub}>
          Inconsistência de marca online custa clientes antes de qualquer conversa.
          A PIXELRY estrutura sua presença digital com metodologia, design estratégico
          e acompanhamento contínuo — para que cada ponto de contato converta.
        </p>

        <div className={styles.ctas}>
          <a href={WA_LINK} target="_blank" rel="noreferrer" className="btn-whatsapp">
            <WaIcon />
            Iniciar diagnóstico gratuito
          </a>
          <a href="#servicos" className="btn-secondary">
            Ver serviços ↓
          </a>
        </div>

        <div className={styles.proof}>
          <span className={styles.proofDot} />
          Disponível para novos projetos em Brasília — DF
        </div>
      </div>
    </section>
  )
}
