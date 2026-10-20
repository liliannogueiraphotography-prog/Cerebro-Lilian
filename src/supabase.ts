import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined

export const supabase = url && key ? createClient(url, key, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
}) : null

export const authEmail = 'lilian.nogueira@live.com'

export async function cerebroRequest<T>(body: Record<string, unknown>): Promise<T> {
  if (!supabase) throw new Error('A conexão segura do Cérebro ainda não está configurada.')
  const { data, error } = await supabase.functions.invoke('cerebro-sync', { body })
  if (error) throw error
  if (data?.error) throw new Error(String(data.error))
  return data as T
}
