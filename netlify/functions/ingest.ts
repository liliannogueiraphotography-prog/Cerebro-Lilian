import type { Config } from '@netlify/functions'
import { chooseAgent } from '../../src/lib/agents'
import { createEmbedding, getSupabase } from './_shared'
import { logEvent } from './_memory'

type IngestionRequest = {
  sourceKind: 'text' | 'link' | 'pdf' | 'image' | 'audio' | 'video' | 'instagram_saved' | 'gmail' | 'google_drive' | 'shopify' | 'browser_use'
  text?: string
  url?: string
  storagePath?: string
  mediaType?: string
  externalId?: string
  title?: string
  metadata?: Record<string, unknown>
}

function detectKind(text: string) {
  if (/\b(decid|fica definido|regra|n[aã]o pode)\b/i.test(text)) return 'decision'
  if (/\b(tarefa|fazer|pend[eê]ncia|pr[oó]ximo passo)\b/i.test(text)) return 'task'
  if (/\b(projeto|luma|bel[eé]m|metamorfose)\b/i.test(text)) return 'project'
  return 'source'
}

function canonicalKey(kind: string, title: string) {
  return `${kind}:${title.toLocaleLowerCase('pt-BR').normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '')}`
}

export default async (req: Request) => {
  if (req.method !== 'POST') return Response.json({ error: 'Use POST.' }, { status: 405 })
  const request = await req.json() as IngestionRequest
  if (!request.sourceKind || (!request.text?.trim() && !request.url && !request.storagePath)) return Response.json({ error: 'Envie texto, link ou referência de arquivo.' }, { status: 400 })
  const supabase = getSupabase()
  if (!supabase) return Response.json({ status: 'captured', mode: 'local-preview', next: 'Configure Supabase para persistir.' })
  const rawText = request.text?.trim() ?? request.title ?? request.url ?? request.storagePath ?? ''
  const agent = chooseAgent(rawText)
  const { data: item, error: itemError } = await supabase.from('ingestion_items').insert({
    source_kind: request.sourceKind,
    external_id: request.externalId,
    source_url: request.url,
    storage_path: request.storagePath,
    media_type: request.mediaType,
    raw_payload: { title: request.title, metadata: request.metadata ?? {} },
    extracted_text: request.text,
    normalized_text: rawText,
    status: request.text ? 'organized' : 'captured',
  }).select('id').single()
  if (itemError) return Response.json({ error: itemError.message }, { status: 500 })

  let nodeId: string | undefined
  if (request.text) {
    const kind = detectKind(rawText)
    const title = request.title || rawText.slice(0, 110)
    const key = canonicalKey(kind, title)
    const { data: existing } = await supabase.from('brain_nodes').select('id').eq('canonical_key', key).maybeSingle()
    const embedding = await createEmbedding(rawText)
    const { data: node, error: nodeError } = existing
      ? { data: existing, error: null }
      : await supabase.from('brain_nodes').insert({
        kind, title, content: rawText, canonical_key: key, embedding,
        agent_slug: agent.id, source_type: request.sourceKind, source_url: request.url, metadata: { ingestion_item_id: item.id, ...request.metadata },
      }).select('id').single()
    if (nodeError) return Response.json({ error: nodeError.message }, { status: 500 })
    nodeId = node.id
    await supabase.from('memory_claims').insert({ ingestion_item_id: item.id, node_id: nodeId, statement: rawText, confidence: existing ? 0.95 : 0.65, metadata: { extracted_automatically: true, duplicate_avoided: Boolean(existing) } })
    if (!existing && embedding) {
      const { data: similar } = await supabase.rpc('match_brain_nodes', { query_embedding: embedding, match_count: 6, filter_kind: null })
      const links = (similar ?? []).filter((candidate: { id: string; similarity: number }) => candidate.id !== nodeId && candidate.similarity >= 0.86)
        .map((candidate: { id: string; similarity: number }) => ({ from_node_id: nodeId, to_node_id: candidate.id, relation_type: 'references', weight: candidate.similarity, metadata: { automatic: true, method: 'semantic_similarity' } }))
      if (links.length) await supabase.from('node_relations').upsert(links, { onConflict: 'from_node_id,to_node_id,relation_type' })
    }
  }
  await logEvent(supabase, { eventType: 'captured_and_organized', actorType: 'system', entityType: 'ingestion_item', entityId: item.id, data: { sourceKind: request.sourceKind, nodeId, assignedAgent: agent.id } })
  if (nodeId) await logEvent(supabase, { eventType: 'memory_updated', actorType: 'system', entityType: 'brain_node', entityId: nodeId, data: { sourceKind: request.sourceKind, assignedAgent: agent.id } })
  return Response.json({ ingestionId: item.id, nodeId, assignedAgent: agent.id, status: request.text ? 'organized' : 'captured' }, { status: 201 })
}

export const config: Config = { path: '/api/ingest' }
