import { useEffect, useRef, useState } from 'react'
import { useRevealContainer } from '../hooks/useReveal'
import styles from './Numeros.module.css'

const METRICS = [
  { value: 18, suffix: '+', label: 'Projetos entregues' },
  { value: 100, suffix: '%', label: 'Entregas no prazo' },
  { value: 2,   suffix: 'h', label: 'Tempo médio de resposta' },
  { value: 3,   suffix: 'x', label: 'Média de crescimento de leads' },
]

function Counter({ value, suffix, duration = 1400 }) {
  const [count, setCount] = useState(0)
  const nodeRef = useRef(null)
  const started = useRef(false)

  useEffect(() => {
    const el = nodeRef.current
    if (!el) return
    const obs = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !started.current) {
          started.current = true
          const startTime = performance.now()
          const tick = (now) => {
            const elapsed = now - startTime
            const progress = Math.min(elapsed / duration, 1)
            const eased = 1 - Math.pow(1 - progress, 3)
            setCount(Math.round(eased * value))
            if (progress < 1) requestAnimationFrame(tick)
          }
          requestAnimationFrame(tick)
        }
      },
      { threshold: 0.5 }
    )
    obs.observe(el)
    return () => obs.disconnect()
  }, [value, duration])

  return (
    <span ref={nodeRef} className={styles.num}>
      {count}{suffix}
    </span>
  )
}

export default function Numeros() {
  const ref = useRevealContainer()

  return (
    <section className={styles.section}>
      <div className={styles.inner} ref={ref}>
        <div className={`${styles.header} reveal`}>
          <span className="label">RESULTADOS</span>
          <h2 className={styles.h2}>
            Números que<br />
            <span className="grad-text">falam por si só.</span>
          </h2>
          <p className={styles.sub}>
            Cada projeto entregue é a prova de que engenharia
            digital séria gera resultado mensurável.
          </p>
        </div>

        <div className={styles.grid}>
          {METRICS.map((m, i) => (
            <div
              key={m.label}
              className={`${styles.card} reveal reveal-d${i + 1}`}
            >
              <Counter value={m.value} suffix={m.suffix} />
              <span className={styles.cardLabel}>{m.label}</span>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
