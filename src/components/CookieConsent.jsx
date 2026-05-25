import { useState, useEffect } from 'react'
import { Check, ChevronDown, ChevronUp, Cookie, X } from 'lucide-react'
import { Link } from 'react-router-dom'
import styles from './CookieConsent.module.css'

export default function CookieConsent() {
  const [isOpen, setIsOpen] = useState(false)
  const [showDetails, setShowDetails] = useState(false)
  const [preferences, setPreferences] = useState({
    essential: true, // Always true
    analytics: false,
    marketing: false,
  })

  useEffect(() => {
    // Check if the user has already made a choice
    const consent = localStorage.getItem('pixelry_cookie_consent')
    if (!consent) {
      // Delay slightly for better UX
      const timer = setTimeout(() => setIsOpen(true), 1500)
      return () => clearTimeout(timer)
    }
  }, [])

  const handleAcceptAll = () => {
    const allAccepted = { essential: true, analytics: true, marketing: true }
    localStorage.setItem('pixelry_cookie_consent', JSON.stringify(allAccepted))
    setPreferences(allAccepted)
    setIsOpen(false)
  }

  const handleSavePreferences = () => {
    localStorage.setItem('pixelry_cookie_consent', JSON.stringify(preferences))
    setIsOpen(false)
  }

  const handleTogglePreference = (key) => {
    if (key === 'essential') return // Cannot toggle essential
    setPreferences(prev => ({ ...prev, [key]: !prev[key] }))
  }

  if (!isOpen) return null

  return (
    <div className={styles.overlay} role="dialog" aria-modal="true" aria-labelledby="cookie-title">
      <div className={styles.container}>
        <div className={styles.header}>
          <div className={styles.titleGroup}>
            <Cookie className={styles.icon} size={24} />
            <h2 id="cookie-title" className={styles.title}>Nós valorizamos sua privacidade</h2>
          </div>
          <button 
            className={styles.closeBtn} 
            onClick={() => setIsOpen(false)}
            aria-label="Fechar"
          >
            <X size={20} />
          </button>
        </div>

        <div className={styles.content}>
          <p className={styles.description}>
            Utilizamos cookies para melhorar sua experiência em nosso site, personalizar conteúdo e analisar nosso tráfego. 
            Ao clicar em "Aceitar Todos", você concorda com o uso de todos os cookies. Você pode gerenciar suas preferências em "Detalhes". 
            Leia nossa <Link to="/privacidade" className={styles.link}>Política de Privacidade</Link> para mais informações.
          </p>
        </div>

        {showDetails && (
          <div className={styles.detailsContainer}>
            <div className={styles.preferenceItem}>
              <div className={styles.preferenceHeader}>
                <div className={styles.preferenceInfo}>
                  <h3 className={styles.preferenceTitle}>Essenciais (Estritamente Necessários)</h3>
                  <p className={styles.preferenceDesc}>
                    Estes cookies são necessários para o funcionamento do site e não podem ser desativados. Eles geralmente são definidos apenas em resposta a ações feitas por você, como definir suas preferências de privacidade ou fazer login.
                  </p>
                </div>
                <div className={styles.toggleWrapper}>
                  <input type="checkbox" id="pref-essential" checked disabled className={styles.toggleInput} />
                  <label htmlFor="pref-essential" className={`${styles.toggleLabel} ${styles.disabled}`}></label>
                </div>
              </div>
            </div>

            <div className={styles.preferenceItem}>
              <div className={styles.preferenceHeader}>
                <div className={styles.preferenceInfo}>
                  <h3 className={styles.preferenceTitle}>Analíticos</h3>
                  <p className={styles.preferenceDesc}>
                    Permitem-nos contar visitas e fontes de tráfego, para que possamos medir e melhorar o desempenho do nosso site. Eles nos ajudam a saber quais páginas são mais e menos populares.
                  </p>
                </div>
                <div className={styles.toggleWrapper}>
                  <input 
                    type="checkbox" 
                    id="pref-analytics" 
                    checked={preferences.analytics} 
                    onChange={() => handleTogglePreference('analytics')}
                    className={styles.toggleInput} 
                  />
                  <label htmlFor="pref-analytics" className={styles.toggleLabel}></label>
                </div>
              </div>
            </div>

            <div className={styles.preferenceItem}>
              <div className={styles.preferenceHeader}>
                <div className={styles.preferenceInfo}>
                  <h3 className={styles.preferenceTitle}>Marketing</h3>
                  <p className={styles.preferenceDesc}>
                    Esses cookies podem ser estabelecidos através do nosso site pelos nossos parceiros de publicidade. Podem ser usados por essas empresas para construir um perfil sobre os seus interesses e mostrar-lhe anúncios relevantes em outros sites.
                  </p>
                </div>
                <div className={styles.toggleWrapper}>
                  <input 
                    type="checkbox" 
                    id="pref-marketing" 
                    checked={preferences.marketing} 
                    onChange={() => handleTogglePreference('marketing')}
                    className={styles.toggleInput} 
                  />
                  <label htmlFor="pref-marketing" className={styles.toggleLabel}></label>
                </div>
              </div>
            </div>
          </div>
        )}

        <div className={styles.footer}>
          <button 
            className={styles.detailsBtn} 
            onClick={() => setShowDetails(!showDetails)}
          >
            {showDetails ? (
              <>Esconder Detalhes <ChevronUp size={16} /></>
            ) : (
              <>Ver Detalhes <ChevronDown size={16} /></>
            )}
          </button>
          
          <div className={styles.actionBtns}>
            {showDetails && (
              <button className={styles.saveBtn} onClick={handleSavePreferences}>
                Salvar Preferências
              </button>
            )}
            <button className={styles.acceptBtn} onClick={handleAcceptAll}>
              {showDetails ? 'Aceitar Todos' : 'Concordar e Continuar'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
