import { useCallback, useEffect, useRef, useState } from 'react'
import { useRevealContainer } from '../hooks/useReveal'
import styles from './Transformacao.module.css'

const ANTES = [
  'Agenda com buracos toda semana',
  'Lead chega e ninguém responde a tempo',
  'Indicação como único canal de paciente novo',
  'Zero rastreamento — ninguém sabe o que funciona',
  'Marketing decidido no feeling',
]

const DEPOIS = [
  'Sistema de captação rodando 24h',
  'Atendimento automatizado responde na hora',
  'Tráfego qualificado em fluxo constante',
  'Cada real investido rastreado ponta a ponta',
  'Decisão guiada por dado real',
]

// Distância mínima antes de assumir que o gesto é um arraste, não uma rolagem.
const DRAG_THRESHOLD = 8

export default function Transformacao() {
  const ref = useRevealContainer()
  const mediaRef = useRef(null)
  const [pos, setPos] = useState(50)
  const draggingRef = useRef(false)
  const originRef = useRef(null)

  const updateFromClientX = useCallback((clientX) => {
    const el = mediaRef.current
    if (!el) return
    const rect = el.getBoundingClientRect()
    const pct = ((clientX - rect.left) / rect.width) * 100
    setPos(Math.max(0, Math.min(100, pct)))
  }, [])

  useEffect(() => {
    const onMove = (e) => {
      const origin = originRef.current
      if (!origin) return

      // Em toque o gesto ainda é ambíguo: só assume o controle quando o
      // movimento é claramente horizontal, senão a página deixa de rolar.
      if (!draggingRef.current) {
        const dx = Math.abs(e.clientX - origin.x)
        const dy = Math.abs(e.clientY - origin.y)
        if (dx < DRAG_THRESHOLD || dx <= dy) return
        draggingRef.current = true
      }

      if (e.cancelable) e.preventDefault()
      updateFromClientX(e.clientX)
    }
    const onUp = () => {
      draggingRef.current = false
      originRef.current = null
    }

    window.addEventListener('pointermove', onMove, { passive: false })
    window.addEventListener('pointerup', onUp)
    window.addEventListener('pointercancel', onUp)
    return () => {
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
      window.removeEventListener('pointercancel', onUp)
    }
  }, [updateFromClientX])

  const onMediaPointerDown = (e) => {
    originRef.current = { x: e.clientX, y: e.clientY }
    // Com mouse a intenção já é inequívoca — salta direto para o ponto clicado.
    if (e.pointerType === 'mouse') {
      draggingRef.current = true
      updateFromClientX(e.clientX)
    }
  }

  // Tocar no próprio divisor é intenção explícita de arrastar.
  const onHandlePointerDown = (e) => {
    e.stopPropagation()
    originRef.current = { x: e.clientX, y: e.clientY }
    draggingRef.current = true
  }

  const onKeyDown = (e) => {
    if (e.key === 'ArrowLeft')  { setPos(p => Math.max(0, p - 5));   e.preventDefault() }
    if (e.key === 'ArrowRight') { setPos(p => Math.min(100, p + 5)); e.preventDefault() }
    if (e.key === 'Home')       { setPos(0);   e.preventDefault() }
    if (e.key === 'End')        { setPos(100); e.preventDefault() }
  }

  return (
    <section>
      <div className="section-wrap" ref={ref}>
        <div className={`${styles.header} reveal`}>
          <span className="label" style={{ justifyContent: 'center' }}>A TRANSFORMAÇÃO</span>
          <h2 className={styles.h2}>
            Arraste e veja a diferença.
          </h2>
          <p className={styles.sub}>
            De um lado, a rotina de quem depende de sorte. Do outro, a rotina de quem tem sistema.
          </p>
        </div>

        <div
          className={`${styles.media} reveal reveal-d2`}
          ref={mediaRef}
          onPointerDown={onMediaPointerDown}
        >
          <div className={styles.pane}>
            <span className={styles.tag}>Antes</span>
            <ul className={styles.list}>
              {ANTES.map(item => <li key={item} className={styles.itemAntes}>{item}</li>)}
            </ul>
          </div>

          <div
            className={`${styles.pane} ${styles.paneDepois}`}
            style={{ clipPath: `inset(0 ${100 - pos}% 0 0)` }}
          >
            <span className={`${styles.tag} ${styles.tagDepois}`}>Depois</span>
            <ul className={styles.list}>
              {DEPOIS.map(item => <li key={item} className={styles.itemDepois}>{item}</li>)}
            </ul>
          </div>

          <div
            className={styles.handle}
            style={{ left: `${pos}%` }}
            role="slider"
            tabIndex={0}
            aria-label="Comparar a rotina antes e depois da Pixelry"
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={Math.round(pos)}
            aria-valuetext={`${Math.round(pos)}% revelado do cenário depois`}
            onKeyDown={onKeyDown}
            onPointerDown={onHandlePointerDown}
          >
            <span className={styles.grip} aria-hidden="true">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="15 18 9 12 15 6" transform="translate(-3 0)" />
                <polyline points="9 18 15 12 9 6" transform="translate(3 0)" />
              </svg>
            </span>
          </div>
        </div>
      </div>
    </section>
  )
}
