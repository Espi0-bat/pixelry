import { forwardRef, useState } from 'react'
import { Eye, EyeOff } from 'lucide-react'
import styles from './PasswordInput.module.css'

/**
 * Campo de senha com botão mostrar/ocultar acessível.
 * Aceita `className` para herdar o estilo do input da tela hospedeira.
 * Permite colar (não bloqueia onPaste) — WCAG 2.2 Autenticação Acessível.
 */
const PasswordInput = forwardRef(function PasswordInput(
  { className = '', wrapperClassName = '', autoComplete = 'current-password', ...props },
  ref,
) {
  const [visible, setVisible] = useState(false)
  return (
    <div className={`${styles.wrap} ${wrapperClassName}`}>
      <input
        {...props}
        ref={ref}
        type={visible ? 'text' : 'password'}
        autoComplete={autoComplete}
        className={`${className} ${styles.input}`}
      />
      <button
        type="button"
        className={styles.toggle}
        onClick={() => setVisible((v) => !v)}
        aria-label={visible ? 'Ocultar senha' : 'Mostrar senha'}
        aria-pressed={visible}
        tabIndex={-1}
      >
        {visible ? <EyeOff size={18} aria-hidden="true" /> : <Eye size={18} aria-hidden="true" />}
      </button>
    </div>
  )
})

export default PasswordInput
