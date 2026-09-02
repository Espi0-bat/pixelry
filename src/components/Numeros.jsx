import { useEffect, useRef, useState } from 'react'
import { useRevealContainer } from '../hooks/useReveal'
import styles from './Numeros.module.css'

// Números conferidos com a operação. Antes eram "18+ projetos" e "3x média de
// crescimento de leads" — o primeiro sem apuração, o segundo uma afirmação
// sobre resultado do cliente que nada no site sustentava.
//
// Todas as quatro falam da PIXELRY, não do cliente. Falta aqui uma métrica de
// resultado (agendamentos, custo por lead, conversão) — seria a única da página
// que prova o efeito do sistema, e não a competência do fornecedor.
const METRICS = [
  { value: 10,  suffix: '+', label: 'Projetos entregues' },
  { value: 2,   suffix: '',  label: 'Cases de sucesso' },
  { value: 100, suffix: '%', label: 'Entregas no prazo' },
  { value: 2,   suffix: 'h', label: 'Tempo médio de resposta' },
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
          {/* Era "RESULTADOS" e "gera resultado mensurável". Nenhuma das quatro
              métricas mede resultado do cliente — todas medem como a PIXELRY
              entrega. O rótulo agora diz o que os números realmente são. */}
          <span className="label">NOSSA OPERAÇÃO</span>
          <h2 className={styles.h2}>
            Números que<br />
            <span className="grad-text">falam por si só.</span>
          </h2>
          <p className={styles.sub}>
            Projeto entregue no prazo combinado e resposta rápida quando
            você precisa. Sem isso, nenhum sistema de aquisição se sustenta.
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
