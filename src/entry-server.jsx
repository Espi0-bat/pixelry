import { StrictMode } from 'react'
import { PassThrough } from 'node:stream'
import { renderToPipeableStream } from 'react-dom/server'
import { StaticRouter } from 'react-router'
import { HelmetProvider } from 'react-helmet-async'
import App from './App.jsx'

/**
 * Entrada de SSR usada só no build (scripts/prerender.mjs) — nunca no browser.
 *
 * Usa renderToPipeableStream em vez de renderToString porque o App carrega
 * quase toda a home com React.lazy: um render síncrono devolveria só o
 * fallback do Suspense, e o crawler continuaria sem Core, Planos, Cases e FAQ.
 * onAllReady espera todo Suspense resolver, que é exatamente o modo pensado
 * para geração estática.
 */
export function render(url, { timeoutMs = 20000 } = {}) {
  const helmetContext = {}

  return new Promise((resolve, reject) => {
    const chunks = []
    const sink = new PassThrough()
    sink.on('data', (c) => chunks.push(c))
    sink.on('end', () =>
      resolve({
        html: Buffer.concat(chunks).toString('utf8'),
        helmet: helmetContext.helmet,
      })
    )
    sink.on('error', reject)

    const { pipe, abort } = renderToPipeableStream(
      <StrictMode>
        <HelmetProvider context={helmetContext}>
          <StaticRouter location={url}>
            <App />
          </StaticRouter>
        </HelmetProvider>
      </StrictMode>,
      {
        // Só drenamos o stream depois que tudo resolveu; assim o HTML sai
        // completo e em ordem, sem os <template> de streaming fora de ordem.
        onAllReady() {
          pipe(sink)
        },
        onError(err) {
          reject(err)
        },
      }
    )

    const guard = setTimeout(() => {
      abort()
      reject(new Error(`SSR de "${url}" passou de ${timeoutMs}ms`))
    }, timeoutMs)
    sink.on('end', () => clearTimeout(guard))
  })
}
