-- Financeiro (app móvel) — 3/5: histórico de alterações (auditoria).
--
-- Contrato: docs/FINANCEIRO_DESIGN.md (seção 3.3) no repositório do app.
--
-- public.finance_audit_log é gravada só por gatilhos e não pode ser alterada,
-- apagada nem forjada (nem por postgres: o gatilho de guarda só aceita insert
-- vindo de dentro de outro gatilho).
--
-- Dois gatilhos de auditoria:
--   * finance_private.audit_row()     — ESTRITO, nas tabelas do financeiro.
--     Se a auditoria falhar, a alteração falha junto.
--   * finance_private.audit_invoice() — TOLERANTE, em public.invoices.
--     Nunca quebra o create-invoice, o payment-webhook nem o cancelamento do
--     dashboard: qualquer erro vira WARNING e a escrita segue.
--
-- Interruptor de emergência (não perde dados):
--   drop trigger if exists finance_audit_invoice_trg on public.invoices;
-- Ver supabase/finance/README.md.

-- ── Quando a auditoria começou ──────────────────────────────────────────────
create table if not exists finance_private.module_info (
  id                 boolean primary key default true constraint module_info_id_check check (id),
  audit_installed_at timestamptz not null default now()
);
insert into finance_private.module_info (id) values (true) on conflict (id) do nothing;
revoke all on table finance_private.module_info from public, anon, authenticated, service_role;

-- ── Tabela de auditoria ─────────────────────────────────────────────────────
create table if not exists public.finance_audit_log (
  id             bigint      generated always as identity primary key,
  occurred_at    timestamptz not null default now(),
  entity_type    text        not null
                             constraint finance_audit_log_entity_type_check
                             check (entity_type in ('invoice', 'finance_entry', 'finance_category',
                                                    'finance_access_grant')),
  entity_id      uuid        not null,
  action         text        not null
                             constraint finance_audit_log_action_check
                             check (action in ('insert', 'update', 'delete')),
  event          text        not null
                             constraint finance_audit_log_event_check
                             check (event in ('created', 'issued', 'corrected', 'settled', 'cancelled',
                                              'reversal_created', 'reference_cleared', 'paid', 'updated',
                                              'deleted', 'archived', 'unarchived', 'access_granted',
                                              'access_changed', 'access_removed')),
  actor_id       uuid,
  actor_role     text        not null,
  reason         text,
  changed_fields text[]      not null default '{}',
  old_values     jsonb,
  new_values     jsonb
);

comment on table public.finance_audit_log is
  'Histórico do financeiro. Gravado só por gatilhos; imutável.';

create index if not exists finance_audit_log_entity_idx
  on public.finance_audit_log (entity_type, entity_id, occurred_at desc);
create index if not exists finance_audit_log_occurred_at_idx
  on public.finance_audit_log (occurred_at desc);

alter table public.finance_audit_log enable row level security;

revoke all on table public.finance_audit_log from public, anon, authenticated, service_role;
revoke all on sequence public.finance_audit_log_id_seq from public, anon, authenticated, service_role;
grant select on table public.finance_audit_log to authenticated;

-- Quem lê o financeiro vê o histórico; o histórico de concessões só o dono e
-- a própria pessoa.
drop policy if exists finance_audit_log_select on public.finance_audit_log;
create policy finance_audit_log_select on public.finance_audit_log
  for select to authenticated
  using (
    (select finance_private.can_read())
    and (
      entity_type <> 'finance_access_grant'
      or (select finance_private.is_owner())
      or entity_id = (select auth.uid())
    )
  );

-- ── Guarda: imutável e não forjável ─────────────────────────────────────────
-- INSERT só de dentro de um gatilho de auditoria (profundidade >= 2: o gatilho
-- de auditoria é a 1, esta guarda é a 2). UPDATE, DELETE e TRUNCATE: nunca.
create or replace function finance_private.audit_log_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if pg_trigger_depth() < 2 then
      raise exception 'O histórico do financeiro é gravado só pelo banco.'
        using errcode = '42501';
    end if;
    return new;
  end if;

  raise exception 'O histórico do financeiro não pode ser alterado nem apagado.'
    using errcode = '42501';
end;
$$;

-- ── Auxiliares de snapshot ──────────────────────────────────────────────────
-- Toda linha com amount recebe amount_cents = round(amount*100)::bigint.
create or replace function finance_private.with_amount_cents(p_row jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when p_row is not null and jsonb_typeof(p_row -> 'amount') = 'number'
      then p_row || jsonb_build_object('amount_cents', round((p_row ->> 'amount')::numeric * 100)::bigint)
    else p_row
  end
$$;

-- Snapshot de invoice: só os campos financeiros.
create or replace function finance_private.invoice_snapshot(p_row jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when p_row is null then null else
    jsonb_build_object(
      'status',           p_row -> 'status',
      'amount',           p_row -> 'amount',
      'amount_cents',     case when jsonb_typeof(p_row -> 'amount') = 'number'
                               then to_jsonb(round((p_row ->> 'amount')::numeric * 100)::bigint)
                               else 'null'::jsonb end,
      'description',      p_row -> 'description',
      'due_date',         p_row -> 'due_date',
      'paid_at',          p_row -> 'paid_at',
      'client_id',        p_row -> 'client_id',
      'mp_preference_id', p_row -> 'mp_preference_id',
      'created_at',       p_row -> 'created_at'
    )
  end
$$;

-- Chaves cujo valor mudou, ignorando carimbos e o derivado amount_cents.
create or replace function finance_private.changed_keys(p_old jsonb, p_new jsonb)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(k.key order by k.key), '{}'::text[])
  from jsonb_object_keys(coalesce(p_old, '{}'::jsonb) || coalesce(p_new, '{}'::jsonb)) as k(key)
  where k.key <> all (array['updated_at', 'updated_by', 'amount_cents'])
    and (p_old -> k.key) is distinct from (p_new -> k.key)
$$;

revoke execute on function finance_private.with_amount_cents(jsonb)   from public, anon, authenticated;
revoke execute on function finance_private.invoice_snapshot(jsonb)    from public, anon, authenticated;
revoke execute on function finance_private.changed_keys(jsonb, jsonb) from public, anon, authenticated;

-- ── Auditoria estrita (tabelas do financeiro) ───────────────────────────────
-- tg_argv[0] = entity_type. Lê NEW/OLD só por to_jsonb(): o mesmo gatilho
-- serve três tabelas com colunas diferentes.
--
-- Eventos:
--   finance_entry:        insert → reversal_created (estorno) | created
--                         update → reference_cleared (só client_id → NULL)
--                                | settled (status passou a settled)
--                                | cancelled (status passou a cancelled)
--                                | corrected
--   finance_category:     insert → created
--                         update → archived (archived_at null → valor)
--                                | unarchived (valor → null) | corrected
--   finance_access_grant: insert → access_granted
--                                | access_removed (linha nova já com level
--                                  none: negativa explícita, nada concedido)
--                         update → access_removed (level passou a none)
--                                | access_changed
--                         delete → access_removed (pessoa apagada)
--   delete de lançamento/categoria nunca chega aqui (block_delete), mas
--   registraria 'deleted'.
-- UPDATE sem mudança real não é registrado.
create or replace function finance_private.audit_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type    text;
  v_old     jsonb;
  v_new     jsonb;
  v_changed text[];
  v_event   text;
  v_id      uuid;
begin
  v_type := tg_argv[0];

  if tg_op in ('UPDATE', 'DELETE') then
    v_old := finance_private.with_amount_cents(to_jsonb(old));
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_new := finance_private.with_amount_cents(to_jsonb(new));
  end if;

  if tg_op = 'UPDATE' then
    v_changed := finance_private.changed_keys(v_old, v_new);
    if cardinality(v_changed) = 0 then
      return null;
    end if;
  else
    v_changed := '{}'::text[];
  end if;

  if v_type = 'finance_access_grant' then
    v_id := (coalesce(v_new, v_old) ->> 'user_id')::uuid;
  else
    v_id := (coalesce(v_new, v_old) ->> 'id')::uuid;
  end if;

  if v_type = 'finance_entry' then
    if tg_op = 'INSERT' then
      v_event := case when (v_new ->> 'entry_kind') = 'reversal' then 'reversal_created' else 'created' end;
    elsif tg_op = 'UPDATE' then
      if v_changed = array['client_id']::text[] and jsonb_typeof(v_new -> 'client_id') = 'null' then
        v_event := 'reference_cleared';
      elsif (v_new ->> 'status') = 'settled' and (v_old ->> 'status') is distinct from 'settled' then
        v_event := 'settled';
      elsif (v_new ->> 'status') = 'cancelled' and (v_old ->> 'status') is distinct from 'cancelled' then
        v_event := 'cancelled';
      else
        v_event := 'corrected';
      end if;
    else
      v_event := 'deleted';
    end if;

  elsif v_type = 'finance_category' then
    if tg_op = 'INSERT' then
      v_event := 'created';
    elsif tg_op = 'UPDATE' then
      if jsonb_typeof(v_old -> 'archived_at') = 'null' and jsonb_typeof(v_new -> 'archived_at') <> 'null' then
        v_event := 'archived';
      elsif jsonb_typeof(v_old -> 'archived_at') <> 'null' and jsonb_typeof(v_new -> 'archived_at') = 'null' then
        v_event := 'unarchived';
      else
        v_event := 'corrected';
      end if;
    else
      v_event := 'deleted';
    end if;

  elsif v_type = 'finance_access_grant' then
    if tg_op = 'INSERT' then
      v_event := case when (v_new ->> 'level') = 'none' then 'access_removed' else 'access_granted' end;
    elsif tg_op = 'UPDATE' then
      if (v_new ->> 'level') = 'none' and (v_old ->> 'level') is distinct from 'none' then
        v_event := 'access_removed';
      else
        v_event := 'access_changed';
      end if;
    else
      v_event := 'access_removed';
    end if;

  else
    raise exception 'finance_private.audit_row: entity_type desconhecido (%)', v_type
      using errcode = '22023';
  end if;

  insert into public.finance_audit_log (
    entity_type, entity_id, action, event, actor_id, actor_role, reason,
    changed_fields, old_values, new_values
  ) values (
    v_type,
    v_id,
    lower(tg_op),
    v_event,
    auth.uid(),
    coalesce(nullif(auth.role(), ''), session_user::text),
    nullif(current_setting('pixelry.finance_change_reason', true), ''),
    v_changed,
    v_old,
    v_new
  );

  return null;
end;
$$;

-- ── Auditoria tolerante (public.invoices) ───────────────────────────────────
-- Esqueleto obrigatório do contrato: nenhum inicializador no DECLARE, toda a
-- lógica (inclusive auth.uid()/auth.role() e o insert) dentro do bloco
-- protegido, return null fora dele. Nunca levanta erro para quem escreveu.
--
-- Regras (lógica de três valores: status pode ser NULL):
--   INSERT com status draft                      → não registra
--   UPDATE com antigo e novo draft               → não registra
--   DELETE de draft                              → não registra
--   UPDATE sem mudança nos campos financeiros    → não registra
--     (ex.: só updated_at, payment_url, qr_code)
-- Eventos: insert não-draft 'created'; antigo draft → novo não-draft 'issued';
-- status passou a paid 'paid'; a cancelled 'cancelled'; outros 'updated';
-- delete 'deleted' (com o snapshot em old_values: é o que mantém a cobrança
-- no ledger depois de apagada).
create or replace function finance_private.audit_invoice()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb; v_new jsonb; v_changed text[]; v_event text;
begin
  begin
    if tg_op in ('UPDATE', 'DELETE') then
      v_old := finance_private.invoice_snapshot(to_jsonb(old));
    end if;
    if tg_op in ('INSERT', 'UPDATE') then
      v_new := finance_private.invoice_snapshot(to_jsonb(new));
    end if;

    if tg_op = 'INSERT' then
      if (v_new ->> 'status') is distinct from 'draft' then
        v_event := 'created';
        v_changed := '{}'::text[];
      end if;

    elsif tg_op = 'UPDATE' then
      if (v_old ->> 'status') is not distinct from 'draft'
         and (v_new ->> 'status') is not distinct from 'draft' then
        v_event := null;
      else
        v_changed := finance_private.changed_keys(v_old, v_new);
        if cardinality(v_changed) > 0 then
          if (v_old ->> 'status') is not distinct from 'draft' then
            v_event := 'issued';
          elsif (v_new ->> 'status') is distinct from (v_old ->> 'status')
                and (v_new ->> 'status') = 'paid' then
            v_event := 'paid';
          elsif (v_new ->> 'status') is distinct from (v_old ->> 'status')
                and (v_new ->> 'status') = 'cancelled' then
            v_event := 'cancelled';
          else
            v_event := 'updated';
          end if;
        end if;
      end if;

    elsif tg_op = 'DELETE' then
      if (v_old ->> 'status') is distinct from 'draft' then
        v_event := 'deleted';
        v_changed := '{}'::text[];
      end if;
    end if;

    if v_event is not null then
      insert into public.finance_audit_log (
        entity_type, entity_id, action, event, actor_id, actor_role, reason,
        changed_fields, old_values, new_values
      ) values (
        'invoice',
        (coalesce(to_jsonb(new), to_jsonb(old)) ->> 'id')::uuid,
        lower(tg_op),
        v_event,
        auth.uid(),
        coalesce(nullif(auth.role(), ''), session_user::text),
        nullif(current_setting('pixelry.finance_change_reason', true), ''),
        coalesce(v_changed, '{}'::text[]),
        v_old,
        v_new
      );
    end if;
  exception when others then
    raise warning 'finance_audit_invoice falhou (sqlstate %)', sqlstate;
  end;
  return null;
end $$;

revoke execute on function finance_private.audit_log_guard() from public, anon, authenticated;
revoke execute on function finance_private.audit_row()       from public, anon, authenticated;
revoke execute on function finance_private.audit_invoice()   from public, anon, authenticated;

-- ── Gatilhos ────────────────────────────────────────────────────────────────
drop trigger if exists finance_audit_log_guard_insert_trg on public.finance_audit_log;
create trigger finance_audit_log_guard_insert_trg
  before insert on public.finance_audit_log
  for each row execute function finance_private.audit_log_guard();

drop trigger if exists finance_audit_log_guard_change_trg on public.finance_audit_log;
create trigger finance_audit_log_guard_change_trg
  before update or delete on public.finance_audit_log
  for each row execute function finance_private.audit_log_guard();

drop trigger if exists finance_audit_log_guard_truncate_trg on public.finance_audit_log;
create trigger finance_audit_log_guard_truncate_trg
  before truncate on public.finance_audit_log
  for each statement execute function finance_private.audit_log_guard();

drop trigger if exists finance_entries_audit_trg on public.finance_entries;
create trigger finance_entries_audit_trg
  after insert or update or delete on public.finance_entries
  for each row execute function finance_private.audit_row('finance_entry');

drop trigger if exists finance_categories_audit_trg on public.finance_categories;
create trigger finance_categories_audit_trg
  after insert or update or delete on public.finance_categories
  for each row execute function finance_private.audit_row('finance_category');

drop trigger if exists finance_access_grants_audit_trg on public.finance_access_grants;
create trigger finance_access_grants_audit_trg
  after insert or update or delete on public.finance_access_grants
  for each row execute function finance_private.audit_row('finance_access_grant');

drop trigger if exists finance_audit_invoice_trg on public.invoices;
create trigger finance_audit_invoice_trg
  after insert or update or delete on public.invoices
  for each row execute function finance_private.audit_invoice();
