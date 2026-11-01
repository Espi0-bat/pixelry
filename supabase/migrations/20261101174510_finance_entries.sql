-- Financeiro (app móvel) — 2/5: categorias e lançamentos manuais.
--
-- Contrato: docs/FINANCEIRO_DESIGN.md (seção 3.2) no repositório do app.
--
-- Lançamentos manuais cobrem despesas, contas a pagar e receitas fora do
-- Mercado Pago. Cobranças do Mercado Pago continuam só em public.invoices.
--
-- Nada é apagado: DELETE e TRUNCATE são recusados por gatilho (inclusive para
-- postgres). Correção é feita com motivo; "cancelado" = o registro não valeu;
-- "estorno" = o dinheiro voltou (linha nova, entry_kind = 'reversal').
--
-- Escrita só pelas RPCs SECURITY DEFINER de 20261101174530. authenticated tem
-- só SELECT (filtrado pela RLS); as policies de INSERT/UPDATE existem como
-- segunda trava, sem grant correspondente. Sem policy nem grant de DELETE.
--
-- Sem seed de categorias: as categorias são decisão do negócio.

-- ── Categorias ──────────────────────────────────────────────────────────────
create table if not exists public.finance_categories (
  id          uuid        primary key default gen_random_uuid(),
  name        text        not null
                          constraint finance_categories_name_check
                          check (char_length(btrim(name)) between 2 and 60),
  applies_to  text        not null default 'both'
                          constraint finance_categories_applies_to_check
                          check (applies_to in ('income', 'expense', 'both')),
  archived_at timestamptz,
  created_by  uuid,
  updated_by  uuid,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.finance_categories is
  'Categorias do financeiro. Arquivar em vez de apagar (finance_set_category_archived).';

create unique index if not exists finance_categories_name_uniq
  on public.finance_categories (lower(btrim(name)));

-- ── Lançamentos ─────────────────────────────────────────────────────────────
-- amount em numeric(14,2); a API trafega centavos inteiros (amount_cents).
create table if not exists public.finance_entries (
  id                uuid          primary key default gen_random_uuid(),
  direction         text          not null
                                  constraint finance_entries_direction_check
                                  check (direction in ('income', 'expense')),
  entry_kind        text          not null default 'regular'
                                  constraint finance_entries_entry_kind_check
                                  check (entry_kind in ('regular', 'reversal')),
  reversal_of       uuid          references public.finance_entries (id),
  description       text          not null
                                  constraint finance_entries_description_check
                                  check (char_length(btrim(description)) between 2 and 200),
  amount            numeric(14,2) not null
                                  constraint finance_entries_amount_check
                                  check (amount > 0),
  currency          text          not null default 'BRL'
                                  constraint finance_entries_currency_check
                                  check (currency = 'BRL'),
  status            text          not null default 'pending'
                                  constraint finance_entries_status_check
                                  check (status in ('forecast', 'pending', 'settled', 'cancelled')),
  category_id       uuid          references public.finance_categories (id),
  client_id         uuid          references public.profiles (id) on delete set null,
  counterparty_name text          constraint finance_entries_counterparty_name_check
                                  check (counterparty_name is null
                                         or char_length(btrim(counterparty_name)) between 1 and 120),
  competence_date   date,
  due_date          date,
  settled_on        date,
  source_reference  text          constraint finance_entries_source_reference_check
                                  check (source_reference is null or char_length(source_reference) <= 200),
  notes             text          constraint finance_entries_notes_check
                                  check (notes is null or char_length(notes) <= 1000),
  idempotency_key   text          constraint finance_entries_idempotency_key_check
                                  check (idempotency_key is null
                                         or char_length(idempotency_key) between 8 and 100),
  cancelled_at      timestamptz,
  cancelled_by      uuid,
  cancel_reason     text,
  created_by        uuid,
  updated_by        uuid,
  created_at        timestamptz   not null default now(),
  updated_at        timestamptz   not null default now(),

  constraint finance_entries_settled_needs_date
    check (status <> 'settled' or settled_on is not null),
  constraint finance_entries_open_without_settlement
    check (status not in ('forecast', 'pending') or settled_on is null),
  constraint finance_entries_open_needs_due
    check (status not in ('forecast', 'pending') or due_date is not null),
  constraint finance_entries_cancel_consistency
    check ((status = 'cancelled') = (cancelled_at is not null)),
  constraint finance_entries_cancel_reason
    check (status <> 'cancelled' or char_length(btrim(coalesce(cancel_reason, ''))) >= 5),
  constraint finance_entries_reversal_link
    check ((entry_kind = 'reversal') = (reversal_of is not null)),
  constraint finance_entries_reversal_settled
    check (entry_kind <> 'reversal' or status in ('settled', 'cancelled')),
  constraint finance_entries_reversal_not_self
    check (reversal_of is distinct from id)
);

comment on table public.finance_entries is
  'Lançamentos manuais do financeiro. Nunca apagados; alterar só pelas RPCs finance_*.';
comment on column public.finance_entries.amount is
  'Valor em reais, numeric(14,2). A API expõe amount_cents = round(amount*100)::bigint.';

create unique index if not exists finance_entries_idempotency_key_uniq
  on public.finance_entries (idempotency_key)
  where idempotency_key is not null;

-- No máximo um estorno ativo (não cancelado) por lançamento.
create unique index if not exists finance_entries_active_reversal_uniq
  on public.finance_entries (reversal_of)
  where reversal_of is not null and status <> 'cancelled';

create index if not exists finance_entries_direction_status_due_idx
  on public.finance_entries (direction, status, due_date);
create index if not exists finance_entries_settled_on_idx
  on public.finance_entries (settled_on)
  where status = 'settled';
create index if not exists finance_entries_competence_date_idx
  on public.finance_entries (competence_date);
create index if not exists finance_entries_category_id_idx
  on public.finance_entries (category_id);
create index if not exists finance_entries_client_id_idx
  on public.finance_entries (client_id);
create index if not exists finance_entries_created_at_idx
  on public.finance_entries (created_at desc);

-- invoices (aditivo): o ledger filtra por vencimento e por data de pagamento.
create index if not exists idx_invoices_due_date on public.invoices (due_date);
create index if not exists idx_invoices_paid_at  on public.invoices (paid_at);

-- ── RLS e grants ────────────────────────────────────────────────────────────
alter table public.finance_categories enable row level security;
alter table public.finance_entries    enable row level security;

revoke all on table public.finance_categories from public, anon, authenticated, service_role;
revoke all on table public.finance_entries    from public, anon, authenticated, service_role;
grant select on table public.finance_categories to authenticated;
grant select on table public.finance_entries    to authenticated;

drop policy if exists finance_categories_select on public.finance_categories;
create policy finance_categories_select on public.finance_categories
  for select to authenticated
  using ((select finance_private.can_read()));

drop policy if exists finance_categories_insert on public.finance_categories;
create policy finance_categories_insert on public.finance_categories
  for insert to authenticated
  with check ((select finance_private.can_manage()));

drop policy if exists finance_categories_update on public.finance_categories;
create policy finance_categories_update on public.finance_categories
  for update to authenticated
  using ((select finance_private.can_manage()))
  with check ((select finance_private.can_manage()));

drop policy if exists finance_entries_select on public.finance_entries;
create policy finance_entries_select on public.finance_entries
  for select to authenticated
  using ((select finance_private.can_read()));

drop policy if exists finance_entries_insert on public.finance_entries;
create policy finance_entries_insert on public.finance_entries
  for insert to authenticated
  with check ((select finance_private.can_manage()));

drop policy if exists finance_entries_update on public.finance_entries;
create policy finance_entries_update on public.finance_entries
  for update to authenticated
  using ((select finance_private.can_manage()))
  with check ((select finance_private.can_manage()));

-- ── Gatilho: autoria, datas e campos imutáveis ──────────────────────────────
-- Serve as duas tabelas (ambas têm created_by, updated_by, created_at e
-- updated_at). O que difere por tabela é lido por to_jsonb(), nunca por
-- new.<coluna> de uma coluna que a outra tabela não tem.
create or replace function finance_private.touch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new        jsonb;
  v_old        jsonb;
  v_key        text;
  v_immutable  text[];
begin
  if tg_op = 'INSERT' then
    new.created_by := coalesce(new.created_by, auth.uid());
    new.created_at := now();
    new.updated_at := now();
    return new;
  end if;

  -- UPDATE
  new.updated_at := now();
  new.updated_by := auth.uid();

  v_new := to_jsonb(new);
  v_old := to_jsonb(old);

  if tg_table_name = 'finance_entries' then
    v_immutable := array['id', 'direction', 'entry_kind', 'reversal_of',
                         'created_at', 'created_by', 'idempotency_key'];
  else
    v_immutable := array['id', 'created_at', 'created_by'];
  end if;

  foreach v_key in array v_immutable loop
    if (v_new -> v_key) is distinct from (v_old -> v_key) then
      raise exception 'Campo não pode ser alterado: %', v_key
        using errcode = '22023';
    end if;
  end loop;

  -- Lançamento cancelado é final. Só client_id pode mudar (vira NULL pelo FK
  -- quando o cliente é apagado), além dos carimbos updated_at/updated_by.
  if tg_table_name = 'finance_entries'
     and (v_old ->> 'status') = 'cancelled'
     and (v_new - array['client_id', 'updated_at', 'updated_by'])
         is distinct from (v_old - array['client_id', 'updated_at', 'updated_by']) then
    raise exception 'Lançamento cancelado não pode ser alterado.'
      using errcode = '22023';
  end if;

  return new;
end;
$$;

-- ── Gatilho: nada é apagado ─────────────────────────────────────────────────
-- BEFORE DELETE (linha) e BEFORE TRUNCATE (comando). DROP TABLE não é afetado:
-- ver supabase/finance/rollback.sql.
create or replace function finance_private.block_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'finance_categories' then
    raise exception 'Categorias não são apagadas; arquive.'
      using errcode = '42501';
  end if;

  raise exception 'Lançamentos financeiros não são apagados; cancele ou estorne com motivo.'
    using errcode = '42501';
end;
$$;

-- Funções de gatilho não precisam de EXECUTE de ninguém.
revoke execute on function finance_private.touch()        from public, anon, authenticated;
revoke execute on function finance_private.block_delete() from public, anon, authenticated;

drop trigger if exists finance_categories_touch_trg on public.finance_categories;
create trigger finance_categories_touch_trg
  before insert or update on public.finance_categories
  for each row execute function finance_private.touch();

drop trigger if exists finance_entries_touch_trg on public.finance_entries;
create trigger finance_entries_touch_trg
  before insert or update on public.finance_entries
  for each row execute function finance_private.touch();

drop trigger if exists finance_categories_block_delete_trg on public.finance_categories;
create trigger finance_categories_block_delete_trg
  before delete on public.finance_categories
  for each row execute function finance_private.block_delete();

drop trigger if exists finance_categories_block_truncate_trg on public.finance_categories;
create trigger finance_categories_block_truncate_trg
  before truncate on public.finance_categories
  for each statement execute function finance_private.block_delete();

drop trigger if exists finance_entries_block_delete_trg on public.finance_entries;
create trigger finance_entries_block_delete_trg
  before delete on public.finance_entries
  for each row execute function finance_private.block_delete();

drop trigger if exists finance_entries_block_truncate_trg on public.finance_entries;
create trigger finance_entries_block_truncate_trg
  before truncate on public.finance_entries
  for each statement execute function finance_private.block_delete();
