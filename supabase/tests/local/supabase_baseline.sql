-- Base local para testar as migrations do CRM sem tocar em produção.
--
-- As migrations deste repositório não sobem de um banco vazio: tabelas como
-- profiles nasceram pelo dashboard, antes da primeira migration. Este arquivo
-- reproduz o mínimo que as migrations do CRM (20261101150*) usam:
--
--   * a parte da plataforma Supabase: papéis anon/authenticated/service_role,
--     o schema auth com auth.users e auth.uid()/role()/email()/jwt(), e os
--     privilégios padrão do schema public (tudo para anon e authenticated,
--     que as migrations do CRM precisam revogar);
--   * profiles, leads, is_admin(), is_team(), handle_new_user() e
--     guard_profile_role() como estavam em produção em 2026-11-01: colunas,
--     constraints, policies e grants conferidos na inspeção somente leitura
--     feita naquele dia e nas migrations 20260526233608..20260924033541.
--
-- Não é uma cópia de produção. Se produção mudar em profiles ou leads, este
-- arquivo precisa acompanhar. Roda num banco descartável criado pelo
-- run-crm-rls.sh; não aplique em outro lugar.

-- ── Plataforma: papéis ──────────────────────────────────────────────────────
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
end;
$$;

-- ── Plataforma: auth ────────────────────────────────────────────────────────
create schema if not exists auth;

create table if not exists auth.users (
  id                 uuid primary key,
  email              text,
  aud                varchar(255),
  role               varchar(255),
  raw_user_meta_data jsonb,
  is_sso_user        boolean not null default false,
  created_at         timestamptz default now()
);

-- Mesmas definições do Supabase: o PostgREST põe o JWT em request.jwt.claims.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;

create or replace function auth.email() returns text
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')
  )::jsonb
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;

-- ── Plataforma: privilégios padrão de public ────────────────────────────────
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

-- ── profiles ────────────────────────────────────────────────────────────────
create table public.profiles (
  id                   uuid not null primary key references auth.users(id) on delete cascade,
  full_name            text,
  company_name         text,
  avatar_url           text,
  updated_at           timestamptz default now(),
  email                text,
  contact_info         jsonb default '{}'::jsonb,
  role                 text not null default 'client',
  job_title            text,
  assigned_employee_id uuid references auth.users(id),
  constraint profiles_role_check
    check (role = any (array['super_admin', 'manager', 'employee', 'client']))
);

create index idx_profiles_role on public.profiles (role);
create index idx_profiles_assigned_employee on public.profiles (assigned_employee_id);

alter table public.profiles enable row level security;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('super_admin', 'manager')
  )
$$;

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

-- Produção: EXECUTE para anon, authenticated e service_role, sem PUBLIC.
revoke execute on function public.is_admin() from public;
revoke execute on function public.is_team() from public;
grant execute on function public.is_admin() to anon, authenticated, service_role;
grant execute on function public.is_team() to anon, authenticated, service_role;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, new.raw_user_meta_data ->> 'full_name', new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from anon, authenticated, public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

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

create trigger profiles_guard_role
  before update on public.profiles
  for each row execute function public.guard_profile_role();

create policy "Admin full access" on public.profiles
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy "Users can view own profile" on public.profiles
  for select
  using (auth.uid() = id);

create policy employees_see_assigned_clients on public.profiles
  for select to authenticated
  using ((auth.uid() = id) or public.is_admin() or (assigned_employee_id = auth.uid()));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy team_members_see_each_other on public.profiles
  for select to authenticated
  using (
    (select public.is_team())
    and role = any (array['super_admin', 'manager', 'employee'])
  );

-- 20260902000050: UPDATE só por coluna, sem role; anon sem escrita.
revoke update on public.profiles from authenticated;
grant update (
  full_name, company_name, avatar_url, contact_info, email,
  job_title, assigned_employee_id, updated_at
) on public.profiles to authenticated;
revoke insert, update, delete on public.profiles from anon;

-- ── leads ───────────────────────────────────────────────────────────────────
create table public.leads (
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

create index idx_leads_created_at on public.leads (created_at desc);

alter table public.leads enable row level security;

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

create trigger leads_flood_guard_trg
  before insert on public.leads
  for each row execute function public.leads_flood_guard();

-- 20260924033536: só o service_role escreve; anon não lê.
revoke insert, update, delete, truncate, references, trigger
  on public.leads from anon, authenticated;
revoke select on public.leads from anon;
