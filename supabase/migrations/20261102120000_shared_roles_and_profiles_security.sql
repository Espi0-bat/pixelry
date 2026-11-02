-- Integração do app móvel — papéis aceitos, proteção de profiles e helpers
-- globais. Vem DEPOIS das migrations dos três módulos (CRM 20261101150*,
-- Ponto 20261101170000, Financeiro 20261101174500..174530) e centraliza o
-- que cada um deles só podia supor:
--
--   1. profiles_role_check aceita os oito papéis do app
--      (lib/core/auth/app_role.dart). O CRM já ampliava a constraint; aqui
--      fica a versão de referência, idempotente, que vale mesmo se um módulo
--      for revertido.
--   2. authenticated perde INSERT e DELETE em public.profiles. Pelo código,
--      nenhum cliente insere ou apaga perfil com o JWT da pessoa: quem cria é
--      handle_new_user (SECURITY DEFINER, roda como o dono) e as Edge
--      Functions create-employee/create-client (service_role). Com o grant,
--      "Admin full access" (FOR ALL, is_admin() inclui manager) deixava um
--      manager apagar o perfil de outra conta e reinseri-lo como super_admin,
--      furando toda regra baseada em profiles.role (ponto, CRM, financeiro,
--      painel). profiles_guard_role (20260902000050) só cobre UPDATE.
--   3. Defesa em profundidade: trigger BEFORE INSERT em profiles, no schema
--      public, que só deixa authenticated/anon criarem perfil com role
--      'client', caso algum grant ou policy seja reaberto no futuro.
--      SECURITY INVOKER de propósito: current_user precisa ser o papel real
--      da conexão (mesmo padrão de guard_profile_role). Não depende de
--      finance_private nem de nenhum schema de módulo.
--   4. A guarda equivalente do Financeiro (finance_profiles_insert_role_guard_trg
--      e finance_private.guard_profile_insert_role) sai do repositório e, se
--      tiver sido aplicada em algum ambiente, é removida aqui. Fica só a
--      proteção compartilhada.
--   5. is_admin() e is_team() revisados para os papéis novos:
--      * is_admin() continua super_admin OU manager. partner e sales_trial
--        NÃO ganham administração do painel (deliveries, invoices, kanban,
--        profiles alheios); o módulo de ponto nunca usou is_admin().
--      * is_team() passa a ser quem opera entregas: super_admin, partner,
--        manager, employee e employee_dev. sales_trial e sdr (comerciais)
--        ficam fora: is_team() dá leitura/escrita nos buckets deliveries e
--        client-uploads de TODOS os clientes e escrita em internal_messages,
--        e o CRM já entrega a eles o que precisam por crm_list_members().
--        client e papel desconhecido nunca entram.
--      * team_members_see_each_other: quem é is_team() vê o perfil de todo
--        papel interno (inclusive sales_trial e sdr), nunca de client.
--
-- O que NÃO muda: a policy "Admin full access" (sem INSERT/DELETE no grant
-- ela só vale para SELECT/UPDATE), o UPDATE por coluna de authenticated (sem
-- role), as policies de kanban_tasks/weekly_goals/leads (listas fixas de
-- super_admin/manager/employee; os papéis novos não as veem) e as regras de
-- cada módulo: só super_admin revisa o ponto alheio, sdr vê no CRM só o que
-- lhe foi atribuído, financeiro depende de concessão exceto para super_admin.
--
-- Idempotente: pode ser aplicada de novo sem erro e sem mudar o estado. Sem
-- begin/commit: a CLI roda cada migration na própria transação.

-- ── 1. Papéis aceitos ───────────────────────────────────────────────────────
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role = any (array[
    'super_admin', 'partner', 'manager', 'sales_trial',
    'employee_dev', 'employee', 'sdr', 'client'
  ]));

comment on constraint profiles_role_check on public.profiles is
  'Papéis do app móvel (lib/core/auth/app_role.dart). Migration de integração 20261102120000.';

-- ── 2. authenticated não insere nem apaga profiles ─────────────────────────
revoke insert, delete on table public.profiles from authenticated;
revoke insert, update, delete on table public.profiles from anon;

-- ── 3. Guarda compartilhada: perfil novo pela API só nasce como client ─────
create or replace function public.guard_profile_insert_role()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon')
     and new.role is distinct from 'client' then
    raise exception 'Perfil novo criado pela API só pode ter o papel client.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

comment on function public.guard_profile_insert_role() is
  'BEFORE INSERT em profiles: authenticated/anon só criam perfil com role client. SECURITY INVOKER de propósito.';

-- Função de gatilho: ninguém precisa de EXECUTE.
revoke all on function public.guard_profile_insert_role() from public, anon, authenticated;

drop trigger if exists profiles_guard_insert_role on public.profiles;
create trigger profiles_guard_insert_role
  before insert on public.profiles
  for each row execute function public.guard_profile_insert_role();

-- ── 4. Sai a guarda do Financeiro (substituída pela compartilhada) ─────────
drop trigger if exists finance_profiles_insert_role_guard_trg on public.profiles;
drop function if exists finance_private.guard_profile_insert_role();

-- ── 5. Helpers globais ──────────────────────────────────────────────────────
-- is_admin(): super_admin OU manager (inalterado). Corpo e grants repetidos
-- aqui para a definição de referência ficar num lugar só.
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

comment on function public.is_admin() is
  'Administração do painel: super_admin ou manager. partner e sales_trial não entram (20261102120000).';

-- is_team(): quem opera entregas e arquivos de cliente.
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
      and role in ('super_admin', 'partner', 'manager', 'employee', 'employee_dev')
  )
$$;

comment on function public.is_team() is
  'Equipe de entrega: super_admin, partner, manager, employee, employee_dev. sales_trial, sdr e client não entram (20261102120000).';

-- Grants como em 20260903175521: anon/authenticated/service_role, sem PUBLIC.
revoke execute on function public.is_admin() from public;
revoke execute on function public.is_team()  from public;
grant execute on function public.is_admin() to anon, authenticated, service_role;
grant execute on function public.is_team()  to anon, authenticated, service_role;

-- Equipe vê o perfil de todo papel interno (nunca de client).
drop policy if exists team_members_see_each_other on public.profiles;
create policy team_members_see_each_other on public.profiles
  for select to authenticated
  using (
    (select public.is_team())
    and role = any (array[
      'super_admin', 'partner', 'manager', 'sales_trial',
      'employee_dev', 'employee', 'sdr'
    ])
  );
