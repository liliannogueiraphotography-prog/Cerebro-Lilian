import type { Config } from '@netlify/functions'
import { getSupabase } from './_shared'

export default async () => {
  const supabase = getSupabase()
  if (!supabase) return Response.json({ nodes: [], relations: [], mode: 'awaiting-central-memory' })
  const { data, error } = await supabase.rpc('get_brain_graph', { max_nodes: 250, include_archived: false })
  if (error) return Response.json({ error: error.message }, { status: 500 })
  return Response.json({ ...(data as { nodes: unknown[]; relations: unknown[] }), mode: 'central-memory' })
}

export const config: Config = { path: '/api/brain-graph' }
