-- Cliente só pode mudar o STATUS de uma entrega, não o conteúdo.
--
-- A policy "Clientes podem atualizar status das suas entregas" é UPDATE em
-- todas as colunas — nada impedia um cliente de reescrever title/description/
-- file_url da própria entrega. RLS não restringe coluna; este trigger sim.

create or replace function public.deliveries_client_update_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Equipe (super_admin / manager / employee) mantém acesso total.
  if is_team() then
    return new;
  end if;

  if new.project_id  is distinct from old.project_id
  or new.title       is distinct from old.title
  or new.description is distinct from old.description
  or new.type        is distinct from old.type
  or new.file_url    is distinct from old.file_url
  or new.created_at  is distinct from old.created_at
  or new.client_id   is distinct from old.client_id
  or new.due_date    is distinct from old.due_date then
    raise exception 'clients may only change delivery status' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists deliveries_client_update_guard_trg on public.deliveries;
create trigger deliveries_client_update_guard_trg
  before update on public.deliveries
  for each row execute function public.deliveries_client_update_guard();
