import { useRevealContainer } from '../hooks/useReveal'
import styles from './Core.module.css'

const LAYERS = [
  {
    num: '01',
    tag: 'BASE OBRIGATÓRIA',
    tagType: 'base',
    title: 'Landing Page de Alta Conversão',
    body: 'A porta de entrada qualificada. Estrutura orientada a um único objetivo: transformar intenção de busca em contato real no seu WhatsApp.',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="3" width="18" height="18" rx="2" />
        <path d="M3 9h18M9 21V9" />
      </svg>
    ),
  },
  {
    num: '02',
    tag: 'BASE OBRIGATÓRIA',
    tagType: 'base',
    title: 'Integração WhatsApp',
    body: 'Canal direto de fechamento sem fricção. O lead qualificado chega diretamente ao responsável pelo atendimento, sem formulários ou barreiras.',
    icon: (
      <svg viewBox="0 0 24 24" fill="currentColor">
        <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347z"/>
        <path d="M12 0C5.373 0 0 5.373 0 12c0 2.127.558 4.126 1.528 5.857L.057 23.882a.5.5 0 0 0 .614.612l6.162-1.624A11.944 11.944 0 0 0 12 24c6.627 0 12-5.373 12-12S18.627 0 12 0zm0 22c-1.886 0-3.655-.523-5.168-1.43l-.369-.22-3.812 1.004 1.021-3.72-.24-.382A9.945 9.945 0 0 1 2 12C2 6.477 6.477 2 12 2s10 4.477 10 10-4.477 10-10 10z"/>
      </svg>
    ),
  },
  {
    num: '03',
    tag: 'BASE OBRIGATÓRIA',
    tagType: 'base',
    title: 'Rastreamento Técnico (Pixel & GA4)',
    body: 'Sem dado confiável, não existe leitura séria de resultado. Instalamos o rastreamento de cada intenção — de onde o lead veio, o que clicou, onde saiu.',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="22 12 18 12 15 21 9 3 6 12 2 12" />
      </svg>
    ),
  },
  {
    num: '04',
    tag: 'BASE OBRIGATÓRIA',
    tagType: 'base',
    // "Google Meu Negócio" virou "Perfil da Empresa no Google" em 2022. Mantemos
    // o nome antigo no corpo porque continua sendo o termo que as pessoas buscam.
    title: 'Perfil da Empresa no Google & SEO Local',
    body: 'Domínio na busca regional. Quando um potencial cliente pesquisa sua especialidade em Brasília, você precisa aparecer antes da concorrência — de forma orgânica e confiável. É o antigo Google Meu Negócio, configurado como infraestrutura.',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" />
        <circle cx="12" cy="10" r="3" />
      </svg>
    ),
  },
  {
    num: '05',
    tag: 'ALAVANCA',
    tagType: 'alavanca',
    title: 'Tráfego Pago (PIXELRY ADS)',
    body: 'Ativado apenas após o CORE validado. Injetamos tráfego qualificado na estrutura existente para escalar conversões — sem investir em cima de um sistema que não foi testado.',
    icon: (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="23 6 13.5 15.5 8.5 10.5 1 18" />
        <polyline points="17 6 23 6 23 12" />
      </svg>
    ),
  },
]

export default function Core() {
  const ref = useRevealContainer()

  return (
    <section id="core">
      <div className="section-wrap" ref={ref}>
        <div className="reveal">
          <span className="label">PIXELRY CORE</span>
          <h2 className={styles.h2}>
            Não é um site.<br />
            É uma <span className="grad-text">infraestrutura de aquisição.</span>
          </h2>
          <p className={styles.sub}>
            O CORE é o sistema integrado que conecta cada camada da sua operação de captação de clientes.
            Cada componente tem função crítica — nenhum é decorativo.
          </p>
        </div>

        <div className={styles.stack}>
          {LAYERS.map((layer, i) => (
            <div
              key={layer.num}
              className={`${styles.layer} ${layer.tagType === 'alavanca' ? styles.alavanca : ''} reveal reveal-d${(i % 3) + 1}`}
            >
              <div className={styles.layerLeft}>
                <span className={styles.num}>{layer.num}</span>
                <div className={styles.icon}>{layer.icon}</div>
              </div>
              <div className={styles.layerBody}>
                <span className={`${styles.tag} ${layer.tagType === 'alavanca' ? styles.tagAlavanca : styles.tagBase}`}>
                  {layer.tag}
                </span>
                <h3 className={styles.title}>{layer.title}</h3>
                <p className={styles.body}>{layer.body}</p>
              </div>
              <div className={styles.layerNum} aria-hidden="true">{layer.num}</div>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
