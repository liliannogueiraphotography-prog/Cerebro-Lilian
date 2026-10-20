export type AgentId = 'luma' | 'belem' | 'metamorfose' | 'conteudo' | 'financeiro'

export type AgentDefinition = {
  id: AgentId
  name: string
  color: string
  description: string
  keywords: string[]
}

export const agents: AgentDefinition[] = [
  { id: 'luma', name: 'Luma', color: '#8fb8e8', description: 'Produtos, fornecedores, Shopify e margem.', keywords: ['luma', 'shopify', 'produto', 'fornecedor', 'cj', 'wiio', 'frete', 'margem'] },
  { id: 'belem', name: 'Belém', color: '#e2b36f', description: 'Natal, agenda, cenário e reservas.', keywords: ['belém', 'belem', 'natal', 'ensaio', 'reserva', 'cenário', 'cenário', 'família'] },
  { id: 'metamorfose', name: 'Metamorfose', color: '#b98fc7', description: 'Comunidade, aulas, jornada e app.', keywords: ['metamorfose', 'comunidade', 'casulo', 'borboleta', 'propósito', 'aula'] },
  { id: 'conteudo', name: 'Conteúdo', color: '#ed8e82', description: 'Instagram, roteiros, Reels e marca pessoal.', keywords: ['conteúdo', 'conteudo', 'instagram', 'reels', 'legenda', 'roteiro', 'viral'] },
  { id: 'financeiro', name: 'Financeiro', color: '#88c7a1', description: 'Caixa, contratos, metas e decisões de dinheiro.', keywords: ['financeiro', 'finança', 'dinheiro', 'contrato', 'pagamento', 'preço', 'preco', 'caixa'] },
]

export function chooseAgent(task: string): AgentDefinition {
  const text = task.toLocaleLowerCase('pt-BR')
  const scored = agents.map((agent) => ({
    agent,
    score: agent.keywords.reduce((score, keyword) => score + (text.includes(keyword) ? 1 : 0), 0),
  }))
  return scored.sort((a, b) => b.score - a.score)[0]?.agent ?? agents[3]
}

export function requiresApproval(task: string): boolean {
  return /\b(comprar|pagamento|pagar|enviar|mensagem para cliente|publicar|deletar|excluir|cancelar)\b/i.test(task)
}
