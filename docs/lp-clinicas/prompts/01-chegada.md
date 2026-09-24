# 01 — A chegada

- **Uso:** hero da LP.
- **Arquivo final no projeto:** `public/assets/clinicas/01-chegada.webp`.
- **Chave em `src/pages/Clinicas.jsx`:** `IMAGES.hero`.
- **Formato:** 16:9, idealmente 2400 × 1350 pixels.
- **Referências para anexar ao Gemini:** recepção atual (`public/assets/pixelry-hero.webp`) e imagens anteriores já aprovadas.

## Prompt principal

Copie todo o bloco abaixo, anexe as referências e gere uma imagem por vez.

```text
Crie uma fotografia editorial para a landing page da Pixelry, uma agência de estratégia, design e presença digital para clínicas brasileiras. Esta imagem integra uma série que acompanha o caminho do paciente até a clínica.

REFERÊNCIA OBRIGATÓRIA
Use a imagem da recepção anexada como referência de arquitetura, materiais, iluminação e tratamento de cor. Preserve a sensação de um mesmo lugar: madeira clara, paredes em marfim, vidro curvo, plantas naturais e luz quente suave. Se houver imagens aprovadas de outras cenas anexadas, mantenha continuidade com elas. A referência estabelece o ambiente, mas o enquadramento deve seguir a cena solicitada.

DIREÇÃO DE ARTE
Fotografia realista e acolhedora, com composição editorial refinada. Clínica brasileira contemporânea de porte acessível, bem cuidada, com escala humana. Tons de pele naturais e diversidade brasileira. Roxo ametista discreto em um objeto ou detalhe arquitetônico; marfim, madeira e verde natural como base. Luz natural combinada à iluminação indireta quente. Profundidade de campo moderada: ambiente reconhecível, pessoas nítidas. Anatomia e mãos naturais, expressões espontâneas. Linguagem visual serena e profissional.

RESTRIÇÕES
Não incluir textos, números, logotipos, marcas d’água, interfaces legíveis, prontuários ou dados pessoais. Não adicionar gráficos de resultados, estrelas de avaliação, cruzes médicas, símbolos hospitalares, hologramas ou partículas neon. Não desenhar bordas nem molduras de pixels: a identidade gráfica será aplicada no site. Não representar procedimentos, diagnósticos, sofrimento ou resultados de tratamentos. Não copiar o rosto de uma pessoa real a partir de referência sem autorização. A cena é conceitual e não deve se apresentar como cliente real da Pixelry.

QUALIDADE
Entregue uma imagem única, sem montagem de alternativas, em alta resolução. Preserve detalhes naturais de pele, tecidos, madeira e vidro. Evite aparência plástica, excesso de nitidez e sorrisos de publicidade genérica.

CENA
Fotografe a entrada de uma clínica acolhedora, vista da calçada em perspectiva de três quartos. Pela porta de vidro é possível reconhecer a recepção da referência: balcão de madeira clara, luz quente e vidro curvo ao fundo. Uma pessoa adulta se aproxima da porta de forma natural. Fachada sóbria, sem nome, sem letreiros, sem logos. Sugira um estabelecimento brasileiro real, sem luxo ostensivo.

COMPOSIÇÃO
Concentre porta, arquitetura principal e pessoa nos 60% à direita. Mantenha a área à esquerda simples, em sombra suave e com baixa complexidade visual. Não crie uma faixa preta artificial. A imagem será usada em um painel vertical com topo arredondado no desktop e em um recorte mais horizontal no celular: o núcleo da cena precisa funcionar nos dois formatos. Mantenha a pessoa inteira dentro da área central-direita e afastada das bordas. Reserve a parte inferior para uma pequena legenda aplicada posteriormente no site.

FORMATO DE ENTREGA
16:9, idealmente 2400 × 1350 pixels. Sem texto embutido. A imagem precisa aceitar recortes responsivos, mantendo os elementos essenciais nas áreas especificadas.
```

## Revisão antes de aprovar

- A cena comunica “a chegada” sem precisar de uma legenda técnica?
- Materiais e iluminação combinam com a recepção de referência?
- Mãos, rostos, móveis e perspectiva estão naturais?
- Não há letras, marcas, números ou informações inventadas?
- O assunto principal continua legível quando a imagem é recortada no celular?

## Prompt de ajuste para celular, se necessário

Use só se o recorte da imagem aprovada não funcionar. Anexe a versão aprovada.

```text
Recomponha esta mesma cena para proporção 4:5. Preserve ambiente, pessoas, roupas, materiais, iluminação e tratamento fotográfico. Reorganize o enquadramento para manter o assunto principal no centro, com rostos e mãos íntegros e espaço nas bordas. Não adicione objetos, personagens, letras, marcas ou interfaces. Entregue uma imagem única com pelo menos 1200 × 1500 pixels.
```

Salve a variante como `01-chegada-mobile.webp`. A primeira versão da LP usa recorte CSS; a variante mobile requer inclusão em um elemento `<picture>` quando integrada.
