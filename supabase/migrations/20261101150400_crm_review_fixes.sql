-- CRM (app móvel) — 5/5: correções da revisão de 2026-11-01.
--
-- Migration nova em vez de editar as quatro anteriores: elas podem já ter
-- sido aplicadas, e migration aplicada não se reescreve (AGENTS.md).
--
-- 1. crm_create_opportunity idempotente também sob concorrência.
--    Antes: duas transações com a mesma chave liam "não existe" ao mesmo
--    tempo; a segunda esperava no índice único e terminava em 23505. Não
--    duplicava nada, mas o segundo envio falhava em vez de devolver o lead.
--    Agora a função toma um advisory lock da chave antes de procurar: a
--    segunda espera a primeira terminar e, em READ COMMITTED (o padrão do
--    PostgREST), o SELECT seguinte já enxerga o que a primeira gravou. Se a
--    primeira desfizer, a segunda cria normalmente.
--
-- 2. crm_list_members devolve menos para quem não tem CRM completo: só
--    id e nome, e só de quem aparece nos registros que a pessoa vê
--    (responsável/SDR de oportunidades, contas e contatos visíveis, autor de
--    atividades visíveis, e autor, responsável e SDR antigos ou novos no
--    histórico das oportunidades visíveis). E-mail, papel e nível de acesso
--    ficam nulos, e nome vazio vira 'Sem nome' (nunca o e-mail). Quem tem CRM completo
--    continua recebendo a lista inteira, porque é quem atribui.
--    A filtragem usa a própria RLS: a função pública é SECURITY INVOKER e
--    só o mapa id → nome passa por uma função SECURITY DEFINER.
--
-- 3. Configuração de etapas pelo app: regras de integridade no banco e um
--    RPC para reordenar de uma vez.

-- ── 1. Novo lead idempotente sob concorrência ───────────────────────────────
create or replace function public.crm_create_opportunity(
  p_request_id      uuid,
  p_title           text,
  p_account_id      uuid        default null,
  p_account_name    text        default null,
  p_contact_name    text        default null,
  p_contact_phone   text        default null,
  p_contact_email   text        default null,
  p_source          text        default null,
  p_stage_id        text        default 'novo',
  p_estimated_value numeric     default null,
  p_next_action     text        default null,
  p_next_action_at  timestamptz default null,
  p_owner_id        uuid        default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id         uuid;
  v_account_id uuid := p_account_id;
  v_contact_id uuid;
  v_owner_id   uuid := coalesce(p_owner_id, auth.uid());
begin
  if p_request_id is null then
    raise exception 'Envio sem chave de idempotência.' using errcode = '22023';
  end if;

  -- Uma chave por vez. O lock é da transação: solta no commit/rollback.
  perform pg_advisory_xact_lock(
    hashtextextended('crm_create_opportunity:' || p_request_id::text, 0)
  );

  select o.id into v_id
  from public.crm_opportunities o
  where o.client_request_id = p_request_id;
  if found then
    return v_id;
  end if;

  begin
    if v_account_id is null and nullif(btrim(p_account_name), '') is not null then
      insert into public.crm_accounts (name, owner_id, client_request_id)
      values (btrim(p_account_name), v_owner_id, p_request_id)
      returning id into v_account_id;
    end if;

    if nullif(btrim(p_contact_name), '') is not null then
      insert into public.crm_contacts (account_id, full_name, phone, email, owner_id, client_request_id)
      values (v_account_id, btrim(p_contact_name), nullif(btrim(p_contact_phone), ''),
              nullif(btrim(p_contact_email), ''), v_owner_id, p_request_id)
      returning id into v_contact_id;
    end if;

    insert into public.crm_opportunities (
      title, account_id, contact_id, stage_id, owner_id, source,
      estimated_value, next_action, next_action_at, client_request_id
    ) values (
      btrim(p_title), v_account_id, v_contact_id, coalesce(p_stage_id, 'novo'), v_owner_id,
      nullif(btrim(p_source), ''), p_estimated_value, nullif(btrim(p_next_action), ''),
      p_next_action_at, p_request_id
    )
    returning id into v_id;
  exception when unique_violation then
    -- Rede de segurança para um INSERT com a mesma chave feito fora desta
    -- função: se a oportunidade já existe e é visível, ela é a resposta.
    select o.id into v_id
    from public.crm_opportunities o
    where o.client_request_id = p_request_id;
    if not found then
      raise;
    end if;
  end;

  return v_id;
end;
$$;

-- create or replace mantém os grants da versão anterior; repetidos aqui para
-- a migration valer sozinha.
revoke execute on function public.crm_create_opportunity(
  uuid, text, uuid, text, text, text, text, text, text, numeric, text, timestamptz, uuid
) from public, anon;
grant execute on function public.crm_create_opportunity(
  uuid, text, uuid, text, text, text, text, text, text, numeric, text, timestamptz, uuid
) to authenticated;

-- ── 2. Membros: menos dados para quem não tem CRM completo ──────────────────

-- Mapa id → dados de exibição. SECURITY DEFINER porque sales_trial e sdr não
-- leem a equipe em profiles. Quem não tem CRM completo só recebe nome, e só
-- dos ids pedidos (a função pública calcula esses ids sob a RLS); sem lista,
-- recebe só o próprio registro.
create or replace function crm_private.member_directory(
  p_ids                    uuid[],
  p_include_without_access boolean
)
returns table (id uuid, full_name text, email text, role text, access_level text, crm_access text)
language sql
stable
security definer
set search_path = ''
as $$
  with caller as (
    select crm_private.access_level() as level,
           crm_private.is_super_admin() as super_admin,
           auth.uid() as uid
  )
  select
    p.id,
    -- Sem CRM completo, o e-mail não pode chegar nem como nome.
    case when c.level = 'full'
         then coalesce(nullif(btrim(p.full_name), ''), p.email, 'Sem nome')
         else coalesce(nullif(btrim(p.full_name), ''), 'Sem nome')
    end,
    case when c.level = 'full' then p.email end,
    case when c.level = 'full' then p.role end,
    case when c.level = 'full' then crm_private.access_level_of(p.id) end,
    case when c.super_admin then p.crm_access end
  from public.profiles p
  cross join caller c
  where c.level <> 'none'
    and p.role <> 'client'
    and (
      c.level = 'full'
      or p.id = c.uid
      or p.id = any (coalesce(p_ids, array[]::uuid[]))
    )
    and (
      crm_private.access_level_of(p.id) <> 'none'
      or (p_include_without_access and c.super_admin)
    )
  order by 2
$$;

revoke execute on function crm_private.member_directory(uuid[], boolean) from public;
grant execute on function crm_private.member_directory(uuid[], boolean) to authenticated, service_role;

-- A assinatura de retorno é a mesma; o corpo passa a SECURITY INVOKER.
create or replace function public.crm_list_members(p_include_without_access boolean default false)
returns table (id uuid, full_name text, email text, role text, access_level text, crm_access text)
language sql
stable
security invoker
set search_path = ''
as $$
  select m.*
  from crm_private.member_directory(
    case
      when crm_private.access_level() = 'full' then null
      else array(
        -- Sob a RLS de quem chama: só entra quem está em algo que a pessoa vê.
        select r.member_id from (
          select o.owner_id   as member_id from public.crm_opportunities o
          union select o.sdr_id            from public.crm_opportunities o
          union select a.owner_id          from public.crm_accounts a
          union select c.owner_id          from public.crm_contacts c
          union select t.created_by        from public.crm_activities t
          -- Histórico das oportunidades visíveis: quem alterou e quem foi
          -- responsável ou SDR antes/depois (a linha do tempo cita essas
          -- pessoas). Os valores vêm de colunas uuid, gravados pelo gatilho.
          union select h.member_id::uuid
                from public.crm_audit_log l
                join public.crm_opportunities o
                  on l.entity_type = 'opportunity' and l.entity_id = o.id::text
                cross join lateral (values
                  (l.actor_id::text),
                  (l.changes -> 'owner_id' ->> 'old'),
                  (l.changes -> 'owner_id' ->> 'new'),
                  (l.changes -> 'sdr_id' ->> 'old'),
                  (l.changes -> 'sdr_id' ->> 'new')
                ) as h(member_id)
                where h.member_id is not null
        ) r
        where r.member_id is not null
      )
    end,
    p_include_without_access
  ) m
$$;

revoke execute on function public.crm_list_members(boolean) from public, anon;
grant execute on function public.crm_list_members(boolean) to authenticated;

-- ── 3. Etapas: integridade e reordenação ────────────────────────────────────

-- Regras por linha. SECURITY DEFINER para enxergar todas as oportunidades,
-- não só as que a RLS mostra a quem configura.
create or replace function crm_private.guard_stage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    if old.id = 'novo' then
      raise exception 'A etapa de entrada (Novo) não pode ser excluída.' using errcode = '23514';
    end if;
    -- Etapa com oportunidades: a FK de crm_opportunities.stage_id já recusa.
    return old;
  end if;

  if tg_op = 'INSERT' then
    return new;
  end if;

  if new.id is distinct from old.id then
    raise exception 'O identificador da etapa não pode mudar.' using errcode = '23514';
  end if;

  -- Leads do site entram em 'novo' (lead_to_crm) e é o padrão das inclusões.
  if old.id = 'novo' and (not new.active or new.kind <> 'open') then
    raise exception 'A etapa de entrada (Novo) precisa continuar ativa e aberta.'
      using errcode = '23514';
  end if;

  if old.active and not new.active and exists (
    select 1 from public.crm_opportunities o
    where o.stage_id = old.id and o.archived_at is null
  ) then
    raise exception 'Mova ou arquive as oportunidades desta etapa antes de desativá-la.'
      using errcode = '23514';
  end if;

  if new.kind is distinct from old.kind and exists (
    select 1 from public.crm_opportunities o where o.stage_id = old.id
  ) then
    raise exception 'O tipo de uma etapa que já tem oportunidades não pode mudar.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

-- Regra do conjunto, depois de cada comando: sem uma etapa ativa de cada
-- tipo não dá para ganhar, perder ou trabalhar uma oportunidade.
create or replace function crm_private.check_stage_kinds()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from unnest(array['open', 'won', 'lost']) as k(kind)
    where not exists (
      select 1 from public.crm_stages s where s.kind = k.kind and s.active
    )
  ) then
    raise exception 'O funil precisa de ao menos uma etapa ativa de cada tipo: aberta, ganha e perdida.'
      using errcode = '23514';
  end if;
  return null;
end;
$$;

revoke execute on function crm_private.guard_stage()       from public;
revoke execute on function crm_private.check_stage_kinds() from public;

create or replace trigger crm_stages_guard
  before insert or update or delete on public.crm_stages
  for each row execute function crm_private.guard_stage();

create or replace trigger crm_stages_kinds
  after insert or update or delete on public.crm_stages
  for each statement execute function crm_private.check_stage_kinds();

-- Reordenar num comando só (subir/descer no app). SECURITY INVOKER: o UPDATE
-- passa pela policy crm_stages_update de quem chama.
-- p_stage_ids: todas as etapas, cada uma uma vez, na nova ordem.
create or replace function public.crm_reorder_stages(p_stage_ids text[])
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not crm_private.can_manage_stages() then
    raise exception 'Somente a administração do CRM configura as etapas.'
      using errcode = '42501';
  end if;

  if p_stage_ids is null
     or cardinality(p_stage_ids) <> (select count(*) from public.crm_stages)
     or cardinality(p_stage_ids) <> (select count(distinct x) from unnest(p_stage_ids) as x)
     or exists (
       select 1 from unnest(p_stage_ids) as x
       where not exists (select 1 from public.crm_stages s where s.id = x)
     ) then
    raise exception 'Envie todas as etapas, cada uma uma vez, na nova ordem.'
      using errcode = '22023';
  end if;

  update public.crm_stages s
  set position = (o.ord * 10)::smallint
  from unnest(p_stage_ids) with ordinality as o(stage_id, ord)
  where s.id = o.stage_id
    and s.position is distinct from (o.ord * 10)::smallint;
end;
$$;

revoke execute on function public.crm_reorder_stages(text[]) from public, anon;
grant execute on function public.crm_reorder_stages(text[]) to authenticated;
