import type { AgentId } from './agents'

export type BrainNode = { id: string; title: string; kind: 'project' | 'decision' | 'task' | 'source'; agent?: AgentId; status: string; updatedAt: string; excerpt: string }

export const fallbackNodes: BrainNode[] = [
  { id: '1', title: 'Projeto Belém 2026', kind: 'project', agent: 'belem', status: 'ativo', updatedAt: 'hoje', excerpt: 'Experiência de Natal com primeiro lote e agenda limitada.' },
  { id: '2', title: 'Luma Shopping', kind: 'project', agent: 'luma', status: 'ativo', updatedAt: 'hoje', excerpt: 'Curadoria de produtos virais nos EUA e operação Shopify.' },
  { id: '3', title: 'Metamorfose', kind: 'project', agent: 'metamorfose', status: 'ativo', updatedAt: 'ontem', excerpt: 'Comunidade para mulheres que se perderam no caminho até a promessa.' },
  { id: '4', title: 'Memória antes de agir', kind: 'decision', status: 'aprovado', updatedAt: 'hoje', excerpt: 'Todo agente consulta a memória compartilhada antes de executar uma tarefa.' },
  { id: '5', title: 'Sem ações irreversíveis', kind: 'decision', status: 'aprovado', updatedAt: 'hoje', excerpt: 'Compras, pagamentos, mensagens a clientes e alterações irreversíveis pedem aprovação.' },
]
