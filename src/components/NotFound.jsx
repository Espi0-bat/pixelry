import { Link } from 'react-router-dom'
import { Home, ArrowLeft } from 'lucide-react'
import styles from './NotFound.module.css'

export default function NotFound() {
  return (
    <div className={styles.wrap}>
      <p className={styles.code}>404</p>
      <h1 className={styles.title}>Página não encontrada</h1>
      <p className={styles.text}>
        O endereço que você tentou acessar não existe ou foi movido.
      </p>
      <div className={styles.actions}>
        <Link to="/" className={styles.primary}>
          <Home size={16} aria-hidden="true" /> Ir para o início
        </Link>
        <button type="button" className={styles.secondary} onClick={() => window.history.back()}>
          <ArrowLeft size={16} aria-hidden="true" /> Voltar
        </button>
      </div>
    </div>
  )
}
