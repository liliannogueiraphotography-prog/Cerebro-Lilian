import { describe, expect, it } from 'vitest'
import ingest from '../netlify/functions/ingest'
import lumaRun from '../netlify/functions/luma-run'
import harness from '../netlify/functions/harness'
import graph from '../netlify/functions/brain-graph'

function event(method: string, body?: unknown) {
  return new Request('https://cerebro-lilian.local/api/test', { method, body: body ? JSON.stringify(body) : undefined, headers: { 'content-type': 'application/json' } })
}

describe('API sem credenciais', () => {
  it('captura texto sem exigir formulário manual', async () => {
    const response = await ingest(event('POST', { sourceKind: 'text', text: 'A decisão é não publicar produtos sem revisão de margem.' }), {} as any)
    expect(response.status).toBe(200)
    expect((await response.json()).status).toBe('captured')
  })

  it('encaminha uma análise Luma sem disparar Shopify', async () => {
    const response = await lumaRun(event('POST', { objective: 'analisar produtos aprovados e margem', execution: true }), {} as any)
    expect(response.status).toBe(200)
    expect((await response.json()).agent).toBe('luma')
  })

  it('mantém uma ação de pagamento parada', async () => {
    const response = await harness(event('POST', { task: 'pagar o fornecedor da Luma' }), {} as any)
    expect(response.status).toBe(200)
    expect((await response.json()).route.state).toBe('waiting_approval')
  })

  it('não inventa nós do grafo quando a memória central não está conectada', async () => {
    const response = await graph()
    expect(response.status).toBe(200)
    expect((await response.json()).nodes).toEqual([])
  })
})
