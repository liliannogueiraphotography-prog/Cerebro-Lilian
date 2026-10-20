import type { Config } from '@netlify/functions'
import { canExecute, classifyActionRisk } from '../../src/lib/policy'
import { getSupabase } from './_shared'
import { logEvent, retrieveMemory } from './_memory'

type LumaRequest = { objective: string; execution?: boolean; authorizationId?: string }

export default async (req: Request) => {
  if (req.method !== 'POST') return Response.json({ error: 'Use POST.' }, { status: 405 })
  const request = await req.json() as LumaRequest
  if (!request.objective?.trim()) return Response.json({ error: 'Descreva o objetivo da Luma.' }, { status: 400 })
  const supabase = getSupabase()
  const risk = classifyActionRisk(request.objective)
  const execute = Boolean(request.execution && canExecute(request.objective, request.authorizationId))
  if (!supabase) return Response.json({ agent: 'luma', state: execute ? 'ready' : 'waiting_approval', mode: 'local-preview', message: 'A rota foi validada; falta conectar o banco.' })

  const context = await retrieveMemory(supabase, `${request.objective} Luma produtos fornecedor Shopify margem`, 12)
  const { data: run, error: runError } = await supabase.from('agent_runs').insert({
    agent_slug: 'luma', status: execute ? 'running' : 'waiting_approval', input: request,
    context_node_ids: context.map((memory) => memory.id), approval_required: risk === 'approval_required',
    policy_snapshot: { risk, execution_requested: Boolean(request.execution), execution_allowed: execute },
    started_at: execute ? new Date().toISOString() : null,
  }).select('id').single()
  if (runError) return Response.json({ error: runError.message }, { status: 500 })
  const { data: action } = await supabase.from('agent_actions').insert({
    run_id: run.id, authorization_id: request.authorizationId, action_type: 'luma_analysis', target_type: 'luma_catalog',
    request: { objective: request.objective }, status: execute ? 'running' : 'waiting_approval', idempotency_key: `luma:${run.id}`,
  }).select('id').single()

  // First validated flow intentionally performs only analysis. Publishing to Shopify
  // is a future connector action and must have a distinct explicit authorization.
  const result = { summary: 'Contexto Luma recuperado e análise preparada.', relatedMemories: context.map(({ id, title, kind }) => ({ id, title, kind })), externalAction: 'none' }
  if (execute) {
    await supabase.from('agent_actions').update({ status: 'completed', response: result, completed_at: new Date().toISOString() }).eq('id', action?.id)
    await supabase.from('agent_runs').update({ status: 'completed', output: result, completed_at: new Date().toISOString() }).eq('id', run.id)
    const { data: resultNode } = await supabase.from('brain_nodes').insert({ kind: 'note', title: `Luma: ${request.objective.slice(0, 92)}`, content: result.summary, status: 'done', agent_slug: 'luma', metadata: { run_id: run.id, context_node_ids: context.map((memory) => memory.id), audit: true } }).select('id').single()
    await logEvent(supabase, { eventType: 'luma_run_completed', actorType: 'agent', actorId: 'luma', entityType: 'agent_run', entityId: run.id, data: { actionId: action?.id, resultNodeId: resultNode?.id, contextCount: context.length } })
    return Response.json({ runId: run.id, actionId: action?.id, state: 'completed', result })
  }
  await logEvent(supabase, { eventType: 'luma_run_waiting_approval', actorType: 'agent', actorId: 'luma', entityType: 'agent_run', entityId: run.id, data: { risk, contextCount: context.length } })
  return Response.json({ runId: run.id, actionId: action?.id, state: 'waiting_approval', contextCount: context.length, reason: 'A execução solicitada ainda não tem autorização específica.' }, { status: 202 })
}

export const config: Config = { path: '/api/luma-run' }
