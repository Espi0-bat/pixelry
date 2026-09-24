-- SEC-01 — Escalação de privilégio via profiles.role
--
-- As duas políticas de UPDATE em profiles verificavam apenas auth.uid() = id.
-- Nenhuma impedia que a linha mudasse de role, e is_admin() decide tudo lendo
-- exatamente essa coluna. Um PATCH em /rest/v1/profiles?id=eq.<próprio-uid>
-- com {"role":"super_admin"} entregava o painel administrativo inteiro a
-- qualquer cliente com conta no portal.
--
-- Três camadas, porque cada uma cobre uma falha diferente:
--   1. grant de coluna  — tira o direito de escrever em role
--   2. trigger          — rede de proteção contra política futura mal escrita
--   3. política única   — WITH CHECK explícito, sem duplicação

-- ── 1. Grants ───────────────────────────────────────────────────────────────
-- Um "revoke update (role)" sozinho não teria efeito: o papel tem UPDATE no
-- nível da tabela, e nesse caso o Postgres ignora a revogação por coluna.
-- É preciso derrubar o grant de tabela e reconceder coluna a coluna.
--
-- A lista abaixo é todas as colunas menos `id` (chave) e `role`. Conferido no
-- frontend: nada fora das Edge Functions (que usam service_role) escreve role.
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

-- anon nunca precisou escrever em profiles; a RLS já barrava, mas o grant
-- estava aberto sem motivo.
revoke insert, update, delete on public.profiles from anon;

-- ── 2. Trigger ──────────────────────────────────────────────────────────────
-- SECURITY INVOKER de propósito: com SECURITY DEFINER, current_user passaria a
-- ser o dono da função e a checagem perderia o sentido. Assim current_user é o
-- papel real da conexão — 'authenticated'/'anon' via PostgREST, 'service_role'
-- nas Edge Functions, 'postgres' no SQL Editor.
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

-- ── 3. Política ─────────────────────────────────────────────────────────────
-- Havia duas políticas permissivas de UPDATE fazendo a mesma coisa, e a mais
-- antiga sem WITH CHECK. O (select auth.uid()) faz o Postgres avaliar uma vez
-- em vez de por linha (advisor auth_rls_initplan).
drop policy if exists "Users can update own profile" on public.profiles;
drop policy if exists "profiles_update_own"          on public.profiles;

create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using      ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);
