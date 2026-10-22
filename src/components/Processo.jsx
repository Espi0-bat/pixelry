import { useEffect, useRef } from 'react'
import styles from './Processo.module.css'

const STEPS = [
  {
    num: '01',
    letter: 'P',
    title: 'P - Posicionamento',
    body: 'Antes do visual, definimos a oferta, o público e a promessa principal. Sua página vira um ambiente de conversão quando o cliente entende imediatamente por que você é a escolha certa.',
    output: 'Oferta clara + público mapeado'
  },
  {
    num: '02',
    letter: 'I',
    title: 'I - Identidade',
    body: 'A estética é um instrumento de percepção de confiança. Uma identidade visual coerente faz o lead decidir que você é confiável antes mesmo de ler o texto.',
    output: 'Identidade visual de autoridade'
  },
  {
    num: '03',
    letter: 'X',
    title: 'X - Experiência',
    body: 'Reduzimos toda a fricção de navegação. Um layout confuso ou lento joga o cliente para trás. Nosso papel é tirar o que atrapalha o lead de clicar no botão de contato.',
    output: 'Jornada sem fricção até o contato'
  },
  {
    num: '04',
    letter: 'E',
    title: 'E - Estratégia',
    body: 'A estrutura é pensada no fechamento. Organizamos Copy, CTAs, gatilhos de prova social e a integração direta com automações básicas no seu canal principal (WhatsApp).',
    output: 'CTAs e fluxo de conversão ativos'
  },
  {
    num: '05',
    letter: 'L',
    title: 'L - Leitura e Lapidação',
    body: 'Sem dados, é intuição. Instalamos o rastreamento técnico (Pixel, GA4) para monitorar resultados e lapidar a estratégia continuamente — o sistema não termina no go-live, ele melhora todo mês.',
    output: 'Pixel + GA4 ativos · otimização contínua'
  },
]

export default function Processo() {
  const sceneRef = useRef(null)
  const stageRef = useRef(null)
  const viewportRef = useRef(null)
  const trackRef = useRef(null)

  useEffect(() => {
    const scene = sceneRef.current
    const stage = stageRef.current
    const viewport = viewportRef.current
    const track = trackRef.current
    const media = window.matchMedia('(min-width: 900px) and (min-height: 700px) and (prefers-reduced-motion: no-preference)')
    let distance = 0
    let frame = 0
    let enabled = false

    const paint = () => {
      frame = 0
      if (!enabled) return
      const top = parseFloat(getComputedStyle(stage).top)
      const travelled = Math.max(0, Math.min(distance, top - scene.getBoundingClientRect().top))
      track.style.transform = `translate3d(${-travelled}px, 0, 0)`
    }
    const schedule = () => {
      if (!frame) frame = window.requestAnimationFrame(paint)
    }
    const measure = () => {
      enabled = media.matches
      scene.dataset.motion = String(enabled)
      if (enabled) {
        distance = Math.max(0, track.scrollWidth - viewport.clientWidth)
        // Texto ampliado ou zoom nunca pode esconder as descrições abaixo da tela.
        enabled = distance > 0 && track.offsetHeight <= stage.clientHeight
      }
      scene.dataset.motion = String(enabled)
      if (enabled) {
        scene.style.height = `${stage.offsetHeight + distance}px`
      } else {
        scene.style.removeProperty('height')
        track.style.removeProperty('transform')
      }
      schedule()
    }
    const observer = new ResizeObserver(measure)
    observer.observe(viewport)
    observer.observe(track)
    window.addEventListener('scroll', schedule, { passive: true })
    window.addEventListener('resize', measure)
    media.addEventListener('change', measure)
    measure()
    return () => {
      window.cancelAnimationFrame(frame)
      observer.disconnect()
      window.removeEventListener('scroll', schedule)
      window.removeEventListener('resize', measure)
      media.removeEventListener('change', measure)
      scene.removeAttribute('data-motion')
      scene.style.removeProperty('height')
      track.style.removeProperty('transform')
    }
  }, [])

  return (
    <section className={styles.bg} id="processo" aria-labelledby="processo-title">
      <div className={styles.inner}>
        <header className={styles.header}>
          <span className="label">Método Pixel</span>
          <h2 className={styles.h2} id="processo-title">
            Um processo que elimina o improviso{' '}
            e garante <span className="type-accent">precisão em cada entrega.</span>
          </h2>
        </header>

        <div className={styles.scene} ref={sceneRef}>
          <div className={styles.stage} ref={stageRef}>
            <div className={styles.viewport} ref={viewportRef}>
              <ol className={styles.list} ref={trackRef}>
                {STEPS.map(s => (
                  <li key={s.num} className={styles.step} id={`pixel-${s.letter.toLowerCase()}`}>
                    <div className={styles.numWrap}>
                      <span className={styles.num}>{s.num}</span>
                      <span className={styles.letterGhost} aria-hidden="true">{s.letter}</span>
                    </div>
                    <div>
                      <h3 className={styles.title}>{s.title}</h3>
                      <p className={styles.body}>{s.body}</p>
                      <span className={styles.output}>
                        <span className={styles.outputDot} />
                        Entrega: {s.output}
                      </span>
                    </div>
                  </li>
                ))}
              </ol>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
