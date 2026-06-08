-- Execute no Supabase Dashboard → SQL Editor

create table invoices (
  id               uuid primary key default gen_random_uuid(),
  client_id        uuid references profiles(id) on delete cascade not null,
  amount           numeric(10,2) not null,
  description      text not null,
  due_date         date,
  status           text default 'pending' check (status in ('pending','paid','cancelled','overdue')),
  mp_preference_id text,
  payment_url      text,
  qr_code          text,
  qr_code_text     text,
  boleto_url       text,
  boleto_barcode   text,
  paid_at          timestamptz,
  created_at       timestamptz default now(),
  updated_at       timestamptz default now()
);

alter table invoices enable row level security;

-- Cliente lê apenas as próprias faturas
create policy "client_read_own_invoices" on invoices
  for select using (auth.uid() = client_id);

-- Service role (Edge Functions) tem acesso total
create policy "service_full_access" on invoices
  for all using (true);

-- Trigger para atualizar updated_at automaticamente
create or replace function update_invoices_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger invoices_updated_at
  before update on invoices
  for each row execute function update_invoices_updated_at();
