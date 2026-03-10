import { useRevealContainer } from '../hooks/useReveal'
import styles from './Processo.module.css'

const STEPS = [
  { num: '01', title: 'Imersão',         body: 'Mapeamos seu negócio, mercado, público e posicionamento atual. Entendemos o que você entrega e o que sua presença digital está comunicando — mesmo que seja o silêncio.' },
  { num: '02', title: 'Estratégia',      body: 'Definimos linguagem visual, arquitetura de marca, prioridades de execução e o que precisa existir antes do que é apenas desejável.' },
  { num: '03', title: 'Design',          body: 'Cada decisão visual tem função estratégica. Criamos interfaces que comunicam autoridade antes que qualquer texto seja lido.' },
  { num: '04', title: 'Engenharia',      body: 'Código limpo, responsivo e performático. Estrutura construída para durar e escalar — sem atalhos que viram problemas.' },
  { num: '05', title: 'Refinamento',     body: 'Revisamos cada detalhe até o projeto representar com precisão o nível do seu negócio. Sem aprovação prematura.' },
  { num: '06', title: 'Ativação',        body: 'Publicação com validação técnica completa. O projeto vai ao ar funcionando — não em fase de testes.' },
  { num: '07', title: 'Continuidade',    body: 'Permanecemos presentes após a entrega. Monitoramos, ajustamos e evoluímos o que foi construído junto com o seu negócio.' },
]

export default function Processo() {
  const ref = useRevealContainer()

  return (
    <div className={styles.bg} id="processo">
      <div className={styles.inner} ref={ref}>
        <header className={`${styles.header} reveal`}>
          <span className="label">METODOLOGIA</span>
          <h2 className={styles.h2}>
            Um processo que elimina o improviso<br />
            e garante precisão em cada entrega.
          </h2>
        </header>

        <div className={styles.list}>
          {STEPS.map((s, i) => (
            <div
              key={s.num}
              className={`${styles.step} reveal ${i % 2 === 1 ? 'reveal-d1' : ''}`}
            >
              <span className={styles.num}>{s.num}</span>
              <div>
                <h3 className={styles.title}>{s.title}</h3>
                <p className={styles.body}>{s.body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
