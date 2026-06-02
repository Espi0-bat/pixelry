-- ================================================================
-- Migration: Criar tabela kanban_tasks para o Kanban interno do Admin
-- Execute este SQL no Supabase SQL Editor
-- ================================================================

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

-- Apenas admins autenticados podem acessar (não é visível ao cliente)
alter table public.kanban_tasks enable row level security;

-- Qualquer usuário autenticado pode ler e escrever (admins)
create policy "Admin full access"
  on public.kanban_tasks
  for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- Índice para ordenação por criação
create index if not exists kanban_tasks_created_at_idx on public.kanban_tasks (created_at);

-- Habilita realtime na tabela
alter publication supabase_realtime add table public.kanban_tasks;
