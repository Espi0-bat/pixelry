/**
 * Traduz o campo `source` da tabela `leads` para algo legível no painel.
 *
 * A LP /clinicas grava `lp_clinicas_<lugar>_<desafio>`: o lugar é o ponto da
 * página onde a pessoa clicou, o desafio é a dor que ela tinha escolhido até
 * ali (ou `geral`, quando abriu o formulário sem escolher nenhuma). O site
 * institucional grava `hero_cta`; `diagnostico_hero` é o padrão antigo.
 *
 * Importante ao ler os rankings: isto conta CADASTRO ENVIADO, não clique.
 * Quem abriu o formulário e desistiu não aparece aqui.
 */

const LUGARES = {
  nav: 'Menu da LP',
  hero: 'Topo da LP',
  automacoes: 'Bloco de automações',
  respostas: 'Card · Agilizar respostas',
  perguntas: 'Card · Agente de IA',
  retorno: 'Card · Organizar retornos',
  rotina: 'Card · Automatizar rotina',
  encontrar: 'Etapa 1 · Ser encontrada',
  confiar: 'Etapa 2 · Transmitir confiança',
  contato: 'Etapa 3 · Facilitar o contato',
  entender: 'Etapa 4 · Decidir com clareza',
  projeto: 'Projeto Dr. Rogério',
  processo: 'Bloco de processo',
  final: 'Chamada final',
}

const DESAFIOS = {
  encontrar: 'Dependo muito de indicação',
  confiar: 'Site não representa a clínica',
  contato: 'Poucas visitas viram contatos',
  entender: 'Não sei o que traz resultado',
  respostas: 'Demoramos para responder',
  perguntas: 'Equipe repete as mesmas respostas',
  retorno: 'Contatos ficam sem retorno',
  rotina: 'Lembretes e confirmações manuais',
  geral: 'Não escolheu um desafio',
}

const HOME = {
  hero_cta: 'Topo da home',
  diagnostico_hero: 'Diagnóstico (padrão antigo)',
}

const VAZIO = '—'

export function parseSource(source) {
  const raw = (source || '').trim()
  if (!raw) return { canal: 'Não informado', lugar: VAZIO, desafio: VAZIO, raw: '' }

  if (raw.startsWith('lp_clinicas_')) {
    const partes = raw.split('_')
    const lugar = partes[2] || ''
    const desafio = partes[3] || ''
    return {
      canal: 'LP Clínicas',
      lugar: LUGARES[lugar] || lugar || VAZIO,
      desafio: DESAFIOS[desafio] || desafio || VAZIO,
      raw,
    }
  }

  if (HOME[raw]) return { canal: 'Home', lugar: HOME[raw], desafio: VAZIO, raw }

  return { canal: 'Outro', lugar: raw, desafio: VAZIO, raw }
}

/** Ranking de um campo já traduzido, do mais frequente para o menos. */
export function ranking(leads, campo) {
  const contagem = new Map()
  let total = 0
  for (const lead of leads) {
    const valor = parseSource(lead.source)[campo]
    if (valor === VAZIO) continue
    contagem.set(valor, (contagem.get(valor) || 0) + 1)
    total += 1
  }
  return [...contagem.entries()]
    .map(([valor, quantidade]) => ({
      valor,
      quantidade,
      porcentagem: total ? Math.round((quantidade / total) * 100) : 0,
    }))
    .sort((a, b) => b.quantidade - a.quantidade || a.valor.localeCompare(b.valor))
}
