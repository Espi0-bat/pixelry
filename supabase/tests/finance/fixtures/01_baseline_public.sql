-- Baseline de public para a suíte do financeiro num Postgres PURO.
-- Usado só por `run.sh --bootstrap`, depois de 00_supabase_stub.sql.
--
-- Idempotente: se public.profiles já existe (Supabase de verdade, homologação,
-- ou baseline já aplicada), não faz nada.
--
-- Por que existe: as migrations versionadas não reconstroem o banco do zero
-- (profiles, projects, deliveries, assets, client_files e portal_events foram
-- criadas fora delas, e 20260608015308 recria um CHECK com nome repetido),
-- então `supabase db reset` não serve. Isto é o subconjunto de public do qual
-- o financeiro depende, no estado efetivo depois de 20260924033541.
--
-- Origem de cada trecho (supabase/migrations/):
--   profiles — tabela criada fora das migrations. Colunas: id, full_name,
--              company_name, avatar_url, created_at, updated_at (estrutura
--              original, inferida do grant por coluna de 20260902000050 e do
--              código); email, contact_info (20260526233608); role, job_title,
--              assigned_employee_id (20260607210944). FK id → auth.users on
--              delete cascade (padrão Supabase: apagar o usuário apaga o perfil).
--   profiles_role_check   — 20260608015308 (super_admin, manager, employee,
--              client). O CHECK inline de 20260607210944 (admin/employee/client)
--              não existe mais no estado efetivo.
--   handle_new_user + on_auth_user_created — 20260526233608; search_path ''
--              e revoke de EXECUTE — 20260831041554.
--   guard_profile_role + profiles_guard_role — 20260902000050.
--   grants de profiles — default privileges (stub) + 20260902000050 (UPDATE
--              só por coluna para authenticated; anon sem INSERT/UPDATE/DELETE).
--   policies de profiles:
--     "Admin full access"            — 20260526233608
--     "Users can view own profile"   — criada fora das migrations (citada em
--                                      20260924033540)
--     employees_see_assigned_clients — 20260608013505
--     team_members_see_each_other    — 20260924033540
--     profiles_update_own            — 20260902000050
--   is_admin() — 20260608023208 (corpo por role), search_path '' —
--              20260831041554, grants — 20260903175521.
--   is_team()  — 20260831185909, grants — 20260903175521.
--   invoices   — 20260608190020 / 20260609025153 (colunas, FK cascade, RLS,
--              gatilho de updated_at); idempotency_key, invoices_status_check
--              e invoices_idempotency_key_uniq — 20260903175117; índices —
--              20260609025104.
--   policies de invoices:
--     client_read_own_invoices — 20260609025153
--     service_role_full_access — 20260609025153
--     "Admin full access"      — 20260903175434

do $baseline$
begin
  if to_regclass('public.profiles') is not null then
    raise notice '01_baseline_public: public.profiles já existe; nada a fazer.';
    return;
  end if;

  -- ── profiles ──────────────────────────────────────────────────────────────
  create table public.profiles (
    id                   uuid primary key references auth.users (id) on delete cascade,
    full_name            text,
    company_name         text,
    avatar_url           text,
    email                text,
    contact_info         jsonb default '{}'::jsonb,
    role                 text not null default 'client',
    job_title            text,
    assigned_employee_id uuid references auth.users (id),
    created_at           timestamptz default now(),
    updated_at           timestamptz default now(),
    constraint profiles_role_check
      check (role in ('super_admin', 'manager', 'employee', 'client'))
  );

  alter table public.profiles enable row level security;

  create index if not exists idx_profiles_role on public.profiles (role);
  create index if not exists idx_profiles_assigned_employee on public.profiles (assigned_employee_id);

  -- 20260902000050: UPDATE só por coluna (sem role) para authenticated.
  revoke update on public.profiles from authenticated;
  grant update (
    full_name, company_name, avatar_url, contact_info, email,
    job_title, assigned_employee_id, updated_at
  ) on public.profiles to authenticated;
  revoke insert, update, delete on public.profiles from anon;

  -- ── Helpers de papel ──────────────────────────────────────────────────────
  create or replace function public.is_admin()
  returns boolean
  language sql
  security definer
  stable
  set search_path = ''
  as $f$
    select exists (
      select 1 from public.profiles
      where id = auth.uid()
      and role in ('super_admin', 'manager')
    )
  $f$;

  create or replace function public.is_team()
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
  as $f$
    select exists (
      select 1 from public.profiles
      where id = auth.uid()
        and role in ('super_admin', 'manager', 'employee')
    )
  $f$;

  revoke execute on function public.is_team() from public;
  grant execute on function public.is_admin() to anon, authenticated, service_role;
  grant execute on function public.is_team()  to anon, authenticated, service_role;

  -- ── Perfil nasce com o usuário ────────────────────────────────────────────
  create or replace function public.handle_new_user()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
  as $f$
  begin
    insert into public.profiles (id, full_name, email)
    values (new.id, new.raw_user_meta_data->>'full_name', new.email)
    on conflict (id) do update set email = excluded.email;
    return new;
  end;
  $f$;

  revoke execute on function public.handle_new_user() from anon, authenticated, public;

  drop trigger if exists on_auth_user_created on auth.users;
  create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

  -- ── Ninguém troca o próprio papel ─────────────────────────────────────────
  create or replace function public.guard_profile_role()
  returns trigger
  language plpgsql
  set search_path = ''
  as $f$
  begin
    if new.role is distinct from old.role
       and current_user in ('authenticated', 'anon') then
      raise exception 'alteração de role não permitida por este papel'
        using errcode = '42501';
    end if;
    return new;
  end;
  $f$;

  drop trigger if exists profiles_guard_role on public.profiles;
  create trigger profiles_guard_role
    before update on public.profiles
    for each row execute function public.guard_profile_role();

  -- ── Policies de profiles ──────────────────────────────────────────────────
  create policy "Admin full access" on public.profiles
    for all to authenticated
    using (public.is_admin())
    with check (public.is_admin());

  create policy "Users can view own profile" on public.profiles
    for select to authenticated
    using (auth.uid() = id);

  create policy employees_see_assigned_clients on public.profiles
    for select to authenticated
    using ((auth.uid() = id) or public.is_admin() or (assigned_employee_id = auth.uid()));

  create policy team_members_see_each_other on public.profiles
    for select to authenticated
    using (
      (select public.is_team())
      and role = any (array['super_admin', 'manager', 'employee'])
    );

  create policy profiles_update_own on public.profiles
    for update to authenticated
    using      ((select auth.uid()) = id)
    with check ((select auth.uid()) = id);

  -- ── invoices ──────────────────────────────────────────────────────────────
  create table public.invoices (
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
  as $f$
  begin
    new.updated_at = now();
    return new;
  end;
  $f$;

  drop trigger if exists invoices_updated_at on public.invoices;
  create trigger invoices_updated_at
    before update on public.invoices
    for each row execute function public.update_invoices_updated_at();

  create policy client_read_own_invoices on public.invoices
    for select
    using (auth.uid() = client_id);

  create policy service_role_full_access on public.invoices
    for all
    using (auth.role() = 'service_role');

  create policy "Admin full access" on public.invoices
    for all to authenticated
    using (public.is_admin())
    with check (public.is_admin());

  raise notice '01_baseline_public: profiles, is_admin, is_team e invoices criados.';
end
$baseline$;
