# PIXELRY — Estúdio Digital

Landing page da PIXELRY construída com **React + Vite**.  
Design dark premium com gradiente roxo → ciano, grid de pontos animado e formas geométricas.

---

## Estrutura do projeto

```
pixelry/
├── .github/
│   └── workflows/
│       └── deploy.yml          # CI/CD automático → GitHub Pages
├── public/
├── src/
│   ├── components/
│   │   ├── Nav.jsx / .module.css
│   │   ├── Hero.jsx / .module.css
│   │   ├── Problema.jsx / .module.css
│   │   ├── Servicos.jsx / .module.css
│   │   ├── Processo.jsx / .module.css
│   │   ├── Diferenciais.jsx / .module.css
│   │   ├── Showcase.jsx / .module.css
│   │   ├── ParaQuem.jsx / .module.css
│   │   ├── Manifesto.jsx / .module.css
│   │   ├── CtaFinal.jsx / .module.css
│   │   └── Footer.jsx / .module.css
│   ├── hooks/
│   │   └── useReveal.js        # IntersectionObserver para scroll animations
│   ├── App.jsx
│   ├── index.css               # CSS variables, resets, utilitários globais
│   └── main.jsx
├── index.html
├── package.json
├── vite.config.js
└── .gitignore
```

---

## Instalação e desenvolvimento local

```bash
# 1. Instalar dependências
npm install

# 2. Rodar em dev
npm run dev

# 3. Build de produção
npm run build

# 4. Preview do build
npm run preview
```

---

## Deploy no GitHub Pages

### Configuração única (fazer antes do primeiro push)

1. **Renomear o `base` no `vite.config.js`** para o nome do seu repositório:
   ```js
   base: '/nome-do-seu-repo/',
   ```

2. **Criar o repositório no GitHub** com o mesmo nome.

3. **Ativar GitHub Pages** via Actions:
   - Vá em **Settings → Pages**
   - Em "Source", selecione **GitHub Actions**

4. **Push para a branch `main`** — o deploy acontece automaticamente.

### URL final
```
https://seu-usuario.github.io/nome-do-seu-repo/
```

---

## Personalização

| O que mudar          | Arquivo                        |
|----------------------|--------------------------------|
| Número do WhatsApp   | `Hero.jsx`, `Nav.jsx`, `CtaFinal.jsx` (constante `WA_LINK`) |
| Textos e copy        | Cada componente da seção       |
| Cores da marca       | `src/index.css` (`:root`)      |
| Fontes               | `index.html` + `index.css`     |
| Serviços e segmentos | `Servicos.jsx`, `ParaQuem.jsx` (arrays de dados) |

---

## Stack

- **React 18** + **Vite 5**
- **CSS Modules** — zero dependências de estilo externas
- **Canvas API** — grid de pontos animado no Hero
- **IntersectionObserver** — reveal animations no scroll
- **Google Fonts** — Syne + DM Sans + JetBrains Mono
