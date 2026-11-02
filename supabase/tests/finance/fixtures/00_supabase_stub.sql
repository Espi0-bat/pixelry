-- Stub mínimo do Supabase para rodar a suíte do financeiro num Postgres PURO
-- (local, descartável). Usado só por `run.sh --bootstrap`.
--
-- Idempotente: se auth.users já existe (Supabase de verdade, ou stub já
-- aplicado), não faz nada.
--
-- O que cria, igual ao Supabase:
--   * papéis anon, authenticated, service_role (nologin; service_role com
--     bypassrls), concedidos a postgres (e a quem roda o script, se for outro);
--   * schema auth com auth.users (só as colunas que a suíte usa) e as funções
--     auth.uid(), auth.role(), auth.email() e auth.jwt(), que leem
--     request.jwt.claim.* e request.jwt.claims como no Supabase;
--   * pgcrypto, se gen_random_uuid() não existir (Postgres < 13);
--   * os default privileges do Supabase no schema public: toda tabela,
--     função e sequência nova nasce com privilégios para anon, authenticated
--     e service_role. Sem isso a suíte não pegaria um `revoke` esquecido.
--
-- NÃO rode isto num projeto Supabase: lá tudo já existe (e o bloco não faz
-- nada, de qualquer forma).

do $stub$
begin
  if to_regclass('auth.users') is not null then
    raise notice '00_supabase_stub: auth.users já existe; nada a fazer.';
    return;
  end if;

  -- ── Papéis ────────────────────────────────────────────────────────────────
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;

  if exists (select 1 from pg_catalog.pg_roles where rolname = 'postgres') then
    grant anon, authenticated, service_role to postgres;
  end if;
  if current_user <> 'postgres' then
    execute format('grant anon, authenticated, service_role to %I', current_user);
  end if;

  grant usage on schema public to anon, authenticated, service_role;

  -- ── auth ──────────────────────────────────────────────────────────────────
  create schema if not exists auth;
  grant usage on schema auth to anon, authenticated, service_role;

  create table if not exists auth.users (
    id                 uuid primary key,
    email              text,
    raw_user_meta_data jsonb default '{}'::jsonb
  );

  create or replace function auth.uid()
  returns uuid
  language sql
  stable
  as $f$
    select coalesce(
      nullif(current_setting('request.jwt.claim.sub', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    )::uuid
  $f$;

  create or replace function auth.role()
  returns text
  language sql
  stable
  as $f$
    select coalesce(
      nullif(current_setting('request.jwt.claim.role', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
    )::text
  $f$;

  create or replace function auth.email()
  returns text
  language sql
  stable
  as $f$
    select coalesce(
      nullif(current_setting('request.jwt.claim.email', true), ''),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
    )::text
  $f$;

  create or replace function auth.jwt()
  returns jsonb
  language sql
  stable
  as $f$
    select coalesce(
      nullif(current_setting('request.jwt.claim', true), ''),
      nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
  $f$;

  grant execute on function auth.uid()   to anon, authenticated, service_role;
  grant execute on function auth.role()  to anon, authenticated, service_role;
  grant execute on function auth.email() to anon, authenticated, service_role;
  grant execute on function auth.jwt()   to anon, authenticated, service_role;

  -- ── gen_random_uuid ───────────────────────────────────────────────────────
  if to_regprocedure('gen_random_uuid()') is null then
    create extension if not exists pgcrypto;
  end if;

  -- ── Default privileges do Supabase em public ──────────────────────────────
  -- Valem para objetos criados daqui em diante pelo papel que roda o script
  -- (no Supabase: postgres).
  alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
  alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

  raise notice '00_supabase_stub: papéis, auth e default privileges criados.';
end
$stub$;
