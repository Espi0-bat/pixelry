# Design system Pixelry — convenções

Sistema **dark-first** para páginas de captação de clientes. A identidade é o
gradiente roxo→ciano sobre fundo quase preto, com três famílias tipográficas
de papéis fixos.

## Envolva tudo em `DSProvider`

`DSProvider` é a raiz obrigatória. Ele faz duas coisas que nada mais faz:

1. **Pinta a superfície do tema.** Os tokens de texto (`--text`, `--text-dim`)
   só têm contraste sobre `--bg`. Sem o provider, variantes claras como
   `Button variant="secondary"` ficam ilegíveis — texto quase branco no branco.
2. **Fornece o contexto de navegação.** `PillNav` e `CookieConsent` usam
   `<Link>` e lançam erro fora de um Router.

```jsx
<DSProvider>
  <Section id="planos">
    <Label>SISTEMA E INVESTIMENTO</Label>
    <h2>Três formas de <GradText>estruturar</GradText>.</h2>
    <Button variant="whatsapp"><WhatsAppIcon />Iniciar diagnóstico</Button>
  </Section>
</DSProvider>
```

Use `padded={false}` para telas full-bleed.

## Idioma de estilo: tokens CSS + classes utilitárias

Não há props de estilo nem sistema de classes utilitárias tipo Tailwind.
Componentes carregam a aparência por conta própria; **para o seu próprio
layout, escreva CSS usando os tokens** — nunca valores literais.

**Cor e superfície**
`--bg` (fundo da página) · `--bg2` · `--bg3` (cartões) · `--surface`
`--purple` `--cyan` (marca) · `--grad` (gradiente 135°) · `--grad-text` (90°, para texto)
`--purple-text` — **use esta, não `--purple`, em texto pequeno**: o roxo puro fica em 3,5:1
`--text` `--text-dim` `--text-faint` (hierarquia de texto)
`--border` `--border-bright`

**Tipografia** — três papéis fixos, não intercambiáveis:
`--font-display` (Inter) títulos · `--font-body` (DM Sans) corpo · `--font-mono` (JetBrains Mono) rótulos, botões e números
Escala: `--fs-body` `--fs-intro` `--fs-label` · Entrelinha: `--lh-heading` `--lh-sub` `--lh-body`

**Layout**
`--section-pad` / `--section-pad-mobile` — respiro de seção (já aplicado por `Section`)

**Classes globais** (disponíveis sem importar componente):
`.grad-text` · `.grad-line` · `.label` · `.section-wrap` · `.wa-icon`
`.btn-primary` `.btn-whatsapp` `.btn-hero-cta` `.btn-secondary` `.btn-client-area`
— prefira o componente `Button` a estas classes.
`.reveal` + `.reveal-d1`…`.reveal-d4` — animação de entrada por scroll; exige
um IntersectionObserver que adicione `.visible`, **que este bundle não inclui**.
Sem esse observer o elemento fica em `opacity: 0`. Só use se você mesmo
implementar o observer.

## Hierarquia de botões

`primary` gradiente, ação padrão · `whatsapp` CTA sólido de conversão ·
`hero` verde de alto contraste, **só na dobra principal, um por página** ·
`secondary` link discreto em mono · `clientArea` secundário com contorno.

## Mobile-first

O site é construído mobile-first. Alvos de toque mínimos de 44px; campos de
formulário com fonte de 16px em telas pequenas (abaixo disso o iOS amplia a
página ao focar).

## Onde está a verdade

Leia antes de estilizar: `_ds/<pasta>/styles.css` e o que ele importa
(`_ds_bundle.css` carrega tokens e classes globais). Cada componente tem
`components/general/<Nome>/<Nome>.prompt.md` com sua API e
`<Nome>.d.ts` com o contrato de props.
