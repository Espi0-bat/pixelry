create table if not exists weekly_goals (
  id             uuid primary key default gen_random_uuid(),
  title          text not null,
  description    text,
  week_start     date not null,
  week_end       date not null,
  status         text default 'pending' check (status in ('pending','done')),
  priority       text default 'medium' check (priority in ('high','medium','low')),
  category       text,
  assignee       text,
  notion_page_id text,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);

alter table weekly_goals enable row level security;

create policy "admins_only" on weekly_goals
  for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');
