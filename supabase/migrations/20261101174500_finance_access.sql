-- Financeiro (app móvel) — 1/5: quem pode ver e quem pode alterar o financeiro.
--
-- Contrato: docs/FINANCEIRO_DESIGN.md (seções 1, 2 e 3.1) no repositório do app.
-- Só acrescenta: nenhuma tabela, função ou policy existente muda. As colunas,
-- o CHECK de papéis, as policies e os grants de profiles ficam como estão (os
-- papéis novos chegam pelo CRM). A guarda de INSERT em profiles, que protege o
-- papel super_admin do qual este arquivo depende, fica separada em
-- 20261101174540_finance_profiles_guard.sql.
--
-- Nível efetivo de acesso ao financeiro (finance_private.level_for):
--   super_admin                         → manage, sempre
--   partner, manager, sales_trial, sdr,
--   employee_dev, employee              → o que estiver concedido em
--                                         finance_access_grants; sem linha = none
--   client, papel desconhecido ou nulo,
--   pessoa sem perfil                   → none, mesmo com concessão gravada
--
-- O manager continua com acesso total a invoices pelo dashboard (policy
-- "Admin full access", que não muda aqui). No módulo financeiro, só com
-- concessão.
--
-- Lições da casa aplicadas:
--   * função usada em policy precisa de EXECUTE para quem consulta: is_owner,
--     can_read e can_manage recebem grant explícito de authenticated e
--     service_role ANTES de qualquer revoke de public;
--   * default privileges do schema public dão EXECUTE direto a anon,
--     authenticated e service_role em toda função nova: por isso as RPCs
--     revogam de public E de anon, explicitamente;
--   * default privileges dão arwdDxtm em toda tabela nova: por isso a tabela
--     revoga tudo de anon, authenticated e service_role e reconcede só SELECT.

-- ── Schema privado ──────────────────────────────────────────────────────────
-- Fora da API REST (o PostgREST expõe public e graphql_public). authenticated
-- precisa de USAGE porque as policies chamam funções daqui.
create schema if not exists finance_private;
revoke all on schema finance_private from public;
grant usage on schema finance_private to authenticated, service_role;

-- ── Regra de nível (pura) ───────────────────────────────────────────────────
create or replace function finance_private.level_for(p_role text, p_grant text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_role = 'super_admin' then 'manage'
    when p_role = any (array['partner', 'manager', 'sales_trial', 'sdr', 'employee_dev', 'employee'])
      then case when p_grant = any (array['read', 'manage']) then p_grant else 'none' end
    else 'none'
  end
$$;

-- level_for não é usada em policy: só as funções SECURITY DEFINER (que rodam
-- como dono) e o service_role a chamam.
grant execute on function finance_private.level_for(text, text) to service_role;
revoke execute on function finance_private.level_for(text, text) from public, anon, authenticated;

-- ── Dono (super_admin) ──────────────────────────────────────────────────────
create or replace function finance_private.is_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select p.role = 'super_admin'
    from public.profiles p
    where p.id = (select auth.uid())
  ), false)
$$;

grant execute on function finance_private.is_owner() to authenticated, service_role;
revoke execute on function finance_private.is_owner() from public, anon;

-- ── Concessões ──────────────────────────────────────────────────────────────
-- Uma linha por pessoa. granted_by sem FK: a autoria fica mesmo se quem
-- concedeu sair. Escrita só por public.finance_set_access (definer) ou pelo
-- SQL Editor como postgres.
create table if not exists public.finance_access_grants (
  user_id    uuid        primary key
                         references public.profiles (id) on delete cascade,
  level      text        not null
                         constraint finance_access_grants_level_check
                         check (level in ('none', 'read', 'manage')),
  reason     text        not null
                         constraint finance_access_grants_reason_check
                         check (char_length(btrim(reason)) between 5 and 500),
  granted_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.finance_access_grants is
  'Acesso ao financeiro por pessoa. Alterar via finance_set_access() (só super_admin).';

alter table public.finance_access_grants enable row level security;

revoke all on table public.finance_access_grants from public, anon, authenticated, service_role;
grant select on table public.finance_access_grants to authenticated;

-- ── Nível de quem está chamando ─────────────────────────────────────────────
create or replace function finance_private.access_level()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select finance_private.level_for(p.role, g.level)
    from public.profiles p
    left join public.finance_access_grants g on g.user_id = p.id
    where p.id = (select auth.uid())
  ), 'none')
$$;

create or replace function finance_private.can_read()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select finance_private.access_level() in ('read', 'manage')
$$;

create or replace function finance_private.can_manage()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select finance_private.access_level() = 'manage'
$$;

grant execute on function finance_private.access_level() to authenticated, service_role;
grant execute on function finance_private.can_read()     to authenticated, service_role;
grant execute on function finance_private.can_manage()   to authenticated, service_role;
revoke execute on function finance_private.access_level() from public, anon;
revoke execute on function finance_private.can_read()     from public, anon;
revoke execute on function finance_private.can_manage()   from public, anon;

-- ── Policy das concessões ───────────────────────────────────────────────────
-- Cada pessoa vê a própria linha; o dono vê todas. Sem policy nem grant de
-- escrita.
drop policy if exists finance_access_grants_select on public.finance_access_grants;
create policy finance_access_grants_select on public.finance_access_grants
  for select to authenticated
  using (user_id = (select auth.uid()) or (select finance_private.is_owner()));

-- ── RPC: o que a pessoa logada pode fazer ───────────────────────────────────
-- Não é set-returning: o PostgREST devolve um objeto. Sempre exatamente uma
-- linha. Sem perfil → level 'none' e profile_role null.
create or replace function public.finance_my_access(
  out level        text,
  out can_read     boolean,
  out can_manage   boolean,
  out is_owner     boolean,
  out profile_role text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    l.lvl,
    l.lvl in ('read', 'manage'),
    l.lvl = 'manage',
    coalesce(p.role = 'super_admin', false),
    p.role
  from (select finance_private.access_level() as lvl) l
  left join public.profiles p on p.id = (select auth.uid())
$$;

-- ── RPC: conceder, mudar ou tirar acesso (só o dono) ────────────────────────
create or replace function public.finance_set_access(p_user_id uuid, p_level text, p_reason text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_reason text;
  v_role   text;
begin
  if not finance_private.is_owner() then
    raise exception 'Só um super admin pode alterar o acesso ao financeiro.'
      using errcode = '42501';
  end if;

  if p_level is null or p_level not in ('none', 'read', 'manage') then
    raise exception 'Nível de acesso inválido. Use none, read ou manage.'
      using errcode = '22023';
  end if;

  v_reason := nullif(btrim(p_reason), '');
  if v_reason is null or char_length(v_reason) < 5 then
    raise exception 'Informe um motivo com pelo menos 5 caracteres.'
      using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'O motivo pode ter no máximo 500 caracteres.'
      using errcode = '22023';
  end if;

  select p.role into v_role
  from public.profiles p
  where p.id = p_user_id;

  if not found then
    raise exception 'Pessoa não encontrada.'
      using errcode = 'P0002';
  end if;

  if v_role = 'super_admin' then
    raise exception 'Super admin já tem acesso completo.'
      using errcode = '22023';
  end if;

  if v_role is null
     or v_role <> all (array['partner', 'manager', 'sales_trial', 'sdr', 'employee_dev', 'employee']) then
    raise exception 'Este papel não pode receber acesso ao financeiro.'
      using errcode = '22023';
  end if;

  perform set_config('pixelry.finance_change_reason', v_reason, true);

  insert into public.finance_access_grants as g (user_id, level, reason, granted_by, updated_at)
  values (p_user_id, p_level, v_reason, auth.uid(), now())
  on conflict (user_id) do update
    set level      = excluded.level,
        reason     = excluded.reason,
        granted_by = excluded.granted_by,
        updated_at = excluded.updated_at;

  -- O motivo vale só para este DML: o resto da transação não o herda.
  perform set_config('pixelry.finance_change_reason', '', true);
end;
$$;

-- ── RPC: lista de acesso (só o dono) ────────────────────────────────────────
-- Pessoas com papel interno ou super_admin. Clientes nunca aparecem.
create or replace function public.finance_access_list()
returns table (
  user_id      uuid,
  display_name text,
  email        text,
  profile_role text,
  level        text,
  reason       text,
  updated_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if not finance_private.is_owner() then
    raise exception 'Só um super admin pode ver e alterar o acesso ao financeiro.'
      using errcode = '42501';
  end if;

  return query
  select
    p.id,
    coalesce(nullif(btrim(p.full_name), ''), nullif(btrim(p.email), ''), 'Sem nome'),
    p.email,
    p.role,
    finance_private.level_for(p.role, g.level),
    g.reason,
    g.updated_at
  from public.profiles p
  left join public.finance_access_grants g on g.user_id = p.id
  where p.role = any (array[
    'super_admin', 'partner', 'manager', 'sales_trial', 'sdr', 'employee_dev', 'employee'
  ])
  order by 2, 1;
end;
$$;

revoke execute on function public.finance_my_access()                 from public, anon;
revoke execute on function public.finance_set_access(uuid, text, text) from public, anon;
revoke execute on function public.finance_access_list()               from public, anon;
grant execute on function public.finance_my_access()                  to authenticated;
grant execute on function public.finance_set_access(uuid, text, text)  to authenticated;
grant execute on function public.finance_access_list()                to authenticated;
