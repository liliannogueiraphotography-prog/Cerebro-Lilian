-- Cérebro Lilian: a fonte única de memória para todos os agentes.
create extension if not exists pgcrypto with schema extensions;
create extension if not exists vector with schema extensions;

create type public.brain_node_kind as enum ('project', 'decision', 'task', 'source', 'note', 'person', 'event');
create type public.brain_status as enum ('active', 'open', 'blocked', 'done', 'archived', 'waiting_approval');
create type public.relation_kind as enum ('belongs_to', 'depends_on', 'informs', 'decided_by', 'blocks', 'references', 'assigned_to', 'supersedes');
create type public.run_status as enum ('ready', 'running', 'completed', 'failed', 'waiting_approval');
create type public.ingestion_status as enum ('captured', 'understanding', 'organized', 'related', 'ready', 'failed', 'needs_review');
create type public.action_status as enum ('planned', 'waiting_approval', 'running', 'completed', 'failed', 'skipped');

create table public.workspaces (
  id uuid primary key default extensions.gen_random_uuid(),
  slug text unique not null,
  name text not null,
  created_at timestamptz not null default now()
);

insert into public.workspaces (slug, name) values ('lilian', 'Cérebro Lilian') on conflict (slug) do nothing;

create or replace function public.lilian_workspace_id()
returns uuid language sql stable security invoker set search_path = '' as $$
  select id from public.workspaces where slug = 'lilian' limit 1;
$$;

create table public.agents (
  slug text primary key,
  name text not null,
  description text not null,
  color text not null,
  capabilities text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.agents (slug, name, description, color, capabilities) values
  ('luma', 'Luma', 'Produtos, fornecedores, Shopify e margem.', '#8fb8e8', array['produtos','fornecedores','shopify','margem']),
  ('belem', 'Belém', 'Natal, agenda, cenário e reservas.', '#e2b36f', array['natal','agenda','cenário','reservas']),
  ('metamorfose', 'Metamorfose', 'Comunidade, aulas, jornada e app.', '#b98fc7', array['comunidade','aulas','jornada','app']),
  ('conteudo', 'Conteúdo', 'Instagram, roteiros, Reels e marca pessoal.', '#ed8e82', array['instagram','roteiros','reels','marca']),
  ('financeiro', 'Financeiro', 'Caixa, contratos, metas e decisões de dinheiro.', '#88c7a1', array['caixa','contratos','metas','dinheiro'])
on conflict (slug) do update set name = excluded.name, description = excluded.description, color = excluded.color, capabilities = excluded.capabilities;

create table public.brain_nodes (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade default public.lilian_workspace_id(),
  kind public.brain_node_kind not null,
  title text not null,
  content text not null default '',
  status public.brain_status not null default 'active',
  agent_slug text references public.agents(slug) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  source_url text,
  source_type text,
  source_at timestamptz,
  due_at timestamptz,
  embedding extensions.vector(1536),
  search_vector tsvector generated always as (to_tsvector('portuguese', coalesce(title, '') || ' ' || coalesce(content, ''))) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index brain_nodes_workspace_kind_idx on public.brain_nodes (workspace_id, kind, status);
create index brain_nodes_search_idx on public.brain_nodes using gin (search_vector);
create index brain_nodes_embedding_hnsw_idx on public.brain_nodes using hnsw (embedding vector_cosine_ops) where embedding is not null;

create table public.node_relations (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade default public.lilian_workspace_id(),
  from_node_id uuid not null references public.brain_nodes(id) on delete cascade,
  to_node_id uuid not null references public.brain_nodes(id) on delete cascade,
  relation_type public.relation_kind not null,
  weight real not null default 1 check (weight > 0 and weight <= 1),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (from_node_id, to_node_id, relation_type),
  check (from_node_id <> to_node_id)
);

create index node_relations_from_idx on public.node_relations (from_node_id);
create index node_relations_to_idx on public.node_relations (to_node_id);

create table public.agent_runs (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade default public.lilian_workspace_id(),
  agent_slug text not null references public.agents(slug),
  status public.run_status not null default 'ready',
  input jsonb not null default '{}'::jsonb,
  output jsonb,
  context_node_ids uuid[] not null default '{}',
  policy_snapshot jsonb not null default '{}'::jsonb,
  approval_required boolean not null default false,
  approval_note text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create index agent_runs_agent_status_idx on public.agent_runs (agent_slug, status, created_at desc);

-- CAPTURAR: every incoming piece is preserved before any model interprets it.
-- `raw_payload` is for small textual payloads and metadata. Files live in private Storage;
-- `storage_path` identifies them without copying binaries into Postgres.
create table public.ingestion_items (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade default public.lilian_workspace_id(),
  source_kind text not null check (source_kind in ('text', 'link', 'pdf', 'image', 'audio', 'video', 'instagram_saved', 'gmail', 'google_drive', 'shopify', 'browser_use')),
  external_id text,
  source_url text,
  storage_path text,
  media_type text,
  raw_payload jsonb not null default '{}'::jsonb,
  extracted_text text,
  normalized_text text,
  content_hash text,
  status public.ingestion_status not null default 'captured',
  error_message text,
  captured_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  unique nulls not distinct (workspace_id, source_kind, external_id)
);
create index ingestion_items_status_idx on public.ingestion_items (status, captured_at);
create index ingestion_items_hash_idx on public.ingestion_items (content_hash) where content_hash is not null;

-- ENTENDER e ORGANIZAR: a claim is a fact extracted from a source. It can be
-- corrected later without destroying the original source or the audit trail.
create table public.memory_claims (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade default public.lilian_workspace_id(),
  ingestion_item_id uuid references public.ingestion_items(id) on delete set null,
  node_id uuid references public.brain_nodes(id) on delete set null,
  statement text not null,
  claim_type text not null default 'fact',
  confidence real not null default 0.5 check (confidence >= 0 and confidence <= 1),
  is_current boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  superseded_at timestamptz
);
create index memory_claims_node_idx on public.memory_claims (node_id, is_current);

-- AGIR: authorization is its own record. A run is never treated as permission.
create table public.agent_authorizations (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade default public.lilian_workspace_id(),
  agent_slug text references public.agents(slug) on delete set null,
  scope jsonb not null,
  granted_by text not null default 'lilian',
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  note text
);
create index agent_authorizations_active_idx on public.agent_authorizations (agent_slug, expires_at) where revoked_at is null;

create table public.agent_actions (
  id uuid primary key default extensions.gen_random_uuid(),
  run_id uuid not null references public.agent_runs(id) on delete cascade,
  authorization_id uuid references public.agent_authorizations(id) on delete set null,
  action_type text not null,
  target_type text,
  target_id text,
  request jsonb not null default '{}'::jsonb,
  response jsonb,
  status public.action_status not null default 'planned',
  idempotency_key text unique,
  error_message text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);
create index agent_actions_run_idx on public.agent_actions (run_id, created_at);

-- Immutable-looking timeline for audit. Corrections are new events, never silent edits.
create table public.brain_events (
  id bigint generated always as identity primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade default public.lilian_workspace_id(),
  event_type text not null,
  actor_type text not null check (actor_type in ('lilian', 'harness', 'agent', 'system', 'connector')),
  actor_id text,
  entity_type text not null,
  entity_id uuid,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index brain_events_entity_idx on public.brain_events (entity_type, entity_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin new.updated_at = now(); return new; end;
$$;
create trigger brain_nodes_updated_at before update on public.brain_nodes for each row execute function public.set_updated_at();

-- Semantic retrieval, restricted to the service role by default.
create or replace function public.match_brain_nodes(
  query_embedding extensions.vector(1536),
  match_count integer default 10,
  filter_kind public.brain_node_kind default null
)
returns table (id uuid, title text, content text, kind public.brain_node_kind, status public.brain_status, agent_slug text, similarity real, updated_at timestamptz)
language sql stable security invoker set search_path = '' as $$
  select n.id, n.title, n.content, n.kind, n.status, n.agent_slug,
         (1 - (n.embedding <=> query_embedding))::real as similarity, n.updated_at
  from public.brain_nodes n
  where n.embedding is not null
    and (filter_kind is null or n.kind = filter_kind)
  order by n.embedding <=> query_embedding
  limit least(greatest(match_count, 1), 50);
$$;

-- RECUPERAR: brings back both the selected memories and their closest relations.
create or replace function public.get_related_brain_nodes(seed_node_ids uuid[], relation_limit integer default 30)
returns table (from_node_id uuid, to_node_id uuid, relation_type public.relation_kind, weight real, related_title text, related_kind public.brain_node_kind)
language sql stable security invoker set search_path = '' as $$
  select r.from_node_id, r.to_node_id, r.relation_type, r.weight,
         n.title as related_title, n.kind as related_kind
  from public.node_relations r
  join public.brain_nodes n on n.id = case when r.from_node_id = any(seed_node_ids) then r.to_node_id else r.from_node_id end
  where r.from_node_id = any(seed_node_ids) or r.to_node_id = any(seed_node_ids)
  order by r.weight desc, n.updated_at desc
  limit least(greatest(relation_limit, 1), 100);
$$;

-- No browser role can read the memory directly. Netlify functions use the server-only service key.
alter table public.workspaces enable row level security;
alter table public.agents enable row level security;
alter table public.brain_nodes enable row level security;
alter table public.node_relations enable row level security;
alter table public.agent_runs enable row level security;
alter table public.ingestion_items enable row level security;
alter table public.memory_claims enable row level security;
alter table public.agent_authorizations enable row level security;
alter table public.agent_actions enable row level security;
alter table public.brain_events enable row level security;
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on function public.match_brain_nodes(extensions.vector, integer, public.brain_node_kind) from public, anon, authenticated;
revoke execute on function public.get_related_brain_nodes(uuid[], integer) from public, anon, authenticated;

insert into public.brain_nodes (kind, title, content, status, agent_slug, metadata) values
  ('decision', 'Memória antes de agir', 'Todo agente consulta a memória compartilhada antes de executar uma tarefa.', 'active', null, '{"policy": true}'),
  ('decision', 'Ações sensíveis pedem aprovação', 'Não comprar, pagar, enviar mensagens a clientes, publicar ou fazer alterações irreversíveis sem aprovação da Lilian.', 'active', null, '{"policy": true}'),
  ('project', 'Projeto Belém 2026', 'Experiência de Natal com cenário, reservas, agenda e primeiro lote.', 'active', 'belem', '{"area": "fotografia"}'),
  ('project', 'Luma Shopping', 'Curadoria de produtos virais nos EUA, fornecedores e operação Shopify.', 'active', 'luma', '{"area": "ecommerce"}'),
  ('project', 'Metamorfose', 'Comunidade e jornada para mulheres que conhecem a promessa e se perderam no caminho.', 'active', 'metamorfose', '{"area": "comunidade"}');
