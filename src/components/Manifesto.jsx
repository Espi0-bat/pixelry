import { useRevealContainer } from '../hooks/useReveal'
import styles from './Manifesto.module.css'

export default function Manifesto() {
  const ref = useRevealContainer()

  return (
    <div className={styles.bg}>
      <div className={styles.inner} ref={ref}>
        <div className="reveal" style={{ textAlign: 'center' }}>
          <span className="label" style={{ justifyContent: 'center' }}>MANIFESTO</span>
          <h2 className={styles.h2}>
            Presença digital que<br />
            <span className="grad-text">comunica o valor<br />que você já entrega.</span>
          </h2>
        </div>

        <p className={`${styles.body} reveal reveal-d2`}>
          Você já entrega um serviço bom. Provavelmente excelente.
          O problema é que o site não conta essa história.{' '}
          A PIXELRY existe para fechar esse gap — com tecnologia real,
          não com post de feed. <strong>Construímos a infraestrutura digital que
          faz o negócio funcionar enquanto você atende.</strong>{' '}
          <strong>Brasília — DF. Padrão sem concessão.</strong>
        </p>
      </div>
    </div>
  )
}
