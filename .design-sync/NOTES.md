# design-sync — notas do repositório Pixelry

## O que este repo é (e o que foi sincronizado)

Este repo é uma **aplicação Vite**, não uma biblioteca de componentes. O `dist/`
é o site compilado (index.html + chunks), e os 25 arquivos em `src/components/`
são majoritariamente **seções desta home** (Hero, Planos, Faq, Manifesto…) com
copy fixa — não são peças de design system.

A biblioteca sincronizada foi **criada para este fim**, em `src/ds/`:

- `src/ds/index.js` — entrypoint; exporta as primitivas + os componentes reutilizáveis
- `src/ds/primitives.jsx` — Button, Label, GradText, GradLine, Section (invólucros finos
  sobre as classes globais que já existiam em `src/index.css` — nenhum estilo reimplementado)
- `src/ds/DSProvider.jsx` — superfície do tema + MemoryRouter
- `src/ds/fonts.css` — `@import` do Google Fonts (ver abaixo)
- `src/ds/index.d.ts` — tipos escritos à mão (Vite lib mode não emite `.d.ts`)

Build separado do site: `npm run build:ds` → `dist-ds/` (config em `vite.lib.config.js`).
**O build do site (`npm run build` → `dist/`) não foi alterado.**

## Decisões deliberadas

- **Seções de página ficaram de fora.** Hero, Planos, Servicos, Core, Cases,
  Transformacao etc. são composições desta página, com texto fixo. Incluí-las
  daria ao agente de design a home da Pixelry fatiada em vez de peças reutilizáveis.
  Se um dia forem parametrizadas por props, viram candidatas legítimas.
- **`DSProvider` pinta a superfície escura.** O scaffold do card de preview fixa
  `body{background:#fff}` (em `lib/emit.mjs`, que a skill proíbe forkar). Como o DS
  é dark-first, sem uma superfície própria as variantes de texto claro ficavam
  invisíveis. Pintar no provider é correto também em uso real — qualquer tela
  Pixelry vive sobre `--bg`.
- **`DSProvider` excluído da lista de componentes** (`componentSrcMap: {"DSProvider": null}`).
  Como ele é o `cfg.provider`, ter um card próprio aninhava dois `<Router>` e
  disparava `[RENDER_ERRORS]`. Ele continua exportado no bundle.

## Armadilhas do build

- **`package.json` precisa do campo `types`.** O extrator lê `pj.types` para achar
  o `.d.ts` (`lib/dts.mjs:90`). Sem ele: `[ZERO_MATCH]`, 0 componentes, apesar de
  o bundle ter 11 exports. Está apontando para `./dist-ds/index.es.d.ts`.
- **`@types/react` tem que estar no `node_modules` do repo**, não só no `.ds-sync/`.
  Fixado em `^18` para casar com o React 18 do projeto — com os tipos v19 o
  namespace `JSX` global não resolve.
- **Playwright: use a 1.59.1.** O chromium em cache nesta máquina é o build 1217;
  1.60/1.61 fixam o 1228 e a 1.62 fixa o 1234 — qualquer uma delas falha com
  `Executable doesn't exist`.
- **Fontes.** O site carrega Inter, DM Sans e JetBrains Mono via `<link>` no
  `index.html`, que não existe numa tela gerada. `src/ds/fonts.css` traz o mesmo
  `@import` só para o bundle — sem ele, `[FONT_MISSING]` e tudo renderiza em fonte
  de sistema. O `@import` é hoisted para o topo do CSS pelo Vite (verificado).

## Avisos de render conhecidos

- `[FONT_REMOTE]` — esperado, é o `@import` do Google Fonts em `src/ds/fonts.css`.
- `[GRID_OVERFLOW]` no PillNav — resolvido com `overrides.PillNav.cardMode: "column"`.
  A nav é mais larga que uma célula de grade por natureza.

## Decisões de preview

- **PillNav não tem célula para `activeHref`.** O indicador de ativo é um ponto de
  12px na cor `baseColor` (`#101022`) que, contra a superfície do tema (`#070710`),
  fica indistinguível — a célula ficava idêntica a `Navegacao`. A prop funciona;
  só não rende diferença visível em card estático.
- **PillNav usa um logo em data-URI**, não o `pixelryicone.jpeg` do repo: o preview
  compila fora do pipeline do Vite e não resolve imports de imagem.
- **4 componentes no floor card** (CaseModal, CookieConsent, LeadCaptureModal,
  GradLine): escolha do usuário nesta rodada ("só os essenciais"). Totalmente
  funcionais; podem ganhar preview em qualquer re-sync.

## Riscos de re-sync

- **`src/ds/index.d.ts` é escrito à mão.** Se a API de um componente mudar
  (props novas em `PillNav`, `LeadCaptureModal`, `CaseModal`), o `.d.ts` **não**
  acompanha sozinho — o agente de design passa a codar contra um contrato falso.
  Revise-o sempre que mexer nesses componentes.
- **`LeadCaptureModal` fala com o Supabase.** Fora do site o cliente é `null`
  (`isSupabaseConfigured` falso), então ele renderiza mas o envio quebraria.
  Nenhum preview envia o formulário. Se um dia um preview precisar do fluxo
  completo, injete o envio por prop em vez de acoplar ao Supabase.
- **A lista de campos de qualificação do modal está no componente**, não em config.
  Mudou lá, muda no card.
- **`vite.lib.config.js` fixa `define` para as variáveis `VITE_*`.** Variável nova
  lida por um componente do DS precisa entrar nessa lista, senão sobra
  `import.meta.env` no bundle e o IIFE do conversor quebra.
- **O ponto de entrada do conversor é `dist-ds/index.es.js`** — rode `npm run build:ds`
  antes do re-sync, senão você sincroniza o bundle antigo.
