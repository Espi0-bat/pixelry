-- Financeiro (app móvel) — 5/5: guarda do papel de profiles criados pela API.
--
-- Contrato: docs/FINANCEIRO_DESIGN.md (seção 3.5) no repositório do app.
--
-- ATENÇÃO: este é o único arquivo do pacote que põe um objeto em uma tabela
-- compartilhada fora de invoices (public.profiles). Ele fica separado de
-- propósito: se a integração preferir tratar isso numa migration compartilhada
-- (junto com o CRM, que também depende de profiles.role), basta tirar este
-- arquivo antes do db push e levar o mesmo conteúdo para lá. Sem ele, o
-- financeiro continua funcionando, mas o caminho descrito abaixo fica aberto
-- e a suíte acusa (manager_cannot_insert_privileged_profile,
-- trigger_functions_closed).
--
-- Não altera colunas, CHECKs, policies nem grants de profiles; só acrescenta um
-- gatilho BEFORE INSERT que, para authenticated/anon, aceita apenas role
-- 'client'. Ninguém do dashboard, do app ou das Edge Functions insere profile
-- com o JWT do usuário: create-employee/create-client usam service_role e o
-- cadastro passa por handle_new_user (SECURITY DEFINER), que não muda o papel.

-- ── Guarda: papel de profile novo criado pela API ───────────────────────────
-- O dono do financeiro é quem tem profiles.role = 'super_admin'. Mudar role
-- por UPDATE já é barrado para authenticated/anon (grant por coluna e
-- guard_profile_role, de 20260902000050), mas o INSERT não: authenticated
-- mantém INSERT e DELETE em profiles, e a policy "Admin full access" deixa
-- qualquer manager apagar um profile e inseri-lo de novo com role
-- 'super_admin', virando dono do financeiro sem concessão nem auditoria.
-- Este gatilho fecha esse caminho: pela API, profile novo só nasce como
-- client. Edge Functions (service_role), handle_new_user (SECURITY DEFINER,
-- roda como o dono) e o SQL Editor (postgres) passam direto. Nada do dashboard
-- nem do app insere em profiles com o JWT do usuário.
-- SECURITY INVOKER de propósito (mesmo motivo de guard_profile_role):
-- current_user precisa ser o papel real da conexão.
create or replace function finance_private.guard_profile_insert_role()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon')
     and new.role is distinct from 'client' then
    raise exception 'Profile novo criado pela API só pode ter o papel client.'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- Função de gatilho: ninguém precisa de EXECUTE.
revoke execute on function finance_private.guard_profile_insert_role() from public, anon, authenticated;

drop trigger if exists finance_profiles_insert_role_guard_trg on public.profiles;
create trigger finance_profiles_insert_role_guard_trg
  before insert on public.profiles
  for each row execute function finance_private.guard_profile_insert_role();
