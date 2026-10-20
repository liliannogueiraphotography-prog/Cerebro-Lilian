import type { Config } from '@netlify/functions'
import { createEmbedding, getSupabase } from './_shared'

export default async (req: Request) => {
  const query = new URL(req.url).searchParams.get('q')?.trim()
  if (!query) return Response.json({ error: 'Informe o que deseja encontrar.' }, { status: 400 })
  const supabase = getSupabase()
  if (!supabase) return Response.json({ results: [], mode: 'local-preview' })
  try {
    const embedding = await createEmbedding(query)
    if (embedding) {
      const { data, error } = await supabase.rpc('match_brain_nodes', { query_embedding: embedding, match_count: 12, filter_kind: null })
      if (error) throw error
      return Response.json({ results: data, mode: 'semantic' })
    }
    const { data, error } = await supabase.from('brain_nodes').select('id,title,kind,content,updated_at').textSearch('search_vector', query, { type: 'websearch' }).limit(12)
    if (error) throw error
    return Response.json({ results: data?.map((item) => ({ ...item, excerpt: item.content?.slice(0, 180) })), mode: 'keyword-fallback' })
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : 'Falha na busca.' }, { status: 500 })
  }
}

export const config: Config = { path: '/api/brain-search' }
