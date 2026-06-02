import { useEffect, useRef, useState } from 'react'
import { useRevealContainer } from '../hooks/useReveal'
import styles from './BrasilMap.module.css'

// Simplified Brazil outline — clockwise from Roraima/Venezuela border
// Mapped to viewBox "0 0 500 560" via geographic projection:
//   x = (lon + 73.9) / 39.1 × 500   (lon in °W, west → left)
//   y = (5.3 - lat) / 39   × 560   (lat in °N, north → top)
const BRASIL_PATH =
  'M 165,4 ' +
  'C 218,2 278,10 308,22 ' +
  'C 328,30 328,58 326,80 ' +
  'C 328,94 352,106 380,114 ' +
  'C 412,122 448,124 458,130 ' +
  'L 492,152 L 498,182 ' +
  'C 494,202 474,220 458,232 ' +
  'C 448,242 448,254 450,264 ' +
  'C 452,280 444,300 436,322 ' +
  'C 431,342 432,358 434,368 ' +
  'C 434,386 414,396 396,402 ' +
  'C 378,408 358,414 352,424 ' +
  'C 338,438 325,454 320,474 ' +
  'C 312,494 295,508 286,514 ' +
  'L 262,554 ' +
  'L 242,536 ' +
  'C 222,522 210,508 210,498 ' +
  'C 208,484 220,462 244,436 ' +
  'C 248,406 245,380 243,366 ' +
  'C 240,342 218,338 203,340 ' +
  'C 181,342 174,316 174,288 ' +
  'C 172,256 144,226 126,198 ' +
  'C 100,166 46,136 12,98 ' +
  'L 12,44 ' +
  'C 52,20 115,4 165,4 Z'

// Geographic coordinates → SVG coordinates
// x = (lon + 73.9) / 39.1 * 500, y = (5.3 - lat) / 39 * 560
const CITIES = [
  { id: 'brasilia', name: 'Brasília — DF', cx: 332, cy: 304, hub: true },
  { id: 'saopaulo', name: 'São Paulo — SP', cx: 349, cy: 406 },
  { id: 'rio',      name: 'Rio de Janeiro — RJ', cx: 393, cy: 399 },
  { id: 'bh',       name: 'Belo Horizonte — MG', cx: 382, cy: 362 },
  { id: 'fortaleza',name: 'Fortaleza — CE', cx: 452, cy: 126 },
  { id: 'recife',   name: 'Recife — PE', cx: 478, cy: 185 },
  { id: 'salvador', name: 'Salvador — BA', cx: 452, cy: 260 },
  { id: 'curitiba', name: 'Curitiba — PR', cx: 308, cy: 456 },
  { id: 'manaus',   name: 'Manaus — AM', cx: 179, cy: 118 },
]

const HUB = CITIES.find(c => c.hub)
const SPOKES = CITIES.filter(c => !c.hub)

export default function BrasilMap() {
  const containerRef = useRevealContainer()
  const mapRef = useRef(null)
  const [mapVisible, setMapVisible] = useState(false)

  useEffect(() => {
    const el = mapRef.current
    if (!el) return
    const obs = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setMapVisible(true)
          obs.disconnect()
        }
      },
      { threshold: 0.15 }
    )
    obs.observe(el)
    return () => obs.disconnect()
  }, [])

  return (
    <section className={styles.section}>
      <div className={styles.inner} ref={containerRef}>

        {/* Left — copy */}
        <div className={`${styles.text} reveal`}>
          <span className="label">PRESENÇA NACIONAL</span>
          <h2 className={styles.h2}>
            De Brasília<br />
            <span className="grad-text">para o Brasil.</span>
          </h2>
          <p className={styles.sub}>
            Operamos em Brasília — DF com clientes em todo o
            território nacional. Cada ponto no mapa é um negócio
            que decidiu parar de improvisar.
          </p>
          <ul className={styles.cityList}>
            {SPOKES.map(c => (
              <li key={c.id} className={styles.cityItem}>
                <span className={styles.cityDot} />
                {c.name}
              </li>
            ))}
          </ul>
        </div>

        {/* Right — SVG map */}
        <div
          className={`${styles.mapWrap} reveal reveal-d2`}
          ref={mapRef}
        >
          <svg
            viewBox="0 0 500 560"
            className={`${styles.svg} ${mapVisible ? styles.svgVisible : ''}`}
            aria-hidden="true"
            focusable="false"
          >
            <defs>
              <radialGradient id="mapHubGlow" cx="50%" cy="50%" r="50%">
                <stop offset="0%" stopColor="#8040F5" stopOpacity="0.9" />
                <stop offset="100%" stopColor="#8040F5" stopOpacity="0" />
              </radialGradient>
              <radialGradient id="mapCityGlow" cx="50%" cy="50%" r="50%">
                <stop offset="0%" stopColor="#00D8FF" stopOpacity="0.7" />
                <stop offset="100%" stopColor="#00D8FF" stopOpacity="0" />
              </radialGradient>
              <filter id="mapBlur">
                <feGaussianBlur stdDeviation="2" />
              </filter>
            </defs>

            {/* Interior fill */}
            <path d={BRASIL_PATH} className={styles.fill} />

            {/* Outline — animates drawing in */}
            <path d={BRASIL_PATH} className={styles.outline} />

            {/* Lines from hub to spokes */}
            {SPOKES.map((city, i) => (
              <line
                key={city.id}
                x1={HUB.cx} y1={HUB.cy}
                x2={city.cx} y2={city.cy}
                className={styles.spoke}
                style={{ '--delay': `${0.8 + i * 0.07}s` }}
              />
            ))}

            {/* Spoke city dots */}
            {SPOKES.map((city, i) => (
              <g
                key={city.id}
                className={styles.cityGroup}
                style={{ '--delay': `${0.9 + i * 0.08}s` }}
              >
                <circle cx={city.cx} cy={city.cy} r="14" fill="url(#mapCityGlow)" />
                <circle cx={city.cx} cy={city.cy} r="2.8" fill="#00D8FF" fillOpacity="0.95" />
                <circle cx={city.cx} cy={city.cy} r="6" fill="none" stroke="#00D8FF" strokeWidth="0.8" strokeOpacity="0.45" className={styles.cityPulse} />
              </g>
            ))}

            {/* Hub — Brasília */}
            <g className={`${styles.hubGroup} ${mapVisible ? styles.hubVisible : ''}`}>
              {/* Outer ambient glow */}
              <circle cx={HUB.cx} cy={HUB.cy} r="28" fill="url(#mapHubGlow)" filter="url(#mapBlur)" />
              {/* Outer pulse ring */}
              <circle cx={HUB.cx} cy={HUB.cy} r="16" fill="none" stroke="#8040F5" strokeWidth="1" strokeOpacity="0.45" className={styles.hubRingOuter} />
              {/* Inner ring */}
              <circle cx={HUB.cx} cy={HUB.cy} r="9" fill="none" stroke="#8040F5" strokeWidth="1.4" strokeOpacity="0.75" className={styles.hubRingInner} />
              {/* Core dot */}
              <circle cx={HUB.cx} cy={HUB.cy} r="4.5" fill="#8040F5" />
              <circle cx={HUB.cx} cy={HUB.cy} r="2" fill="#fff" fillOpacity="0.9" />
              {/* Label */}
              <text
                x={HUB.cx + 8}
                y={HUB.cy - 20}
                className={styles.hubLabel}
              >
                PIXELRY HQ
              </text>
            </g>
          </svg>
        </div>

      </div>
    </section>
  )
}
