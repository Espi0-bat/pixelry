-- ─────────────────────────────────────────────────────────────────────────────
-- Stub do ambiente Supabase para os testes do módulo Ponto e Trabalho.
--
-- Reproduz SÓ o que as migrations versionadas (supabase/migrations) e a
-- plataforma Supabase entregam e que o módulo usa. Nada aqui vem da produção:
-- a fonte é o histórico versionado. Roda num Postgres 17.5 descartável, como
-- superusuário `postgres` (no Supabase o dono das migrations também se chama
-- postgres e ignora a RLS das próprias tabelas, então o efeito é o mesmo).
--
-- Ordem: papéis → schemas → privilégios padrão → auth → profiles → funções
-- auxiliares → policies/grants/triggers, na ordem em que as migrations os
-- deixaram. Cada bloco cita a migration de origem.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Papéis da plataforma ─────────────────────────────────────────────────
-- anon/authenticated/service_role são NOLOGIN NOINHERIT; o PostgREST entra como
-- authenticator (LOGIN NOINHERIT) e troca de papel com SET ROLE a cada pedido.
-- service_role ignora RLS (BYPASSRLS), como no Supabase.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator login noinherit;
  end if;
end;
$$;

grant anon, authenticated, service_role to authenticator;

-- ── 2. Schemas ──────────────────────────────────────────────────────────────
create schema if not exists auth;
create schema if not exists extensions;

grant usage on schema public     to anon, authenticated, service_role;
grant usage on schema auth       to anon, authenticated, service_role;
grant usage on schema extensions to anon, authenticated, service_role;

-- ── 3. Privilégios padrão do Supabase em public ─────────────────────────────
-- Toda tabela, sequência e função nova criada por postgres em public nasce com
-- ALL/EXECUTE para os três papéis da API. No PG 17, ALL em tabela inclui
-- MAINTAIN. Funções ainda recebem EXECUTE para PUBLIC (padrão do Postgres).
-- É por isso que o módulo precisa trabalhar com listas de permissão.
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;

-- ── 4. auth: usuários e leitura do JWT ──────────────────────────────────────
-- Mesmo contrato das funções do GoTrue: leem request.jwt.claims (o PostgREST
-- grava o JWT inteiro ali a cada pedido) e caem para o formato antigo
-- request.jwt.claim.<campo>. String vazia vale como ausente.
create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text,
  raw_user_meta_data jsonb default '{}'::jsonb,
  raw_app_meta_data  jsonb default '{}'::jsonb,
  created_at         timestamptz default now(),
  updated_at         timestamptz default now()
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

create or replace function auth.email()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;

create or replace function auth.jwt()
returns jsonb
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;

-- ── 5. public.profiles ──────────────────────────────────────────────────────
-- A tabela foi criada pelo dashboard (não há CREATE TABLE no histórico). As
-- colunas abaixo são as que o histórico usa: id/full_name/company_name/
-- avatar_url/updated_at (dashboard), email/contact_info (20260526233608),
-- role/job_title/assigned_employee_id (20260607210944).
--
-- profiles_role_check: a 20260607210944 adicionou role com um CHECK inline
-- ('admin','employee','client') que o Postgres nomearia profiles_role_check, e a
-- 20260608015308 faz ADD CONSTRAINT profiles_role_check com outra lista. As duas
-- não convivem; o estado final do histórico é a da 20260608015308, reproduzida
-- aqui com o MESMO texto. A coluna é criada sem o CHECK antigo por isso.
create table if not exists public.profiles (
  id                   uuid primary key references auth.users(id) on delete cascade,
  full_name            text,
  company_name         text,
  avatar_url           text,
  updated_at           timestamptz default now()
);

alter table public.profiles enable row level security;

-- 20260526233608_admin_rls_and_schema
alter table public.profiles
  add column if not exists email text,
  add column if not exists contact_info jsonb default '{}';

-- 20260607210944_add_roles_employee_system (sem o CHECK inline; ver acima)
alter table public.profiles
  add column if not exists role text not null default 'client',
  add column if not exists job_title text,
  add column if not exists assigned_employee_id uuid references auth.users(id);

-- 20260608015308_add_role_constraint_rls_notion_column (texto idêntico)
alter table public.profiles
  add constraint profiles_role_check
  check (role in ('super_admin', 'manager', 'employee', 'client'));

-- 20260609025104_add_performance_indexes
create index if not exists idx_profiles_role on profiles(role);
create index if not exists idx_profiles_assigned_employee on profiles(assigned_employee_id);

-- ── 6. handle_new_user (20260526233608 + 20260831041554) ───────────────────
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, new.raw_user_meta_data->>'full_name', new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

alter function public.handle_new_user() set search_path = '';
revoke execute on function public.handle_new_user() from anon, authenticated, public;

-- ── 7. is_admin (20260608023208 + 20260831041554 + 20260903175256/175521) ──
-- super_admin OU manager. EXECUTE de PUBLIC caiu na 20260903175256 e a reversão
-- devolveu só anon/authenticated/service_role.
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
    and role in ('super_admin', 'manager')
  )
$$;

alter function public.is_admin() set search_path = '';

-- ── 8. is_team (20260831185909 + 20260903175256/175521) ────────────────────
create or replace function public.is_team()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('super_admin', 'manager', 'employee')
  )
$$;

revoke execute on function public.is_team() from public;
grant execute on function public.is_team() to authenticated;

-- 20260903175256_harden_helper_fn_execute (aplicada e revertida)
revoke execute on function public.is_admin() from anon, authenticated, public;
revoke execute on function public.is_team()  from anon, authenticated, public;
grant execute on function public.is_admin() to service_role;
grant execute on function public.is_team()  to service_role;

-- 20260903175521_revert_harden_helper_fn_execute
grant execute on function public.is_admin() to anon, authenticated, service_role;
grant execute on function public.is_team()  to anon, authenticated, service_role;

-- ── 9. Policies de profiles (estado final do histórico) ─────────────────────
-- "Users can view own profile": criada pelo dashboard; citada pela
-- 20260924033540. Formato padrão do dashboard (SELECT, sem TO, auth.uid() = id).
drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile" on public.profiles
  for select using (auth.uid() = id);

-- 20260526233608: FOR ALL com is_admin() — inclui manager. Junto com o INSERT/
-- DELETE de tabela que authenticated mantém, é o furo global de §6.1.
drop policy if exists "Admin full access" on public.profiles;
create policy "Admin full access" on public.profiles
  for all to authenticated using (is_admin()) with check (is_admin());

-- 20260608013505_fix_profiles_rls_infinite_recursion
drop policy if exists "employees_see_assigned_clients" on public.profiles;
create policy "employees_see_assigned_clients"
on public.profiles
for select
to authenticated
using (
  (auth.uid() = id)
  or is_admin()
  or (assigned_employee_id = auth.uid())
);

-- 20260924033540_profiles_team_visibility
drop policy if exists team_members_see_each_other on public.profiles;
create policy team_members_see_each_other on public.profiles
  for select to authenticated
  using (
    (select public.is_team())
    and role = any (array['super_admin', 'manager', 'employee'])
  );

-- ── 10. Escrita em profiles (20260902000050_fix_profile_role_escalation) ───
-- Grants: a tabela nasceu com ALL para anon/authenticated/service_role
-- (privilégios padrão, bloco 3). A migration tira o UPDATE de tabela de
-- authenticated, devolve UPDATE coluna a coluna (sem id e role) e tira
-- INSERT/UPDATE/DELETE de anon. INSERT e DELETE de authenticated continuam.
revoke update on public.profiles from authenticated;

grant update (
  full_name,
  company_name,
  avatar_url,
  contact_info,
  email,
  job_title,
  assigned_employee_id,
  updated_at
) on public.profiles to authenticated;

revoke insert, update, delete on public.profiles from anon;

-- Trigger: SECURITY INVOKER de propósito (current_user = papel real).
create or replace function public.guard_profile_role()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.role is distinct from old.role
     and current_user in ('authenticated', 'anon') then
    raise exception 'alteração de role não permitida por este papel'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_role on public.profiles;

create trigger profiles_guard_role
  before update on public.profiles
  for each row execute function public.guard_profile_role();

drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "profiles_update_own"          on public.profiles;

create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using      ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);
