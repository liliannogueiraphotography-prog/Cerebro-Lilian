import type { SupabaseClient } from '@supabase/supabase-js'
import { createEmbedding } from './_shared'

export type MemoryResult = { id: string; title: string; content: string; kind: string; status: string; agent_slug?: string; similarity?: number }

export async function retrieveMemory(supabase: SupabaseClient, query: string, limit = 8): Promise<MemoryResult[]> {
  const embedding = await createEmbedding(query)
  if (embedding) {
    const { data, error } = await supabase.rpc('match_brain_nodes', { query_embedding: embedding, match_count: limit, filter_kind: null })
    if (error) throw error
    return (data ?? []) as MemoryResult[]
  }
  const { data, error } = await supabase
    .from('brain_nodes')
    .select('id,title,content,kind,status,agent_slug')
    .textSearch('search_vector', query, { type: 'websearch', config: 'portuguese' })
    .limit(limit)
  if (error) throw error
  return (data ?? []) as MemoryResult[]
}

export async function logEvent(supabase: SupabaseClient, input: { eventType: string; actorType: 'harness' | 'agent' | 'system' | 'connector'; actorId?: string; entityType: string; entityId?: string; data?: Record<string, unknown> }) {
  await supabase.from('brain_events').insert({
    event_type: input.eventType,
    actor_type: input.actorType,
    actor_id: input.actorId,
    entity_type: input.entityType,
    entity_id: input.entityId,
    data: input.data ?? {},
  })
}
