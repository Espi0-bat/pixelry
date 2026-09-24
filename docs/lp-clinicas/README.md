# LP para clínicas — Pixelry

## Prévia e objetivo

Página: `/clinicas`. Apresenta o caminho do paciente (encontrar, confiar, entrar em contato) e o papel da Pixelry. A rolagem é normal e as etapas podem ser acessadas diretamente. O institucional, `/portal` e `/admin` permanecem nas suas rotas.

A primeira versão já inclui hero, escolha de desafio, quatro etapas, referência ao projeto real do Doutor Rogério, processo, perguntas frequentes e convite ao WhatsApp. A escolha do desafio preenche uma mensagem que o visitante revisa antes de enviar; selecionar uma opção não envia nada. Nesta versão não há novo formulário nem gravação de leads. A captura existente do institucional permanece independente.

## Gerar imagens no Gemini, uma por vez

1. Abra o prompt da cena abaixo.
2. Anexe `public/assets/pixelry-hero.webp` como referência visual. Essa é a recepção já aprovada. Use também as cenas anteriores aprovadas para manter continuidade.
3. Copie o bloco “Prompt principal” inteiro e gere apenas aquela cena.
4. Revise mãos, rostos, perspectiva, materiais e recorte. Não aceite marcas, textos ou números inventados.
5. Salve o original em alta resolução. Depois exporte a versão WebP para o caminho indicado; não basta renomear a extensão de um JPEG.
6. Atualize a chave correspondente de `IMAGES` em `src/pages/Clinicas.jsx` com o nome do arquivo (sem diretório). Exemplo: `discovery: '02-descoberta.webp'`.
7. Confira desktop e celular na prévia. Se precisar, use o prompt de recomposição mobile do mesmo arquivo.

| Ordem | Prompt | Arquivo final | Chave |
|---|---|---|---|
| 1 | [A chegada](prompts/01-chegada.md) | `01-chegada.webp` | `hero` |
| 2 | [Ser encontrada](prompts/02-descoberta.md) | `02-descoberta.webp` | `discovery` |
| 3 | [Transmitir confiança](prompts/03-confianca.md) | `03-confianca.webp` | `trust` |
| 4 | [Facilitar o contato](prompts/04-contato.md) | `04-contato.webp` | `contact` |
| 5 | [Entender o que funciona](prompts/05-clareza.md) | `05-clareza.webp` | `clarity` |
| 6 | [A próxima conversa](prompts/06-conversa.md) | `06-conversa.webp` | `closing` |

## Direção visual

Uma mesma clínica conceitual brasileira: madeira clara, marfim, vidro curvo, plantas e luz natural quente. Pessoas em situações espontâneas. O roxo é um acento da marca; a página aplica os elementos gráficos. Não gerar molduras de pixels nem interfaces dentro das fotografias. Fotos de IA são cenas conceituais; não apresentá-las como clientes reais.

Desktop: grandes imagens ao lado de textos curtos. Celular: texto e imagem em sequência. A interface da LP segue os tokens do site principal em `src/index.css`: fundos escuros, superfícies azuladas, gradiente roxo–ciano e tipografia Inter / DM Sans / JetBrains Mono. Marfim e madeira pertencem apenas aos ambientes fotografados, nunca à paleta da interface. Sem passeio 3D nem rolagem forçada.

## Estado das imagens e provas

- Hero e confiança usam a recepção já produzida enquanto aguardam as cenas específicas.
- Descoberta, contato e clareza usam ilustrações de interface em HTML/CSS identificadas como ilustrações, sem métricas fictícias.
- O encerramento funciona com fundo violeta até receber a imagem.
- O projeto Doutor Rogério tem uma miniatura real e clicável do site publicado, em `public/assets/portfolio/dr-rogerio-site.webp`. As fotos originais do projeto estão em `../site-rogerio/assets/`.
- Nenhuma imagem pendente é requisitada; cada chave `null` usa a composição provisória.

## Integração e revisão

- Conteúdo e mapa de imagens: `src/pages/Clinicas.jsx`.
- Estilos próprios: `src/pages/Clinicas.module.css`.
- Rota e separação da navegação: `src/App.jsx`.
- Link no institucional: rodapé, “Soluções para clínicas”.
- `/clinicas` incluída no prerender e sitemap, com título, descrição e canonical próprios.
- Imagens: WebP, idealmente abaixo de 250 KB por cena, preservando qualidade. Hero tem carregamento prioritário; demais imagens carregam sob demanda.

Antes de publicar: integrar fotos aprovadas, conferir recortes em 320/390/768/1440 px, revisar todos os links e o WhatsApp, testar teclado e redução de movimento, confirmar o escopo comercial e conferir as informações do projeto real. Comparar contatos qualificados por origem quando houver uma implementação de mensuração acordada; essa mensuração ainda não foi adicionada nesta etapa.
