import { createClient } from '@supabase/supabase-js'

export function getSupabase() {
  const env = (globalThis as typeof globalThis & { Netlify?: { env?: { get: (name: string) => string | undefined } } }).Netlify?.env
  const url = env?.get('SUPABASE_URL')
  const key = env?.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!url || !key) return null
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
}

export async function createEmbedding(input: string): Promise<number[] | null> {
  const apiKey = (globalThis as typeof globalThis & { Netlify?: { env?: { get: (name: string) => string | undefined } } }).Netlify?.env?.get('OPENAI_API_KEY')
  if (!apiKey) return null
  const response = await fetch('https://api.openai.com/v1/embeddings', {
    method: 'POST',
    headers: { authorization: `Bearer ${apiKey}`, 'content-type': 'application/json' },
    body: JSON.stringify({ model: 'text-embedding-3-small', input, dimensions: 1536 }),
  })
  if (!response.ok) throw new Error('Não foi possível gerar a busca semântica.')
  const body = await response.json() as { data: Array<{ embedding: number[] }> }
  return body.data[0]?.embedding ?? null
}
