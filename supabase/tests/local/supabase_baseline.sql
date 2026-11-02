-- Base local compartilhada para testar as migrations do app móvel (CRM, Ponto
-- e Trabalho, Financeiro e a migration de integração) num Postgres puro, sem
-- tocar em produção.
--
-- As migrations deste repositório não sobem de um banco vazio: profiles,
-- invoices e outras tabelas nasceram pelo dashboard, antes da primeira
-- migration, e 20260608015308 recria um CHECK com nome repetido. Este arquivo
-- reproduz o estado EFETIVO, depois de 20260924033541, do que as migrations
-- 202611* usam:
--
--   * plataforma Supabase: papéis anon/authenticated/service_role (NOLOGIN
--     NOINHERIT; service_role com BYPASSRLS) e authenticator (LOGIN NOINHERIT,
--     como o PostgREST entra), schemas auth e extensions, auth.users e
--     auth.uid()/role()/email()/jwt() com o mesmo contrato do GoTrue, e os
--     privilégios padrão de public (ALL para os três papéis da API);
--   * public.profiles, is_admin(), is_team(), handle_new_user(),
--     guard_profile_role(), policies e grants como estavam em produção em
--     2026-11-01 (inspeção somente leitura daquele dia + migrations
--     20260526233608..20260924033541). Cada bloco cita a origem;
--   * public.leads (20260609034144, 20260826025331, 20260903175232,
--     20260924033536) — o CRM liga os leads antigos e pendura um trigger;
--   * public.invoices (20260608190020/20260609025153, 20260903175117,
--     20260609025104, 20260903175434) — o Financeiro lê e audita.
--
-- Não é uma cópia de produção. Se produção mudar em profiles, leads ou
-- invoices, este arquivo precisa acompanhar. Aplicar UMA vez num banco
-- descartável recém-criado (run-crm-rls.sh, finance/run.sh --bootstrap e o
-- runner do Ponto fazem isso); não aplique em outro lugar.
--
-- Fonte única: o stub antigo do Ponto (stub/supabase_stub.sql) e a baseline do
-- Financeiro (fixtures/01_baseline_public.sql) foram fundidos aqui.

-- ── 1. Papéis da plataforma ─────────────────────────────────────────────────
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
-- ALL/EXECUTE para os três papéis da API (no PG 17, ALL em tabela inclui
-- MAINTAIN). Funções ainda recebem EXECUTE para PUBLIC (padrão do Postgres).
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
  aud                varchar(255),
  role               varchar(255),
  raw_user_meta_data jsonb default '{}'::jsonb,
  raw_app_meta_data  jsonb default '{}'::jsonb,
  is_sso_user        boolean not null default false,
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

grant execute on all functions in schema auth to anon, authenticated, service_role;

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
-- DELETE de tabela que authenticated mantinha, era o furo global que a
-- migration de integração (20261102120000) fecha.
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
-- INSERT/UPDATE/DELETE de anon. INSERT e DELETE de authenticated continuam
-- (até a 20261102120000).
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

-- ── 11. public.leads ────────────────────────────────────────────────────────
-- 20260609034144 (tabela, policy admin_read_leads), 20260826025331 (campos de
-- qualificação), 20260903175232 (CHECKs de tamanho e flood guard),
-- 20260924033536 (só o service_role escreve; anon não lê).
create table if not exists public.leads (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  email            text not null,
  whatsapp         text,
  instagram        text,
  source           text default 'diagnostico_hero',
  created_at       timestamptz default now(),
  clinic_type      text,
  revenue_range    text,
  investment_range text,
  constraint leads_name_len   check (char_length(name) between 1 and 200),
  constraint leads_email_fmt  check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 320),
  constraint leads_wa_len     check (whatsapp is null or char_length(whatsapp) <= 40),
  constraint leads_ig_len     check (instagram is null or char_length(instagram) <= 120),
  constraint leads_src_len    check (source is null or char_length(source) <= 80),
  constraint leads_clinic_len check (clinic_type is null or char_length(clinic_type) <= 120),
  constraint leads_rev_len    check (revenue_range is null or char_length(revenue_range) <= 60),
  constraint leads_inv_len    check (investment_range is null or char_length(investment_range) <= 60)
);

create index if not exists idx_leads_created_at on public.leads (created_at desc);

alter table public.leads enable row level security;

drop policy if exists admin_read_leads on public.leads;
create policy admin_read_leads on public.leads
  for select
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.role = any (array['super_admin', 'manager', 'employee'])
    )
  );

create or replace function public.leads_flood_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_recent integer;
begin
  select count(*) into v_recent
  from public.leads
  where created_at > now() - interval '1 minute';
  if v_recent >= 30 then
    raise exception 'rate limited: too many lead submissions, retry shortly'
      using errcode = '53400';
  end if;
  return new;
end;
$$;

drop trigger if exists leads_flood_guard_trg on public.leads;
create trigger leads_flood_guard_trg
  before insert on public.leads
  for each row execute function public.leads_flood_guard();

-- 20260924033536: só o service_role escreve; anon não lê.
revoke insert, update, delete, truncate, references, trigger
  on public.leads from anon, authenticated;
revoke select on public.leads from anon;

-- ── 12. public.invoices ─────────────────────────────────────────────────────
-- 20260608190020 / 20260609025153 (colunas, FK cascade, RLS, gatilho de
-- updated_at); idempotency_key, invoices_status_check e
-- invoices_idempotency_key_uniq (20260903175117); índices (20260609025104);
-- "Admin full access" (20260903175434).
create table if not exists public.invoices (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid references public.profiles (id) on delete cascade not null,
  amount           numeric(10,2) not null,
  description      text not null,
  due_date         date,
  status           text default 'pending',
  mp_preference_id text,
  payment_url      text,
  qr_code          text,
  qr_code_text     text,
  boleto_url       text,
  boleto_barcode   text,
  paid_at          timestamptz,
  created_at       timestamptz default now(),
  updated_at       timestamptz default now(),
  idempotency_key  text,
  constraint invoices_status_check
    check (status = any (array['draft', 'pending', 'paid', 'cancelled', 'overdue', 'error']))
);

alter table public.invoices enable row level security;

create unique index if not exists invoices_idempotency_key_uniq
  on public.invoices (idempotency_key)
  where idempotency_key is not null and status <> 'cancelled';
create index if not exists idx_invoices_client_id on public.invoices (client_id);
create index if not exists idx_invoices_status on public.invoices (status);

create or replace function public.update_invoices_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists invoices_updated_at on public.invoices;
create trigger invoices_updated_at
  before update on public.invoices
  for each row execute function public.update_invoices_updated_at();

drop policy if exists client_read_own_invoices on public.invoices;
create policy client_read_own_invoices on public.invoices
  for select
  using (auth.uid() = client_id);

drop policy if exists service_role_full_access on public.invoices;
create policy service_role_full_access on public.invoices
  for all
  using (auth.role() = 'service_role');

drop policy if exists "Admin full access" on public.invoices;
create policy "Admin full access" on public.invoices
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());
