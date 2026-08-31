create table if not exists invoices (
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

drop policy if exists "service_full_access" on invoices;
drop policy if exists "client_read_own_invoices" on invoices;
drop policy if exists "service_role_full_access" on invoices;

create policy "client_read_own_invoices" on invoices
  for select using (auth.uid() = client_id);

create policy "service_role_full_access" on invoices
  for all using (auth.role() = 'service_role');
