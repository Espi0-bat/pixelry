import { useState } from 'react'
import { ArrowRight } from 'lucide-react'
import styles from './Cases.module.css'
import CaseModal from './CaseModal'
import drRogerioImg from './images/Dr Rogerio Furtado-74.jpg'

const BASE_URL = import.meta.env.BASE_URL || '/'

const portfolioData = [
  {
    id: 'casarao',
    title: 'Casarão dos Pireneus',
    description: 'Projeto completo com foco em design de conversão e integração com sistema de reservas. A arquitetura de informação foi pensada para guiar o hóspede a uma experiência premium desde o primeiro contato, maximizando as reservas diretas.',
    tags: ['Design de Conversão', 'Integração de Reservas', 'High-end'],
    image: `${BASE_URL}chale_fachada_colonial.jpg`,
    link: 'https://www.fazendacasaraodospireneus.com.br/',
    status: 'live'
  },
  {
    id: 'dr-rogerio',
    title: 'Doutor Rogério',
    description: 'Site institucional focado em construir autoridade médica e otimizar o agendamento de consultas. Design sóbrio, elegante e voltado para um público exigente.',
    tags: ['Saúde', 'Autoridade Médica', 'Institucional'],
    image: drRogerioImg,
    link: 'https://espi0-bat.github.io/site-rogerio/',
    status: 'live'
  }
]

export default function Cases() {
  const [selectedCase, setSelectedCase] = useState(null)

  return (
    <section className={styles.section} id="cases">
      <div className={styles.container}>
        <div className={styles.header}>
          <span className="label">PORTFÓLIO</span>
          <h2 className={styles.title}>Nossas Entregas</h2>
        </div>

        <div className={styles.grid}>
          {portfolioData.map((item) => (
            <div 
              key={item.id} 
              className={styles.card}
              onClick={() => setSelectedCase(item)}
            >
              <div className={styles.cardImage}>
                {item.status === 'em-breve' && (
                  <div className={styles.emBreveOverlay}>
                    <span className={styles.emBreveBadge}>Em Breve</span>
                  </div>
                )}
                {item.image ? (
                  <img src={item.image} alt={item.title} loading="lazy" />
                ) : (
                  <div className={styles.placeholderBg}></div>
                )}
              </div>
              
              <div className={styles.cardContent}>
                <h3 className={styles.cardTitle}>{item.title}</h3>
                <p className={styles.cardDesc}>
                  {item.description.length > 110 
                    ? item.description.substring(0, 110) + '...' 
                    : item.description}
                </p>
                <div className={styles.cardFooter}>
                  <div className={styles.cardTags}>
                    {item.tags.slice(0, 2).map((tag, i) => (
                      <span key={i} className={styles.cardTag}>{tag}</span>
                    ))}
                  </div>
                  <div className={styles.viewIcon}>
                    <ArrowRight size={18} />
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      <CaseModal 
        isOpen={!!selectedCase} 
        onClose={() => setSelectedCase(null)} 
        caseData={selectedCase} 
      />
    </section>
  )
}
