alter table kanban_tasks enable row level security;

drop policy if exists "admin_only_kanban" on kanban_tasks;

create policy "admin_only_kanban" on kanban_tasks
  for all using (
    exists (
      select 1 from profiles
      where id = auth.uid()
      and role in ('super_admin', 'manager', 'employee')
    )
  );

create index if not exists idx_portal_events_created_at
  on portal_events(created_at desc);

create index if not exists idx_portal_events_client_id
  on portal_events(client_id);
