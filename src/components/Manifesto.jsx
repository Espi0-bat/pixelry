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
          Existe uma lacuna entre o que muitos negócios são e o que eles comunicam online.
          A PIXELRY nasceu para fechar essa lacuna. <strong>Com o Método P.I.X.E.L. Com engenharia digital focada em atração.</strong>{' '}
          Não somos a agência que promete crescimento viral. Somos a empresa de tecnologia que constrói o sistema
          que transforma autoridade real em previsibilidade comercial —
          e visitantes em clientes no seu WhatsApp.{' '}
          <strong>Brasília — DF. Padrão sem concessão.</strong>
        </p>
      </div>
    </div>
  )
}
