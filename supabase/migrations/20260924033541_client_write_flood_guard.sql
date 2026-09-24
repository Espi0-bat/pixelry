-- S2 (defesa em profundidade) — trava de flood por cliente em messages e
-- portal_events.
--
-- Um cliente autenticado (ou uma conta criada pelo cadastro público, enquanto
-- esteve aberto) podia inserir sem limite nas duas tabelas. Em messages cada
-- linha vira uma notificação em tempo real na Central de Atendimento; em
-- portal_events só cresce o banco.
--
-- Mesmo padrão do leads_flood_guard, mas por client_id: limite de linhas no
-- último minuto, passado como argumento do trigger. Equipe é isenta.
-- SECURITY DEFINER porque o cliente não tem SELECT em portal_events e a
-- contagem sob RLS voltaria 0. Função de trigger: EXECUTE revogado
-- (PostgREST não consegue chamá-la).

create or replace function public.client_write_flood_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit  integer := coalesce(nullif(tg_argv[0], '')::integer, 30);
  v_recent integer;
begin
  -- Equipe (super_admin / manager / employee) não entra na conta: a resposta
  -- do admin não pode ser bloqueada pelo flood do cliente, e o time escreve em
  -- ritmo humano. Mesmo critério do deliveries_client_update_guard.
  if new.client_id is null or (select public.is_team()) then
    return new;
  end if;

  execute format(
    'select count(*) from %I.%I where client_id = $1 and created_at > now() - interval ''1 minute''',
    tg_table_schema, tg_table_name
  )
  into v_recent
  using new.client_id;

  if v_recent >= v_limit then
    raise exception 'rate limited: too many writes for this client, retry shortly'
      using errcode = '53400';
  end if;

  return new;
end;
$$;

revoke execute on function public.client_write_flood_guard() from anon, authenticated, public;

drop trigger if exists messages_flood_guard_trg on public.messages;
create trigger messages_flood_guard_trg
  before insert on public.messages
  for each row execute function public.client_write_flood_guard('30');

drop trigger if exists portal_events_flood_guard_trg on public.portal_events;
create trigger portal_events_flood_guard_trg
  before insert on public.portal_events
  for each row execute function public.client_write_flood_guard('60');

-- messages não tinha índice em client_id, coluna usada na policy e agora na
-- contagem do trigger. portal_events já tem idx_portal_events_client_id.
create index if not exists idx_messages_client_id_created_at
  on public.messages (client_id, created_at desc);
