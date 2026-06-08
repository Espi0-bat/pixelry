import { useRevealContainer } from '../hooks/useReveal'
import styles from './Processo.module.css'

const STEPS = [
  {
    num: '01',
    letter: 'P',
    title: 'P - Posicionamento',
    body: 'Antes do visual, definimos a oferta, o público e a promessa principal. Sua página vira um ambiente de conversão quando o cliente entende imediatamente por que você é a escolha certa.',
    output: 'Oferta clara + público mapeado'
  },
  {
    num: '02',
    letter: 'I',
    title: 'I - Identidade',
    body: 'A estética é um instrumento de percepção de confiança. Geramos um ambiente profissional e coeso que reflete qualidade e eleva a autoridade percebida da sua clínica.',
    output: 'Identidade visual de autoridade'
  },
  {
    num: '03',
    letter: 'X',
    title: 'X - Experiência',
    body: 'Reduzimos toda a fricção de navegação. Um layout confuso ou lento joga o cliente para trás. Nosso papel é pavimentar um caminho rápido e limpo até o botão de contato.',
    output: 'Jornada sem fricção até o contato'
  },
  {
    num: '04',
    letter: 'E',
    title: 'E - Estratégia',
    body: 'A estrutura é pensada no fechamento. Organizamos Copy, CTAs, gatilhos de prova social e a integração direta com automações básicas no seu canal principal (WhatsApp).',
    output: 'CTAs e fluxo de conversão ativos'
  },
  {
    num: '05',
    letter: 'L',
    title: 'L - Leitura e Lapidação',
    body: 'Sem dados, é intuição. Instalamos o rastreamento técnico (Pixel, GA4) para monitorar resultados e lapidar a estratégia continuamente — o sistema não termina no go-live, ele melhora todo mês.',
    output: 'Pixel + GA4 ativos · otimização contínua'
  },
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
              <div className={styles.numWrap}>
                <span className={styles.num}>{s.num}</span>
                <span className={styles.letterGhost} aria-hidden="true">{s.letter}</span>
              </div>
              <div>
                <h3 className={styles.title}>{s.title}</h3>
                <p className={styles.body}>{s.body}</p>
                <span className={styles.output}>
                  <span className={styles.outputDot} />
                  OUTPUT: {s.output}
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
