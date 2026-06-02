import styles from './Marquee.module.css'

const ITEMS = [
  'ENGENHARIA DIGITAL',
  'BRASÍLIA — DF',
  'SISTEMAS DE AQUISIÇÃO',
  'LANDING PAGE',
  'TRÁFEGO PAGO',
  'SEO LOCAL',
  'PIXELRY CORE',
  'RASTREAMENTO TÉCNICO',
  'RESULTADO MENSURÁVEL',
  'PADRÃO SEM CONCESSÃO',
]

export default function Marquee() {
  return (
    <div className={styles.wrap} aria-hidden="true">
      <div className={styles.track}>
        {[...ITEMS, ...ITEMS].map((item, i) => (
          <span key={i} className={styles.item}>
            {item}
            <span className={styles.sep}>·</span>
          </span>
        ))}
      </div>
    </div>
  )
}
