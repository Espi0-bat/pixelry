-- CRM (app móvel) — 1/4: papéis do app e nível de acesso ao CRM por pessoa.
--
-- Só amplia: nenhuma linha existente muda e os quatro papéis atuais continuam
-- valendo como antes.
--
-- 1. profiles_role_check passa a aceitar os papéis que o app Flutter já
--    reconhece (lib/core/auth/app_role.dart): partner, sales_trial,
--    employee_dev e sdr. A lista é a mesma do app, inteira, para que os
--    pacotes Ponto e Financeiro possam repetir este bloco sem conflito.
--    is_admin() e is_team() NÃO mudam: o dashboard continua tratando como
--    equipe só super_admin/manager/employee. Isso é decisão da integração.
--
-- 2. profiles.crm_access: ajuste administrativo do acesso ao CRM, pessoa a
--    pessoa, lido pelo banco a cada consulta. Muda sem novo APK.
--      NULL       = padrão do papel (ver crm_private.access_level_of)
--      'full'     = CRM completo
--      'assigned' = só o que estiver atribuído à pessoa
--      'none'     = sem CRM
--    super_admin é sempre 'full'; client e papel desconhecido, sempre 'none',
--    qualquer que seja o valor da coluna.
--    authenticated NÃO recebe UPDATE nesta coluna (o grant de profiles é por
--    coluna desde 20260902000050). Só crm_set_member_access(), restrita ao
--    super_admin, Edge Functions (service_role) e o SQL Editor a alteram.
--
-- 3. crm_private: schema fora da API REST (o PostgREST expõe public e
--    graphql_public), com as funções usadas pelas policies do CRM.
--    authenticated precisa de USAGE e EXECUTE: expressão de policy roda com
--    os privilégios de quem consulta (lição de 20260903175521). O que o
--    schema impede é chamar essas funções por /rest/v1/rpc.

-- ── 1. Papéis ───────────────────────────────────────────────────────────────
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role = any (array[
    'super_admin', 'partner', 'manager', 'sales_trial',
    'employee_dev', 'employee', 'sdr', 'client'
  ]));

-- ── 2. Ajuste de acesso ao CRM ──────────────────────────────────────────────
alter table public.profiles
  add column if not exists crm_access text
    constraint profiles_crm_access_check
    check (crm_access in ('none', 'assigned', 'full'));

comment on column public.profiles.crm_access is
  'Ajuste do acesso ao CRM. NULL = padrão do papel. Alterar via crm_set_member_access().';

-- ── 3. Funções de acesso ────────────────────────────────────────────────────
create schema if not exists crm_private;
revoke all on schema crm_private from public;
grant usage on schema crm_private to authenticated, service_role;

-- Papel de uma pessoa. NULL quando não há perfil.
create or replace function crm_private.role_of(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p where p.id = p_user_id
$$;

-- Nível efetivo de acesso ao CRM de uma pessoa.
--   super_admin                    → full, sempre
--   client, desconhecido, sem perfil → none, sempre
--   demais papéis internos         → crm_access, se definido; senão o padrão:
--     partner, manager, sales_trial → full
--     sdr                           → assigned
--     employee, employee_dev        → none
create or replace function crm_private.access_level_of(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case
      when p.role = 'super_admin' then 'full'
      when p.role is null
        or p.role <> all (array['partner', 'manager', 'sales_trial', 'sdr', 'employee_dev', 'employee'])
        then 'none'
      when p.crm_access is not null then p.crm_access
      when p.role = any (array['partner', 'manager', 'sales_trial']) then 'full'
      when p.role = 'sdr' then 'assigned'
      else 'none'
    end
    from public.profiles p
    where p.id = p_user_id
  ), 'none')
$$;

-- Nível de quem está chamando. É a função que as policies usam.
create or replace function crm_private.access_level()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select crm_private.access_level_of(auth.uid())
$$;

-- Exclusão definitiva e ajuste de acessos: só super_admin.
create or replace function crm_private.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(crm_private.role_of(auth.uid()) = 'super_admin', false)
$$;

-- Configurar etapas do funil: administração com CRM completo.
create or replace function crm_private.can_manage_stages()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select crm_private.access_level() = 'full'
     and coalesce(crm_private.role_of(auth.uid()) = any (array['super_admin', 'partner', 'manager']), false)
$$;

revoke execute on function crm_private.role_of(uuid)         from public;
revoke execute on function crm_private.access_level_of(uuid) from public;
revoke execute on function crm_private.access_level()        from public;
revoke execute on function crm_private.is_super_admin()      from public;
revoke execute on function crm_private.can_manage_stages()   from public;

-- role_of/access_level_of recebem um id qualquer: ficam só para as funções
-- SECURITY DEFINER (que rodam como dono) e para o service_role.
grant execute on function crm_private.role_of(uuid)         to service_role;
grant execute on function crm_private.access_level_of(uuid) to service_role;
grant execute on function crm_private.access_level()        to authenticated, service_role;
grant execute on function crm_private.is_super_admin()      to authenticated, service_role;
grant execute on function crm_private.can_manage_stages()   to authenticated, service_role;

-- ── 4. RPCs do app ──────────────────────────────────────────────────────────
-- O que a pessoa logada pode fazer no CRM. O app decide a interface por aqui,
-- não pelo papel gravado no APK. NULL quando não há perfil.
create or replace function public.crm_my_access()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'user_id',           p.id,
    'role',              p.role,
    'access_level',      crm_private.access_level_of(p.id),
    'can_assign',        crm_private.access_level_of(p.id) = 'full',
    'can_delete',        p.role = 'super_admin',
    'can_manage_stages', crm_private.access_level_of(p.id) = 'full'
                         and p.role = any (array['super_admin', 'partner', 'manager']),
    'can_manage_access', p.role = 'super_admin'
  )
  from public.profiles p
  where p.id = auth.uid()
$$;

-- Pessoas que podem ser responsáveis no CRM, com nome para exibição.
-- Existe porque as policies de profiles só mostram a equipe para is_team(),
-- e sales_trial/sdr não são is_team(). Devolve só id, nome, e-mail e papel.
-- p_include_without_access: o super_admin vê também a equipe sem CRM, para
-- conceder acesso. Para os demais o parâmetro é ignorado.
create or replace function public.crm_list_members(p_include_without_access boolean default false)
returns table (id uuid, full_name text, email text, role text, access_level text, crm_access text)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    coalesce(nullif(btrim(p.full_name), ''), p.email, 'Sem nome'),
    p.email,
    p.role,
    crm_private.access_level_of(p.id),
    case when crm_private.is_super_admin() then p.crm_access end
  from public.profiles p
  where crm_private.access_level() <> 'none'
    and p.role <> 'client'
    and (
      crm_private.access_level_of(p.id) <> 'none'
      or (p_include_without_access and crm_private.is_super_admin())
    )
  order by 2
$$;

revoke execute on function public.crm_my_access()             from public, anon;
revoke execute on function public.crm_list_members(boolean)   from public, anon;
grant execute on function public.crm_my_access()              to authenticated;
grant execute on function public.crm_list_members(boolean)    to authenticated;
