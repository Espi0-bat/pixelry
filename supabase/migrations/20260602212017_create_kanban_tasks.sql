create table if not exists public.kanban_tasks (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  client      text,
  type        text,
  assignee    text,
  priority    text default 'medium' check (priority in ('low', 'medium', 'high')),
  due         date,
  status      text default 'backlog' check (status in ('backlog', 'copy', 'design', 'review', 'done')),
  created_at  timestamptz default now(),
  updated_at  timestamptz default now()
);

alter table public.kanban_tasks enable row level security;

create policy "Admin full access"
  on public.kanban_tasks
  for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

create index if not exists kanban_tasks_created_at_idx on public.kanban_tasks (created_at);

alter publication supabase_realtime add table public.kanban_tasks;
