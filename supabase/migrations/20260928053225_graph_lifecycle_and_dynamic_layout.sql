-- The graph is derived from memory. No application-owned list of nodes exists.
create type public.project_lifecycle as enum ('permanente', 'sazonal', 'temporario', 'arquivado');
alter type public.brain_node_kind add value if not exists 'product';
alter type public.brain_node_kind add value if not exists 'content';
alter type public.brain_node_kind add value if not exists 'file';
alter type public.brain_node_kind add value if not exists 'topic';
alter type public.brain_node_kind add value if not exists 'customer';

alter table public.brain_nodes
  add column lifecycle public.project_lifecycle,
  add column parent_node_id uuid references public.brain_nodes(id) on delete set null,
  add column is_core boolean not null default false,
  add column canonical_key text;

create index brain_nodes_parent_idx on public.brain_nodes (parent_node_id);
create unique index brain_nodes_workspace_canonical_key_idx
  on public.brain_nodes (workspace_id, canonical_key)
  where canonical_key is not null;

create type public.memory_entity_kind as enum ('person', 'organization', 'brand', 'product', 'topic', 'place', 'customer', 'document');
create table public.memory_entities (
  id uuid primary key default extensions.gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade default public.lilian_workspace_id(),
  entity_type public.memory_entity_kind not null,
  name text not null,
  normalized_name text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, entity_type, normalized_name)
);
create table public.node_entity_mentions (
  node_id uuid not null references public.brain_nodes(id) on delete cascade,
  entity_id uuid not null references public.memory_entities(id) on delete cascade,
  confidence real not null check (confidence between 0 and 1),
  evidence text,
  created_at timestamptz not null default now(),
  primary key (node_id, entity_id)
);
alter table public.memory_entities enable row level security;
alter table public.node_entity_mentions enable row level security;
revoke all on public.memory_entities, public.node_entity_mentions from anon, authenticated;

-- The permanent areas are database records, not UI assumptions.
insert into public.brain_nodes (kind, title, content, lifecycle, is_core, canonical_key, status, metadata) values
  ('project', 'Lilian Cristina', 'Marca pessoal, posicionamento, Instagram, conteúdo, Reels, palestras, livro, podcast e projetos autorais.', 'permanente', true, 'core:lilian-cristina', 'active', '{"graph_role":"core"}'),
  ('project', 'Fotografia / Estúdio', 'Clientes, ensaios, contratos, agenda, pacotes, entregas, presets, cenários, equipamentos, campanhas e operação do estúdio.', 'permanente', true, 'core:fotografia-estudio', 'active', '{"graph_role":"core"}'),
  ('project', 'Metamorfose', 'Comunidade, método, aulas, produtos, eventos, conteúdo, membros, app e projetos derivados.', 'permanente', true, 'core:metamorfose', 'active', '{"graph_role":"core"}'),
  ('project', 'Luma', 'Produtos, fornecedores, Shopify, CJ, preços, margens, frete, aprovações, estoque e operação.', 'permanente', true, 'core:luma', 'active', '{"graph_role":"core"}'),
  ('project', 'Financeiro', 'Financeiro pessoal e dos negócios, recebimentos, despesas, contratos, dívidas, metas, investimentos e fluxo de caixa.', 'permanente', true, 'core:financeiro', 'active', '{"graph_role":"core"}'),
  ('project', 'Vida Pessoal', 'Família, filhos, casamento, casa, rotina, compromissos, viagens, compras e objetivos pessoais.', 'permanente', true, 'core:vida-pessoal', 'active', '{"graph_role":"core"}')
on conflict (workspace_id, canonical_key) where canonical_key is not null do update
  set title = excluded.title, content = excluded.content, lifecycle = excluded.lifecycle, is_core = true, metadata = excluded.metadata;

-- Preserve prior seed data while moving it into the correct permanent area.
update public.brain_nodes
set title = 'Luma', lifecycle = 'permanente', is_core = true, canonical_key = 'core:luma'
where lower(title) = 'luma shopping' and not exists (
  select 1 from public.brain_nodes n2 where n2.canonical_key = 'core:luma' and n2.id <> brain_nodes.id
);

update public.brain_nodes
set lifecycle = 'permanente', is_core = true, canonical_key = 'core:metamorfose'
where lower(title) = 'metamorfose' and not exists (
  select 1 from public.brain_nodes n2 where n2.canonical_key = 'core:metamorfose' and n2.id <> brain_nodes.id
);

create or replace function public.core_node_id(core_key text, workspace uuid)
returns uuid language sql stable security invoker set search_path = '' as $$
  select id from public.brain_nodes
  where workspace_id = workspace and canonical_key = 'core:' || core_key
  limit 1;
$$;

-- Automatic classification works from known agent ownership and the memory text.
create or replace function public.infer_core_key(node_kind public.brain_node_kind, agent text, node_title text, node_content text)
returns text language plpgsql immutable set search_path = '' as $$
declare text_to_classify text := lower(coalesce(node_title, '') || ' ' || coalesce(node_content, ''));
begin
  if agent = 'luma' or text_to_classify ~ '(shopify|fornecedor|produto|margem|frete|cj|estoque)' then return 'luma'; end if;
  if agent = 'metamorfose' or text_to_classify ~ '(metamorfose|comunidade|casulo|borboleta|propósito)' then return 'metamorfose'; end if;
  if agent = 'conteudo' or text_to_classify ~ '(instagram|reels|podcast|palestra|livro|marca pessoal|lilian cristina)' then return 'lilian-cristina'; end if;
  if agent = 'financeiro' or text_to_classify ~ '(financeir|pagamento|recebimento|dívida|investimento|fluxo de caixa|contrato)' then return 'financeiro'; end if;
  if text_to_classify ~ '(belém|belem|natal|ensaio|gestante|newborn|fotografia|estúdio|estudio|cliente|preset)' then return 'fotografia-estudio'; end if;
  if text_to_classify ~ '(família|familia|filho|casamento|casa|viagem|rotina|compra pessoal)' then return 'vida-pessoal'; end if;
  return null;
end;
$$;

create or replace function public.maintain_brain_node_structure()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare inferred_core text;
begin
  if new.canonical_key is null then
    new.canonical_key := lower(new.kind::text || ':' || regexp_replace(trim(new.title), '[^[:alnum:]]+', '-', 'g'));
  end if;
  if new.is_core then
    new.lifecycle := 'permanente';
    new.parent_node_id := null;
  elsif new.parent_node_id is null then
    inferred_core := public.infer_core_key(new.kind, new.agent_slug, new.title, new.content);
    if inferred_core is not null then new.parent_node_id := public.core_node_id(inferred_core, new.workspace_id); end if;
  end if;
  if new.lifecycle is null and new.kind = 'project' then new.lifecycle := 'temporario'; end if;
  return new;
end;
$$;

create trigger brain_nodes_maintain_structure
before insert or update of title, content, agent_slug, lifecycle, parent_node_id, is_core, canonical_key
on public.brain_nodes for each row execute function public.maintain_brain_node_structure();

-- Hierarchy is materialized as a relation too, so both tree and graph reads stay consistent.
create or replace function public.sync_parent_relation()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and old.parent_node_id is distinct from new.parent_node_id then
    delete from public.node_relations where from_node_id = new.id and relation_type = 'belongs_to';
  end if;
  if new.parent_node_id is not null then
    insert into public.node_relations (workspace_id, from_node_id, to_node_id, relation_type, weight, metadata)
    values (new.workspace_id, new.id, new.parent_node_id, 'belongs_to', 1, '{"automatic":true}')
    on conflict (from_node_id, to_node_id, relation_type) do update set weight = excluded.weight, metadata = excluded.metadata;
  end if;
  return new;
end;
$$;
create trigger brain_nodes_sync_parent_relation
after insert or update of parent_node_id on public.brain_nodes
for each row execute function public.sync_parent_relation();

insert into public.brain_nodes (kind, title, content, lifecycle, parent_node_id, canonical_key, status, metadata)
select 'project', 'Campanhas', 'Campanhas e projetos sazonais do estúdio, incluindo Natal, lançamentos e ações especiais.', 'permanente', public.core_node_id('fotografia-estudio', w.id), 'area:campanhas-fotografia', 'active', '{"structural_area":true}'
from public.workspaces w where w.slug = 'lilian'
on conflict (workspace_id, canonical_key) where canonical_key is not null do update
  set parent_node_id = excluded.parent_node_id, lifecycle = 'permanente', metadata = excluded.metadata;

update public.brain_nodes b
set title = 'Belém 2026', lifecycle = 'temporario', is_core = false,
    canonical_key = 'project:belem-2026', parent_node_id = (select id from public.brain_nodes p where p.workspace_id = b.workspace_id and p.canonical_key = 'area:campanhas-fotografia')
where lower(b.title) in ('projeto belém 2026', 'belém 2026') and b.canonical_key is null;

-- Belém is a temporary campaign under Estúdio, never a permanent core.
insert into public.brain_nodes (kind, title, content, lifecycle, parent_node_id, canonical_key, status, agent_slug, metadata)
select 'project', 'Belém 2026', 'Campanha temporária de Natal: cenário, lotes, clientes, agenda, kits, vídeos, fornecedores, pagamentos, reservas, preços, tarefas e decisões.', 'temporario', c.id, 'project:belem-2026', 'active', 'belem', '{"area":"Fotografia / Estúdio","campaign":true}'
from public.workspaces w
join public.brain_nodes c on c.workspace_id = w.id and c.canonical_key = 'area:campanhas-fotografia'
where w.slug = 'lilian'
on conflict (workspace_id, canonical_key) where canonical_key is not null do update
  set lifecycle = 'temporario', parent_node_id = excluded.parent_node_id, is_core = false, metadata = excluded.metadata;

-- Older seed records remain auditably searchable without competing with the current core.
update public.brain_nodes b set lifecycle = 'arquivado', status = 'archived', is_core = false,
  parent_node_id = public.core_node_id('luma', b.workspace_id), canonical_key = 'legacy:luma-shopping'
where lower(b.title) = 'luma shopping' and b.canonical_key is null;
update public.brain_nodes b set lifecycle = 'arquivado', status = 'archived', is_core = false,
  parent_node_id = public.core_node_id('metamorfose', b.workspace_id), canonical_key = 'legacy:metamorfose-seed'
where lower(b.title) = 'metamorfose' and b.canonical_key is null;

insert into public.node_relations (workspace_id, from_node_id, to_node_id, relation_type, weight, metadata)
select b.workspace_id, b.id, f.id, 'belongs_to', 1, '{"automatic":true}'
from public.brain_nodes b
join public.brain_nodes f on f.workspace_id = b.workspace_id and f.canonical_key = 'area:campanhas-fotografia'
where b.canonical_key = 'project:belem-2026'
on conflict (from_node_id, to_node_id, relation_type) do update set weight = excluded.weight, metadata = excluded.metadata;

-- Dynamic graph: hierarchy, relation count, usage and recency determine prominence.
create or replace function public.get_brain_graph(max_nodes integer default 250, include_archived boolean default false)
returns jsonb language sql stable security invoker set search_path = '' as $$
with relation_degree as (
  select node_id, count(*)::integer as degree
  from (select from_node_id as node_id from public.node_relations union all select to_node_id from public.node_relations) r
  group by node_id
), event_frequency as (
  select entity_id as node_id, count(*)::integer as events, max(created_at) as last_event_at
  from public.brain_events where entity_type = 'brain_node' and entity_id is not null group by entity_id
), weighted as (
  select n.id, n.title, n.kind::text as kind, n.status::text as status, n.lifecycle::text as lifecycle, n.parent_node_id, n.is_core, n.agent_slug,
    coalesce(rd.degree, 0) as degree, coalesce(ef.events, 0) as frequency,
    greatest(n.updated_at, coalesce(ef.last_event_at, n.updated_at)) as last_activity,
    (
      case when n.is_core then 110 when n.lifecycle = 'permanente' then 76 when n.lifecycle = 'sazonal' then 48 when n.lifecycle = 'temporario' then 32 when n.lifecycle = 'arquivado' then 5 else 19 end
      + least(coalesce(rd.degree, 0) * 5, 38)
      + least(coalesce(ef.events, 0) * 3, 24)
      + greatest(0, 25 - floor(extract(epoch from now() - greatest(n.updated_at, coalesce(ef.last_event_at, n.updated_at))) / 86400))
    )::real as relevance
  from public.brain_nodes n
  left join relation_degree rd on rd.node_id = n.id
  left join event_frequency ef on ef.node_id = n.id
  where include_archived or (n.status <> 'archived' and coalesce(n.lifecycle::text, '') <> 'arquivado')
), chosen as (
  select *, row_number() over (order by is_core desc, relevance desc, last_activity desc) as graph_rank
  from weighted limit least(greatest(max_nodes, 10), 500)
), graph_edges as (
  select r.id, r.from_node_id, r.to_node_id, r.relation_type::text as relation_type, r.weight
  from public.node_relations r join chosen a on a.id = r.from_node_id join chosen b on b.id = r.to_node_id
)
select jsonb_build_object(
  'nodes', coalesce((select jsonb_agg(jsonb_build_object(
    'id', id, 'title', title, 'kind', kind, 'status', status, 'lifecycle', lifecycle, 'parent_node_id', parent_node_id,
    'is_core', is_core, 'agent_slug', agent_slug, 'degree', degree, 'frequency', frequency, 'last_activity', last_activity,
    'relevance', relevance, 'visual_size', least(70, greatest(10, round(8 + sqrt(relevance) * 5)))
  ) order by graph_rank) from chosen), '[]'::jsonb),
  'relations', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'from_node_id', from_node_id, 'to_node_id', to_node_id, 'relation_type', relation_type, 'weight', weight)) from graph_edges), '[]'::jsonb)
);
$$;

revoke execute on function public.get_brain_graph(integer, boolean) from public, anon, authenticated;
