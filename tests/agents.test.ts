import { describe, expect, it } from 'vitest'
import { chooseAgent, requiresApproval } from '../src/lib/agents'
import { canExecute, classifyActionRisk } from '../src/lib/policy'

describe('harness', () => {
  it('encaminha tarefas da Luma', () => expect(chooseAgent('revisar a margem e o frete dos produtos da Shopify').id).toBe('luma'))
  it('encaminha tarefas de Natal para Belém', () => expect(chooseAgent('abrir novas reservas de Natal').id).toBe('belem'))
  it('protege ações que precisam da Lilian', () => expect(requiresApproval('enviar mensagem para cliente confirmando pagamento')).toBe(true))
  it('não segura uma análise comum', () => expect(requiresApproval('analisar tarefas pendentes da comunidade')).toBe(false))
  it('exige registro de autorização para pagar', () => {
    expect(classifyActionRisk('pagar o fornecedor')).toBe('approval_required')
    expect(canExecute('pagar o fornecedor')).toBe(false)
    expect(canExecute('pagar o fornecedor', 'autorizacao-registrada')).toBe(true)
  })
})
