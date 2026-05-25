import { X, ExternalLink } from 'lucide-react'
import { useEffect, useState } from 'react'
import styles from './CaseModal.module.css'

export default function CaseModal({ isOpen, onClose, caseData }) {
  const [mounted, setMounted] = useState(false)

  // Tratamento de escape e bloqueio de scroll
  useEffect(() => {
    if (isOpen) {
      setMounted(true)
      document.body.style.overflow = 'hidden'
    } else {
      setTimeout(() => setMounted(false), 300) // tempo da transição CSS
      document.body.style.overflow = ''
    }

    const handleEsc = (e) => {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', handleEsc)
    return () => {
      window.removeEventListener('keydown', handleEsc)
      document.body.style.overflow = ''
    }
  }, [isOpen, onClose])

  if (!mounted && !isOpen) return null

  return (
    <div className={`${styles.overlay} ${isOpen ? styles.open : ''}`} onClick={onClose}>
      <div className={styles.modal} onClick={(e) => e.stopPropagation()}>
        <button className={styles.closeBtn} onClick={onClose} aria-label="Fechar">
          <X size={20} />
        </button>

        <div className={styles.imageArea}>
          {caseData?.image ? (
            <img src={caseData.image} alt={caseData?.title} />
          ) : (
            <div className={styles.placeholderImage}></div>
          )}
        </div>

        <div className={styles.contentArea}>
          <div className={styles.header}>
            <div>
              <h3 className={styles.title}>{caseData?.title}</h3>
              <div className={styles.tags}>
                {caseData?.tags?.map((tag, i) => (
                  <span key={i} className={styles.tag}>{tag}</span>
                ))}
              </div>
            </div>
            
            {caseData?.link && (
              <a href={caseData.link} target="_blank" rel="noopener noreferrer" className={styles.visitBtn}>
                Visitar Site <ExternalLink size={18} />
              </a>
            )}
          </div>

          <p className={styles.description}>
            {caseData?.description}
          </p>
        </div>
      </div>
    </div>
  )
}
