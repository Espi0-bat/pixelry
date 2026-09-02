import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { HelmetProvider } from 'react-helmet-async'
import App from './App.jsx'
import './index.css'
import './print.css'

const raiz = document.getElementById('root')

const arvore = (
  <React.StrictMode>
    <HelmetProvider>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </HelmetProvider>
  </React.StrictMode>
)

// O build pré-renderiza as rotas públicas (scripts/prerender.mjs). Quando o
// HTML já chega pronto do servidor, hidratamos em vez de recriar do zero —
// senão o React descarta o conteúdo servido e a página pisca no primeiro paint.
if (raiz.hasChildNodes()) {
  ReactDOM.hydrateRoot(raiz, arvore)
} else {
  ReactDOM.createRoot(raiz).render(arvore)
}
