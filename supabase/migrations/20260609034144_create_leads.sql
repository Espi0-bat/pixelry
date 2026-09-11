create table leads (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  email         text not null,
  whatsapp      text,
  instagram     text,
  source        text default 'diagnostico_hero',
  created_at    timestamptz default now()
);

-- Habilitar RLS
alter table leads enable row level security;

-- Política 1: Permitir inserção anônima (usuários no site público)
create policy "allow_insert_leads" on leads
  for insert with check (true);

-- Política 2: Permitir leitura apenas para equipe logada
create policy "admin_read_leads" on leads
  for select using (
    exists (
      select 1 from profiles
      where id = auth.uid() and role in ('super_admin', 'manager', 'employee')
    )
  );
