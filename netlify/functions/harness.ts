import type { Config } from '@netlify/functions'
import { chooseAgent } from '../../src/lib/agents'
import { classifyActionRisk } from '../../src/lib/policy'
import { getSupabase } from './_shared'
import { logEvent, retrieveMemory } from './_memory'

export default async (req: Request) => {
  if (req.method !== 'POST') return Response.json({ error: 'Use POST.' }, { status: 405 })
  const { task } = await req.json() as { task?: string }
  if (!task?.trim()) return Response.json({ error: 'Descreva a tarefa.' }, { status: 400 })
  const agent = chooseAgent(task)
  const approvalRequired = classifyActionRisk(task) === 'approval_required'
  const supabase = getSupabase()
  let context: unknown[] = []
  try {
    if (supabase) {
      context = await retrieveMemory(supabase, task, 8)
      const { data: run } = await supabase.from('agent_runs').insert({
        agent_slug: agent.id, status: approvalRequired ? 'waiting_approval' : 'ready', input: { task },
        context_node_ids: context.map((item: any) => item.id), approval_required: approvalRequired,
        policy_snapshot: { risk: approvalRequired ? 'approval_required' : 'safe', flow: ['capture', 'understand', 'organize', 'relate', 'retrieve', 'act'] },
      }).select('id').single()
      if (run) await logEvent(supabase, { eventType: 'task_routed', actorType: 'harness', actorId: 'harness', entityType: 'agent_run', entityId: run.id, data: { agent: agent.id, contextCount: context.length, approvalRequired } })
    }
  } catch { /* Routing remains available even when retrieval is temporarily unavailable. */ }
  return Response.json({ route: { agent: agent.name, agentId: agent.id, approvalRequired, contextCount: context.length, state: approvalRequired ? 'waiting_approval' : 'ready' } })
}

export const config: Config = { path: '/api/harness' }
