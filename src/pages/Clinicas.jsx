import { useCallback, useState } from 'react'
import { Link } from 'react-router-dom'
import { Helmet } from 'react-helmet-async'
import { ArrowUpRight, ArrowDown, Search, MessageCircle, MapPin, Check, MousePointer2 } from 'lucide-react'
import { buildWhatsAppLink } from '../config/contact'
import styles from './Clinicas.module.css'
import logoImg from '../components/images/pixelryicone.jpeg'
import LeadCaptureModal from '../components/LeadCaptureModal'

// Troque null pelo nome do arquivo produzido com docs/lp-clinicas/prompts.
const IMAGES = {
  hero: '01-chegada.webp', // 01-chegada.webp
  discovery: '02-descoberta.webp', // 02-descoberta.webp
  trust: '03-confianca.webp', // 03-confianca.webp
  contact: '04-contato.webp', // 04-contato.webp
  clarity: '05-clareza.webp', // 05-clareza.webp
  closing: '06-conversa.webp', // 06-conversa.webp
}
const asset = name => `${import.meta.env.BASE_URL}assets/clinicas/${name}`
const reception = `${import.meta.env.BASE_URL}assets/pixelry-hero.webp`
const challenges = [
  { label: 'Dependo muito de indicação', id: 'encontrar' },
  { label: 'Meu site não representa minha clínica', id: 'confiar' },
  { label: 'Poucas visitas viram contatos', id: 'contato' },
  { label: 'Não sei o que traz resultado', id: 'entender' },
  { label: 'Demoramos para responder no WhatsApp', id: 'respostas' },
  { label: 'Minha equipe repete as mesmas respostas', id: 'perguntas' },
  { label: 'Contatos interessados ficam sem retorno', id: 'retorno' },
  { label: 'Lembretes e confirmações são manuais', id: 'rotina' },
]
const automations = [
  { id: 'respostas', label: 'AGENTE DE IA', title: 'O contato chega. Sua equipe está ocupada.', text: 'Um agente de IA pode acolher a primeira mensagem, identificar o interesse e encaminhar a conversa com contexto para a recepção.', cta: 'Quero agilizar as respostas' },
  { id: 'perguntas', label: 'INFORMAÇÕES APROVADAS', title: 'As mesmas perguntas, várias vezes ao dia.', text: 'Horários, localização e orientações de agendamento podem ser respondidos com base nas informações aprovadas pela clínica.', cta: 'Quero conhecer o agente de IA' },
  { id: 'retorno', label: 'ACOMPANHAMENTO', title: 'Perguntou, se interessou… e a conversa parou.', text: 'Fluxos de acompanhamento ajudam a organizar retornos e lembrar sua equipe de retomar oportunidades, com regras e intervalos definidos.', cta: 'Quero organizar os retornos' },
  { id: 'rotina', label: 'AUTOMAÇÃO DA ROTINA', title: 'Menos copiar e colar. Mais atenção às pessoas.', text: 'Podemos conectar lembretes, solicitações de confirmação e encaminhamentos à rotina da clínica, conforme os sistemas disponíveis.', cta: 'Quero automatizar minha rotina' },
]
const chapters = [
  { id: 'encontrar', number: '01', tag: 'ANTES DE CHEGAR', title: 'Quem precisa de você consegue encontrar sua clínica?', text: 'O paciente procura atendimento na sua região. Sua clínica precisa estar presente nesse primeiro momento.', solution: 'Organizamos sua presença no Google e, quando fizer sentido, criamos campanhas para alcançar quem procura seu atendimento.', image: 'discovery', alt: 'Pessoa procurando atendimento pelo celular', outcome: 'Ser encontrada', icon: Search },
  { id: 'confiar', number: '02', tag: 'A PRIMEIRA IMPRESSÃO', title: 'Seu site acolhe tão bem quanto a sua recepção?', text: 'Antes de marcar, a pessoa quer conhecer os profissionais, entender o atendimento e sentir confiança.', solution: 'Criamos um site que apresenta sua equipe, suas especialidades e o cuidado que existe em cada detalhe da clínica.', image: 'trust', alt: 'Ambiente acolhedor de uma clínica', outcome: 'Transmitir confiança', icon: MapPin },
  { id: 'contato', number: '03', tag: 'O PRÓXIMO PASSO', title: 'Gostou da sua clínica. E agora, como falar com vocês?', text: 'Um telefone difícil de encontrar ou informações confusas podem interromper uma boa primeira impressão.', solution: 'Deixamos o caminho até o WhatsApp simples, com informações claras e convites para conversar nos lugares certos.', image: 'contact', alt: 'Recepcionista atendendo na clínica', outcome: 'Facilitar o contato', icon: MessageCircle },
  { id: 'entender', number: '04', tag: 'POR TRÁS DO CUIDADO', title: 'Você sabe o que está trazendo novos contatos?', text: 'Quando tudo parece vir “da internet”, fica difícil decidir onde vale a pena investir.', solution: 'Acompanhamos de onde vêm os contatos para ajudar você a entender o que funciona e o que precisa de ajuste.', image: 'clarity', alt: 'Gestora revisando informações na clínica', outcome: 'Decidir com clareza', icon: MousePointer2 },
]

function Scene({ chapter }) {
  const Icon = chapter.icon
  if (IMAGES[chapter.image]) return <img className={styles.scenePhoto} src={asset(IMAGES[chapter.image])} alt={chapter.alt} loading="lazy" width="1200" height="1000" />
  if (chapter.image === 'trust') return <div className={styles.receptionScene}><img src={reception} alt="Cena conceitual de acolhimento na recepção de uma clínica" loading="lazy" width="1376" height="768" /><span className={styles.photoNote}>CADA DETALHE COMUNICA CUIDADO.</span></div>
  return <div className={`${styles.illustration} ${styles[chapter.image]}`}>
    <span className={styles.illustrationLabel}>O CAMINHO DO PACIENTE</span>
    <div className={styles.sceneCard}>
      <Icon size={28} strokeWidth={1.4} />
      {chapter.image === 'discovery' && <><div className={styles.searchBar}><Search size={16} /> Clínica perto de mim</div><div className={styles.result}><span className={styles.resultIcon}><MapPin /></span><div><strong>Sua clínica</strong><p>Seu atendimento. Na sua região.</p></div></div><span className={styles.miniLink}>Conhecer a clínica <ArrowUpRight size={15} /></span></>}
      {chapter.image === 'contact' && <><h3>O cuidado começa<br />na primeira conversa.</h3><p>Especialidades, localização e um próximo passo claro.</p><span className={styles.messageBubble}><MessageCircle size={18} /> Olá! Gostaria de saber mais sobre o atendimento.</span></>}
      {chapter.image === 'clarity' && <><h3>Da descoberta<br />ao contato.</h3><div className={styles.path}><span>Google</span><span>Seu site</span><span>WhatsApp</span></div><p>Entender o caminho ajuda a escolher o próximo passo.</p></>}
    </div>
    <span className={styles.illustrationCaption}>Ilustração da jornada · {chapter.outcome}</span>
  </div>
}

export default function Clinicas() {
  const [selected, setSelected] = useState('')
  const [capture, setCapture] = useState(null)
  const closeCapture = useCallback(() => setCapture(null), [])
  function openCapture(placement, challenge = selected) {
    const challengeId = challenges.find(c => c.label === challenge)?.id || 'geral'
    setSelected(challenge)
    setCapture({ source: `lp_clinicas_${placement}_${challengeId}`, challenge })
  }
  const captureWa = buildWhatsAppLink(`Olá! Vim pela LP da Pixelry e quero um diagnóstico sobre captação, automações e agentes de IA para minha clínica.${capture?.challenge ? ` Meu principal desafio: ${capture.challenge}.` : ''}`)
  const wa = buildWhatsAppLink(`Olá! Vim pela página para clínicas da Pixelry e quero conversar sobre captação, automações e agentes de IA.${selected ? ` Meu principal desafio: ${selected}.` : ''}`)
  const title = 'Automações, agentes de IA e captação para clínicas | Pixelry'
  const description = 'Conecte captação e atendimento com a Pixelry. Sites, automações e agentes de IA para responder contatos, organizar retornos e apoiar sua recepção.'
  return <div className={styles.page}>
    <Helmet>
      <title>{title}</title>
      <meta name="description" content={description} />
      <link rel="canonical" href="https://www.pixelry.com.br/clinicas" />
      <meta property="og:title" content={title} />
      <meta property="og:description" content={description} />
      <meta property="og:url" content="https://www.pixelry.com.br/clinicas" />
      <meta property="og:image" content="https://www.pixelry.com.br/assets/pixelry-hero.webp" />
      <meta property="og:image:width" content="1376" />
      <meta property="og:image:height" content="768" />
      <meta name="twitter:title" content={title} />
      <meta name="twitter:description" content={description} />
      <meta name="twitter:image" content="https://www.pixelry.com.br/assets/pixelry-hero.webp" />
    </Helmet>
    <header className={styles.header}>
      <Link to="/" className={styles.logo} aria-label="Pixelry — site institucional"><img src={logoImg} alt="" width="36" height="36" /> PIXELRY</Link>
      <nav aria-label="Navegação para clínicas"><a href="#jornada">Como ajudamos</a><a href="#automacoes">Automações e IA</a></nav>
      <button type="button" onClick={() => openCapture('nav')} className={styles.headerCta}>Quero um diagnóstico <ArrowUpRight size={16} /></button>
    </header>

    <section className={styles.hero}>
      <div className={styles.heroCopy}>
        <p className={styles.eyebrow}>CAPTAÇÃO + AUTOMAÇÕES + AGENTES DE IA</p>
        <h1>Mais atenção ao paciente.<br /><em>Menos oportunidades perdidas no caminho.</em></h1>
        <p>Conectamos seu site, o WhatsApp e a rotina da recepção com automações e agentes de IA. Para atrair contatos, agilizar respostas e acompanhar quem demonstrou interesse.</p>
        <button type="button" className={styles.button} onClick={() => openCapture('hero')}>Descobrir o que posso automatizar <ArrowUpRight size={18} /></button>
        <a className={styles.tourLink} href="#jornada"><ArrowDown size={16} /> Conheça esse caminho</a>
      </div>
      <div className={styles.heroVisual}><img src={IMAGES.hero ? asset(IMAGES.hero) : reception} alt="Cena conceitual de uma clínica acolhedora" width="1376" height="768" fetchpriority="high" /><div className={styles.heroCaption}><span className={styles.smallPixel} /> Do primeiro interesse ao próximo passo, cada contato importa.</div></div>
      <div className={styles.heroFoot}><span>ATRAIR. RESPONDER. ACOMPANHAR. MELHORAR.</span><span>PIXELRY / CADA ETAPA CONECTADA</span></div>
    </section>

    <section id="jornada" className={styles.intro}>
      <p className={styles.eyebrow}>VAMOS OLHAR PARA A SUA CLÍNICA?</p>
      <h2>Em qual parte do caminho<br />você sente que precisa de ajuda?</h2>
      <div className={styles.choices}>{challenges.map((c, i) => <a key={c.id} href={`#${c.id}`} onClick={() => setSelected(c.label)} className={selected === c.label ? styles.selected : ''}><span>0{i + 1}</span>{c.label}<ArrowUpRight size={18} /></a>)}</div>
    </section>

    <section id="automacoes" className={styles.automations}>
      <div className={styles.automationHeader}><p className={styles.eyebrow}>SUA RECEPÇÃO COM MAIS APOIO</p><h2>O interesse chegou.<br /><span className="grad-text">O que acontece depois?</span></h2><p>É aqui que automações e agentes de IA podem tirar tarefas repetitivas da equipe e dar continuidade ao atendimento.</p></div>
      <div className={styles.automationGrid}>{automations.map((item, i) => <article id={item.id} key={item.id}><span className={styles.eyebrow}>{item.label}</span><h3>{item.title}</h3><p>{item.text}</p><button type="button" className={styles.textLink} onClick={() => openCapture(item.id, challenges[i + 4].label)}>{item.cta} <ArrowUpRight size={17} /></button></article>)}</div>
      <div className={styles.automationFlow}><span>Contato recebido</span><ArrowUpRight size={16} /><span>IA identifica o interesse</span><ArrowUpRight size={16} /><span>Equipe recebe o contexto</span><ArrowUpRight size={16} /><span>Retorno organizado</span></div>
      <p className={styles.scopeNote}>Exemplo de fluxo. Integrações e ações são definidas no diagnóstico. A IA apoia o atendimento administrativo; decisões clínicas e situações que exigem atenção humana seguem com a equipe.</p>
      <button type="button" className={styles.button} onClick={() => openCapture('automacoes')}>Quero um plano para minha clínica <ArrowUpRight size={18} /></button>
    </section>

    <nav className={styles.journeyNav} aria-label="Etapas da jornada">{chapters.map(c => <a key={c.id} href={`#${c.id}`}><span>{c.number}</span>{c.outcome}</a>)}</nav>
    {chapters.map((chapter, i) => <section id={chapter.id} key={chapter.id} className={`${styles.chapter} ${i % 2 ? styles.reverse : ''}`}>
      <div className={styles.scene}><Scene chapter={chapter} /></div>
      <div className={styles.chapterCopy}><p className={styles.eyebrow}><span>{chapter.number} /</span> {chapter.tag}</p><h2>{chapter.title}</h2><p>{chapter.text}</p><div className={styles.solution}><span className={styles.smallPixel} /><div><h3>A Pixelry ajuda assim</h3><p>{chapter.solution}</p></div></div><button type="button" className={styles.textLink} onClick={() => openCapture(chapter.id, challenges[i].label)}>Quero resolver esse desafio <ArrowUpRight size={17} /></button></div>
    </section>)}

    <section id="projeto" className={styles.project}>
      <div><p className={styles.eyebrow}>UM PROJETO REAL</p><h2>O cuidado também<br />aparece na entrega.</h2><p>No projeto do Doutor Rogério, o site foi pensado para apresentar o profissional e facilitar o caminho até o agendamento. Este projeto apresenta nossa entrega de site.</p><button type="button" className={styles.button} onClick={() => openCapture('projeto')}>Quero conectar captação e atendimento <ArrowUpRight size={17} /></button><br /><a href="https://espi0-bat.github.io/site-rogerio/" target="_blank" rel="noreferrer" className={styles.textLink}>Visitar o projeto <ArrowUpRight size={18} /></a></div>
      <a className={styles.projectCard} href="https://espi0-bat.github.io/site-rogerio/" target="_blank" rel="noreferrer" aria-label="Visitar o site do Dr. Rogério Furtado (abre em nova aba)">
        <div className={styles.browserBar}><span aria-hidden="true">● ● ●</span><span>DR. ROGÉRIO FURTADO</span><ArrowUpRight size={16} /></div>
        <img className={styles.projectThumbnail} src={`${import.meta.env.BASE_URL}assets/portfolio/dr-rogerio-site.webp`} alt="Miniatura real do site do Dr. Rogério Furtado, com sua fotografia e apresentação do atendimento" width="1440" height="1000" loading="lazy" />
        <div className={styles.projectCaption}><div><h3>Dr. Rogério Furtado</h3><p>Site institucional · Oftalmologia</p></div><ArrowUpRight size={20} aria-hidden="true" /></div>
      </a>
    </section>

    <section className={styles.process}><p className={styles.eyebrow}>UM PASSO DE CADA VEZ</p><h2>Começamos entendendo você.</h2><div>{[{title:'Uma conversa sobre sua clínica',text:'Entendemos o momento, os desafios e o que você já tem hoje.'},{title:'Um caminho que faz sentido',text:'Definimos as prioridades e apresentamos o que será entregue.'},{title:'Cuidado depois da entrega',text:'Acompanhamos o que foi combinado e orientamos os próximos ajustes.'}].map((p,i)=><article key={p.title}><span>0{i+1}</span><h3>{p.title}</h3><p>{p.text}</p></article>)}</div><button type="button" className={styles.button} onClick={() => openCapture('processo')}>Preencher minha ficha de diagnóstico <ArrowUpRight size={18} /></button></section>

    <section className={styles.faq}><h2>Antes da nossa conversa.</h2>{[
      ['Já tenho um site. Posso contratar automações?', 'Sim. Avaliamos o que você já usa e quais etapas precisam de apoio. A proposta pode priorizar atendimento, retornos e integrações, aproveitando sua estrutura atual quando ela atende ao projeto.'],
      ['Preciso começar com anúncios?', 'Não necessariamente. Avaliamos primeiro se sua presença digital explica bem o atendimento e facilita o contato. Anúncios podem entrar quando fizerem sentido.'],
      ['O agente de IA substitui minha recepção?', 'Ele pode apoiar respostas administrativas e coletar informações iniciais, conforme o fluxo aprovado. Sua equipe assume exceções e situações que precisam de atenção humana. O agente não faz diagnóstico médico.'],
      ['A automação funciona com meu sistema de agenda?', 'Depende das integrações disponíveis. Conferimos a viabilidade antes da proposta e definimos o que pode ser automatizado, o que precisa de confirmação e quem acompanha o fluxo.'],
      ['Quanto custa?', 'O investimento depende dos fluxos, integrações, agente de IA, captação e acompanhamento definidos para sua clínica. Depois de entender sua clínica, apresentamos uma proposta com entregas e valores.'],
    ].map(([q,a])=><details key={q}><summary>{q}<span aria-hidden="true">+</span></summary><p>{a}</p></details>)}</section>

    <section id="diagnostico" className={styles.closing}>
      {IMAGES.closing && <img src={asset(IMAGES.closing)} alt="" loading="lazy" className={styles.closingImage} />}
      <p className={styles.eyebrow}>O PRÓXIMO PASSO É UMA CONVERSA</p><h2>Qual tarefa sua equipe<br />precisa tirar do manual?</h2><p>Preencha sua ficha para conversarmos com contexto sobre os gargalos, as prioridades e o investimento da sua clínica.</p>
      <label htmlFor="clinic-challenge">Qual é o principal desafio da sua clínica?</label>
      <select id="clinic-challenge" value={selected} onChange={e=>setSelected(e.target.value)}><option value="">Quero entender por onde começar</option>{challenges.map(c=><option key={c.id} value={c.label}>{c.label}</option>)}</select>
      <button type="button" className={styles.button} onClick={() => openCapture('final')}>Preencher ficha e pedir diagnóstico <ArrowUpRight size={18} /></button><small><Check size={14} /> Nossa equipe recebe seu cadastro antes da conversa.</small><a href={wa} target="_blank" rel="noreferrer" className={styles.directLink}>Prefiro uma conversa rápida no WhatsApp <MessageCircle size={16} /></a>
    </section>
    <LeadCaptureModal isOpen={!!capture} onClose={closeCapture} waLink={captureWa} source={capture?.source} context={capture?.challenge} />
    <footer className={styles.footer}><Link to="/" className={styles.logo}>PIXELRY</Link><p>Estratégia, design e tecnologia para aproximar pessoas.</p><div><Link to="/">Conheça a Pixelry</Link><Link to="/privacidade">Privacidade</Link><Link to="/termos">Termos de uso</Link></div></footer>
  </div>
}
