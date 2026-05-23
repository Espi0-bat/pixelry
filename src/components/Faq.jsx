import { useState } from 'react'
import { useRevealContainer } from '../hooks/useReveal'
import styles from './Faq.module.css'

const FAQS = [
  {
    q: 'O que exatamente é um sistema de aquisição de clientes?',
    a: 'Não é apenas um site. É uma estrutura integrada: página de alta conversão, integração com WhatsApp, rastreamento técnico (GA4/Pixel), SEO local e — quando validado — mídia paga. Cada peça trabalha em conjunto para transformar intenção de busca em agendamento real na sua agenda.',
  },
  {
    q: 'Minha clínica já tem redes sociais. Por que precisaria disso?',
    a: 'Redes sociais geram visibilidade, mas não controlam a jornada do cliente. Um sistema de aquisição captura esse tráfego, qualifica o lead e direciona diretamente para o fechamento — de forma rastreável e previsível. São camadas complementares, não concorrentes.',
  },
  {
    q: 'Qual a diferença entre a PIXELRY e agências de marketing?',
    a: 'Nós não somos uma agência focada apenas em estética visual ou gestão de redes sociais. Somos uma empresa de engenharia digital focada em aquisição de clientes. Em vez de vender "design", construímos o PIXELRY CORE: um sistema que integra atração, conversão e dados para garantir rastreabilidade nas suas vendas.',
  },
  {
    q: 'Vou precisar entender de tecnologia para gerenciar meu site?',
    a: 'Não. Entregamos o projeto funcional, treinamos você (ou sua equipe) nas partes que precisam de atualização rotineira e permanecemos disponíveis para suporte. O objetivo é que você gerencie o conteúdo sem depender de nós para cada pequena mudança.',
  },
  {
    q: 'Como funciona o processo de pagamento?',
    a: 'Nosso modelo tem duas etapas. Primeiro, você investe na Taxa de Setup — o projeto completo: desenvolvimento, design, tagueamento e publicação. Após a entrega, entra o Acompanhamento Mensal: hosting premium, o Hub PIXELRY com seus dados em tempo real, suporte técnico e manutenção contínua. Tudo começa com uma conversa para definir qual plano faz sentido para o seu negócio.',
  },
  {
    q: 'E se eu não gostar do resultado?',
    a: 'Todo projeto tem rodadas de revisão definidas no contrato. Trabalhamos com aprovação etapa por etapa justamente para evitar surpresas no final. Se algo não estiver alinhado com o que foi acordado, ajustamos sem custo adicional.',
  },
]

export default function Faq() {
  const [open, setOpen] = useState(null)
  const ref = useRevealContainer()

  return (
    <section id="faq">
      <div className="section-wrap" ref={ref}>
        <div className="reveal">
          <span className="label">DÚVIDAS</span>
          <h2 className={styles.h2}>
            Perguntas que todo dono de negócio<br />
            faz antes de investir em digital.
          </h2>
        </div>

        <div className={styles.list}>
          {FAQS.map((faq, i) => {
            const isOpen = open === i
            return (
              <div
                key={i}
                className={`${styles.item} reveal reveal-d${(i % 3) + 1}`}
              >
                <button
                  className={styles.trigger}
                  onClick={() => setOpen(isOpen ? null : i)}
                  aria-expanded={isOpen}
                >
                  <span className={styles.q}>{faq.q}</span>
                  <span className={`${styles.icon} ${isOpen ? styles.iconOpen : ''}`}>
                    +
                  </span>
                </button>
                <div className={`${styles.body} ${isOpen ? styles.bodyOpen : ''}`}>
                  <p>{faq.a}</p>
                </div>
              </div>
            )
          })}
        </div>
      </div>
    </section>
  )
}
