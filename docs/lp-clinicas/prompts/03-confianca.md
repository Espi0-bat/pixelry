# 03 — Transmitir confiança

- **Uso:** etapa 02 — transmitir confiança.
- **Arquivo final no projeto:** `public/assets/clinicas/03-confianca.webp`.
- **Chave em `src/pages/Clinicas.jsx`:** `IMAGES.trust`.
- **Formato:** 6:5, idealmente 1800 × 1500 pixels.
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
Novo ângulo da mesma recepção da imagem de referência, visto a partir da porta de entrada, como se o visitante estivesse chegando. Balcão de madeira clara à direita, poltronas acolhedoras e planta à esquerda, divisória de vidro curvo ao fundo. Uma profissional da clínica, com roupa discreta em tom marfim ou azul profundo, está presente ao fundo com expressão receptiva, sem posar para a câmera. Priorize a arquitetura e a sensação de cuidado.

COMPOSIÇÃO
Use as linhas naturais do ambiente para convidar o olhar a entrar. Evite uma grande área vazia de piso. Mantenha o ponto de interesse no centro para recortes quadrados e horizontais. Arquitetura fisicamente plausível, portas e móveis proporcionais. Fotografia limpa, sem intervenções gráficas. Não inventar certificações, diplomas legíveis ou marcas médicas.

FORMATO DE ENTREGA
6:5, idealmente 1800 × 1500 pixels. Sem texto embutido. A imagem precisa aceitar recortes responsivos, mantendo os elementos essenciais nas áreas especificadas.
```

## Revisão antes de aprovar

- A cena comunica “transmitir confiança” sem precisar de uma legenda técnica?
- Materiais e iluminação combinam com a recepção de referência?
- Mãos, rostos, móveis e perspectiva estão naturais?
- Não há letras, marcas, números ou informações inventadas?
- O assunto principal continua legível quando a imagem é recortada no celular?

## Prompt de ajuste para celular, se necessário

Use só se o recorte da imagem aprovada não funcionar. Anexe a versão aprovada.

```text
Recomponha esta mesma cena para proporção 4:5. Preserve ambiente, pessoas, roupas, materiais, iluminação e tratamento fotográfico. Reorganize o enquadramento para manter o assunto principal no centro, com rostos e mãos íntegros e espaço nas bordas. Não adicione objetos, personagens, letras, marcas ou interfaces. Entregue uma imagem única com pelo menos 1200 × 1500 pixels.
```

Salve a variante como `03-confianca-mobile.webp`. A primeira versão da LP usa recorte CSS; a variante mobile requer inclusão em um elemento `<picture>` quando integrada.
