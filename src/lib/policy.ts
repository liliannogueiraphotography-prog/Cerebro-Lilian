export type ActionRisk = 'safe' | 'approval_required'

const sensitivePatterns = [
  /\b(comprar|compra|pagar|pagamento|transferir|pix|cart[aã]o)\b/i,
  /\b(enviar|responder|mandar).{0,35}\b(cliente|fornecedor|pessoa)\b/i,
  /\b(publicar|postar|excluir|deletar|cancelar|reembolsar)\b/i,
]

export function classifyActionRisk(instruction: string): ActionRisk {
  return sensitivePatterns.some((pattern) => pattern.test(instruction)) ? 'approval_required' : 'safe'
}

export function canExecute(action: string, authorizationId?: string): boolean {
  return classifyActionRisk(action) === 'safe' || Boolean(authorizationId)
}
