-- Financeiro (app móvel) — 4/5: RPCs de leitura e de alteração.
--
-- Contrato: docs/FINANCEIRO_DESIGN.md (seção 3.4) no repositório do app.
--
-- Todas as RPCs: SECURITY DEFINER, search_path vazio, primeira instrução é a
-- checagem de permissão, EXECUTE revogado de public e anon e concedido a
-- authenticated. Toda regra garantida por CHECK é validada antes aqui, com
-- 22023 e mensagem em pt-BR (o CHECK é a segunda trava).
--
-- Dinheiro: o banco guarda numeric(14,2); a API trafega centavos inteiros
-- (amount_cents bigint = round(amount*100)::bigint). Nunca float.
-- Datas de negócio: America/Sao_Paulo. O servidor devolve settled_on,
-- created_on, reference_date e today prontos.
--
-- Mutações gravam o motivo em pixelry.finance_change_reason (local à
-- transação) antes do DML; o gatilho de auditoria o lê. Depois do DML o
-- motivo volta a '': outro DML na mesma transação (por exemplo, uma mutação
-- GraphQL em lote que também mexa em invoices) não herda o motivo.

-- ── Auxiliares (só para as RPCs; ninguém recebe EXECUTE) ────────────────────
create or replace function finance_private.assert_can_read()
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not finance_private.can_read() then
    raise exception 'Sem acesso ao financeiro.'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function finance_private.assert_can_manage()
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not finance_private.can_manage() then
    raise exception 'Sem permissão para alterar o financeiro.'
      using errcode = '42501';
  end if;
end;
$$;

-- "Hoje" do negócio.
create or replace function finance_private.today_sp()
returns date
language sql
stable
set search_path = ''
as $$
  select (now() at time zone 'America/Sao_Paulo')::date
$$;

create or replace function finance_private.display_name(p_company text, p_full text, p_fallback text)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(nullif(btrim(p_company), ''), nullif(btrim(p_full), ''), p_fallback)
$$;

-- Nome de uma pessoa da equipe (criador, ator do histórico).
create or replace function finance_private.person_name(p_full text, p_email text)
returns text
language sql
immutable
set search_path = ''
as $$
  select coalesce(nullif(btrim(p_full), ''), nullif(btrim(p_email), ''), 'Sem nome')
$$;

-- Texto com btrim; vazio vira NULL.
create or replace function finance_private.clean_text(p_value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select nullif(btrim(p_value), '')
$$;

-- Motivo obrigatório: 5 a 500 caracteres depois do btrim.
create or replace function finance_private.require_reason(p_reason text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_reason text;
begin
  v_reason := nullif(btrim(p_reason), '');
  if v_reason is null or char_length(v_reason) < 5 then
    raise exception 'Informe um motivo com pelo menos 5 caracteres.'
      using errcode = '22023';
  end if;
  if char_length(v_reason) > 500 then
    raise exception 'O motivo pode ter no máximo 500 caracteres.'
      using errcode = '22023';
  end if;
  return v_reason;
end;
$$;

-- Motivo opcional: NULL/vazio = sem motivo; se vier, as mesmas regras.
create or replace function finance_private.optional_reason(p_reason text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if nullif(btrim(p_reason), '') is null then
    return null;
  end if;
  return finance_private.require_reason(p_reason);
end;
$$;

-- Campo de data de p_changes: JSON null → NULL; string 'YYYY-MM-DD' válida → date.
create or replace function finance_private.change_date(p_changes jsonb, p_key text)
returns date
language plpgsql
stable
set search_path = ''
as $$
declare
  v_txt  text;
  v_date date;
begin
  if jsonb_typeof(p_changes -> p_key) = 'null' then
    return null;
  end if;
  if jsonb_typeof(p_changes -> p_key) is distinct from 'string' then
    raise exception 'Data inválida em %.', p_key
      using errcode = '22023';
  end if;
  v_txt := p_changes ->> p_key;
  if v_txt !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'Data inválida em %.', p_key
      using errcode = '22023';
  end if;
  begin
    v_date := v_txt::date;
  exception when others then
    raise exception 'Data inválida em %.', p_key
      using errcode = '22023';
  end;
  return v_date;
end;
$$;

-- Campo de id de p_changes: JSON null → NULL; string uuid → uuid.
create or replace function finance_private.change_uuid(p_changes jsonb, p_key text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if jsonb_typeof(p_changes -> p_key) = 'null' then
    return null;
  end if;
  if jsonb_typeof(p_changes -> p_key) is distinct from 'string' then
    raise exception 'Identificador inválido em %.', p_key
      using errcode = '22023';
  end if;
  begin
    v_id := (p_changes ->> p_key)::uuid;
  exception when others then
    raise exception 'Identificador inválido em %.', p_key
      using errcode = '22023';
  end;
  return v_id;
end;
$$;

-- Campo de texto de p_changes: JSON null → NULL; string → btrim (vazio = NULL).
create or replace function finance_private.change_text(p_changes jsonb, p_key text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
  if jsonb_typeof(p_changes -> p_key) = 'null' then
    return null;
  end if;
  if jsonb_typeof(p_changes -> p_key) is distinct from 'string' then
    raise exception 'O campo % precisa ser um texto.', p_key
      using errcode = '22023';
  end if;
  return finance_private.clean_text(p_changes ->> p_key);
end;
$$;

-- Regras de um lançamento (criação e linha resultante da correção). Recebe
-- textos já limpos (clean_text). Espelha os CHECKs de finance_entries.
create or replace function finance_private.validate_entry(
  p_direction         text,
  p_description       text,
  p_amount_cents      bigint,
  p_status            text,
  p_due_date          date,
  p_settled_on        date,
  p_counterparty_name text,
  p_source_reference  text,
  p_notes             text
)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_direction is null or p_direction not in ('income', 'expense') then
    raise exception 'Tipo de lançamento inválido. Use income (receita) ou expense (despesa).'
      using errcode = '22023';
  end if;

  if p_description is null or char_length(p_description) not between 2 and 200 then
    raise exception 'A descrição precisa ter de 2 a 200 caracteres.'
      using errcode = '22023';
  end if;

  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'O valor precisa ser maior que zero.'
      using errcode = '22023';
  end if;
  if p_amount_cents > 99999999999999 then
    raise exception 'O valor passa do limite permitido.'
      using errcode = '22023';
  end if;

  if p_status is null or p_status not in ('forecast', 'pending', 'settled') then
    raise exception 'Situação inválida. Use forecast, pending ou settled.'
      using errcode = '22023';
  end if;

  if p_status in ('forecast', 'pending') then
    if p_due_date is null then
      raise exception 'Informe o vencimento do lançamento em aberto.'
        using errcode = '22023';
    end if;
    if p_settled_on is not null then
      raise exception 'Lançamento em aberto não tem data de pagamento.'
        using errcode = '22023';
    end if;
  else
    if p_settled_on is null then
      raise exception 'Informe a data de pagamento.'
        using errcode = '22023';
    end if;
    if p_settled_on > finance_private.today_sp() then
      raise exception 'A data de pagamento não pode ser futura.'
        using errcode = '22023';
    end if;
  end if;

  if p_counterparty_name is not null and char_length(p_counterparty_name) > 120 then
    raise exception 'O nome do cliente ou fornecedor pode ter no máximo 120 caracteres.'
      using errcode = '22023';
  end if;
  if p_source_reference is not null and char_length(p_source_reference) > 200 then
    raise exception 'A referência pode ter no máximo 200 caracteres.'
      using errcode = '22023';
  end if;
  if p_notes is not null and char_length(p_notes) > 1000 then
    raise exception 'As observações podem ter no máximo 1000 caracteres.'
      using errcode = '22023';
  end if;
end;
$$;

-- Categoria utilizável por um lançamento da direção dada.
create or replace function finance_private.check_category(p_category_id uuid, p_direction text)
returns void
language plpgsql
stable
set search_path = ''
as $$
declare
  v_applies_to  text;
  v_archived_at timestamptz;
begin
  select c.applies_to, c.archived_at
    into v_applies_to, v_archived_at
  from public.finance_categories c
  where c.id = p_category_id;

  if not found then
    raise exception 'Categoria não encontrada.'
      using errcode = '22023';
  end if;
  if v_archived_at is not null then
    raise exception 'Esta categoria está arquivada.'
      using errcode = '22023';
  end if;
  if v_applies_to is null or v_applies_to not in (p_direction, 'both') then
    raise exception 'Esta categoria não vale para este tipo de lançamento.'
      using errcode = '22023';
  end if;
end;
$$;

-- Nome atual de um cliente (profile com role client). Recusa quem não é cliente.
-- Sem empresa nem nome → 'Cliente sem nome' (como no ledger), nunca o e-mail:
-- o snapshot fica em counterparty_name e quem só lê o financeiro o vê.
create or replace function finance_private.client_label(p_client_id uuid)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_role text;
  v_name text;
begin
  select p.role,
         finance_private.display_name(p.company_name, p.full_name, 'Cliente sem nome')
    into v_role, v_name
  from public.profiles p
  where p.id = p_client_id;

  if not found or v_role is distinct from 'client' then
    raise exception 'O cliente informado não é um cliente cadastrado.'
      using errcode = '22023';
  end if;
  return left(v_name, 120);
end;
$$;

revoke execute on function finance_private.assert_can_read()                       from public, anon, authenticated;
revoke execute on function finance_private.assert_can_manage()                     from public, anon, authenticated;
revoke execute on function finance_private.today_sp()                              from public, anon, authenticated;
revoke execute on function finance_private.display_name(text, text, text)          from public, anon, authenticated;
revoke execute on function finance_private.person_name(text, text)                 from public, anon, authenticated;
revoke execute on function finance_private.clean_text(text)                        from public, anon, authenticated;
revoke execute on function finance_private.require_reason(text)                    from public, anon, authenticated;
revoke execute on function finance_private.optional_reason(text)                   from public, anon, authenticated;
revoke execute on function finance_private.change_date(jsonb, text)                from public, anon, authenticated;
revoke execute on function finance_private.change_uuid(jsonb, text)                from public, anon, authenticated;
revoke execute on function finance_private.change_text(jsonb, text)                from public, anon, authenticated;
revoke execute on function finance_private.validate_entry(text, text, bigint, text, date, date, text, text, text)
  from public, anon, authenticated;
revoke execute on function finance_private.check_category(uuid, text)              from public, anon, authenticated;
revoke execute on function finance_private.client_label(uuid)                      from public, anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- Leitura (exigem can_read, exceto finance_clients, que exige can_manage)
-- ════════════════════════════════════════════════════════════════════════════

-- Ledger: invoices vivas + invoices apagadas (pela auditoria) + lançamentos.
--
-- Status de invoice, nesta ordem: draft fica fora; NULL → invalid;
-- não-paid com paid_at → invalid; paid → settled (sem paid_at: settled com
-- settled_on NULL); pending/overdue → pending; cancelled → cancelled;
-- qualquer outro (inclusive error) → invalid.
--
-- Janela: ambos NULL → tudo. Só um NULL, ou p_from > p_to → 22023. Com
-- janela, entram os abertos (forecast/pending) sempre, e o resto se due_date,
-- settled_on, competence_date ou created_on estiver em [p_from, p_to].
create or replace function public.finance_ledger(p_from date default null, p_to date default null)
returns table (
  source               text,
  id                   uuid,
  direction            text,
  entry_kind           text,
  reversal_of          uuid,
  reversed_by_id       uuid,
  description          text,
  amount_cents         bigint,
  status               text,
  source_status        text,
  category_id          uuid,
  category_name        text,
  client_id            uuid,
  counterparty_name    text,
  competence_date      date,
  due_date             date,
  settled_on           date,
  settled_at           timestamptz,
  created_at           timestamptz,
  created_on           date,
  updated_at           timestamptz,
  reference_date       date,
  created_by_name      text,
  source_reference     text,
  notes                text,
  cancel_reason        text,
  has_payment_link     boolean,
  is_deleted_at_source boolean,
  total_rows           bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform finance_private.assert_can_read();

  if (p_from is null) <> (p_to is null) then
    raise exception 'Informe o início e o fim do período.'
      using errcode = '22023';
  end if;
  if p_from > p_to then
    raise exception 'O início do período não pode ser depois do fim.'
      using errcode = '22023';
  end if;

  return query
  select
    v.source, v.id, v.direction, v.entry_kind, v.reversal_of, v.reversed_by_id,
    v.description, v.amount_cents, v.status, v.source_status,
    v.category_id, v.category_name, v.client_id, v.counterparty_name,
    v.competence_date, v.due_date, v.settled_on, v.settled_at,
    v.created_at, v.created_on, v.updated_at, v.reference_date,
    v.created_by_name, v.source_reference, v.notes, v.cancel_reason,
    v.has_payment_link, v.is_deleted_at_source, v.total_rows
  from (
    select
      u.source, u.id, u.direction, u.entry_kind, u.reversal_of, u.reversed_by_id,
      u.description, u.amount_cents, u.status, u.source_status,
      u.category_id, u.category_name, u.client_id, u.counterparty_name,
      u.competence_date, u.due_date, u.settled_on, u.settled_at,
      u.created_at, u.created_on, u.updated_at,
      coalesce(u.settled_on, u.due_date, u.competence_date, u.created_on) as reference_date,
      u.created_by_name, u.source_reference, u.notes, u.cancel_reason,
      u.has_payment_link, u.is_deleted_at_source,
      count(*) over () as total_rows
    from (
      -- 1. Cobranças do Mercado Pago (vivas)
      select
        'invoice'::text                                                  as source,
        i.id                                                             as id,
        'income'::text                                                   as direction,
        'regular'::text                                                  as entry_kind,
        null::uuid                                                       as reversal_of,
        null::uuid                                                       as reversed_by_id,
        i.description                                                    as description,
        round(i.amount * 100)::bigint                                    as amount_cents,
        case
          when i.status is null                           then 'invalid'
          when i.status <> 'paid' and i.paid_at is not null then 'invalid'
          when i.status = 'paid'                          then 'settled'
          when i.status in ('pending', 'overdue')         then 'pending'
          when i.status = 'cancelled'                     then 'cancelled'
          else 'invalid'
        end::text                                                        as status,
        i.status                                                         as source_status,
        null::uuid                                                       as category_id,
        null::text                                                       as category_name,
        i.client_id                                                      as client_id,
        finance_private.display_name(cp.company_name, cp.full_name, 'Cliente sem nome')
                                                                         as counterparty_name,
        null::date                                                       as competence_date,
        i.due_date                                                       as due_date,
        (i.paid_at at time zone 'America/Sao_Paulo')::date               as settled_on,
        i.paid_at                                                        as settled_at,
        i.created_at                                                     as created_at,
        (coalesce(i.created_at, i.updated_at, i.paid_at) at time zone 'America/Sao_Paulo')::date
                                                                         as created_on,
        i.updated_at                                                     as updated_at,
        null::text                                                       as created_by_name,
        i.mp_preference_id                                               as source_reference,
        null::text                                                       as notes,
        null::text                                                       as cancel_reason,
        (i.payment_url is not null)                                      as has_payment_link,
        false                                                            as is_deleted_at_source
      from public.invoices i
      left join public.profiles cp on cp.id = i.client_id
      where i.status is distinct from 'draft'

      union all

      -- 2. Cobranças apagadas (snapshot do evento 'deleted' mais recente,
      --    só se não houver invoice viva com o mesmo id)
      select
        'invoice'::text,
        d.entity_id,
        'income'::text,
        'regular'::text,
        null::uuid,
        null::uuid,
        coalesce(d.old_values ->> 'description', 'Cobrança apagada'),
        coalesce((d.old_values ->> 'amount_cents')::bigint,
                 round((d.old_values ->> 'amount')::numeric * 100)::bigint,
                 0::bigint),
        case
          when (d.old_values ->> 'status') = 'paid' and (d.old_values ->> 'paid_at') is not null
            then 'settled'
          else 'cancelled'
        end::text,
        'deleted'::text,
        null::uuid,
        null::text,
        (d.old_values ->> 'client_id')::uuid,
        case
          when dp.id is not null
            then finance_private.display_name(dp.company_name, dp.full_name, 'Cliente sem nome')
          else 'Cliente removido'
        end,
        null::date,
        (d.old_values ->> 'due_date')::date,
        ((d.old_values ->> 'paid_at')::timestamptz at time zone 'America/Sao_Paulo')::date,
        (d.old_values ->> 'paid_at')::timestamptz,
        (d.old_values ->> 'created_at')::timestamptz,
        (coalesce((d.old_values ->> 'created_at')::timestamptz,
                  d.occurred_at,
                  (d.old_values ->> 'paid_at')::timestamptz) at time zone 'America/Sao_Paulo')::date,
        d.occurred_at,
        null::text,
        d.old_values ->> 'mp_preference_id',
        null::text,
        null::text,
        false,
        true
      from (
        select distinct on (a.entity_id)
          a.entity_id, a.occurred_at, a.old_values
        from public.finance_audit_log a
        where a.entity_type = 'invoice'
          and a.event = 'deleted'
          and not exists (select 1 from public.invoices li where li.id = a.entity_id)
        order by a.entity_id, a.occurred_at desc, a.id desc
      ) d
      left join public.profiles dp on dp.id = (d.old_values ->> 'client_id')::uuid

      union all

      -- 3. Lançamentos manuais
      select
        'manual'::text,
        e.id,
        e.direction,
        e.entry_kind,
        e.reversal_of,
        r.id,
        e.description,
        round(e.amount * 100)::bigint,
        e.status,
        e.status,
        e.category_id,
        c.name,
        e.client_id,
        coalesce(e.counterparty_name,
                 finance_private.display_name(ep.company_name, ep.full_name, null)),
        e.competence_date,
        e.due_date,
        e.settled_on,
        null::timestamptz,
        e.created_at,
        (coalesce(e.created_at, e.updated_at) at time zone 'America/Sao_Paulo')::date,
        e.updated_at,
        case
          when e.created_by is null then 'Administração do banco'
          when cb.id is null        then 'Pessoa removida'
          else finance_private.person_name(cb.full_name, cb.email)
        end,
        e.source_reference,
        e.notes,
        e.cancel_reason,
        false,
        false
      from public.finance_entries e
      left join public.finance_entries r
        on r.reversal_of = e.id and r.status <> 'cancelled'
      left join public.finance_categories c on c.id = e.category_id
      left join public.profiles ep on ep.id = e.client_id
      left join public.profiles cb on cb.id = e.created_by
    ) u
    where p_from is null
       or u.status in ('forecast', 'pending')
       or u.due_date        between p_from and p_to
       or u.settled_on      between p_from and p_to
       or u.competence_date between p_from and p_to
       or u.created_on      between p_from and p_to
  ) v
  order by v.reference_date desc nulls last, v.created_at desc nulls last, v.source, v.id;
end;
$$;

-- Metadados da tela. Não é set-returning: o PostgREST devolve um objeto.
create or replace function public.finance_overview_meta(
  out first_record_on       date,
  out last_change_at        timestamptz,
  out audit_installed_at    timestamptz,
  out today                 date,
  out invoice_count         bigint,
  out deleted_invoice_count bigint,
  out entry_count           bigint,
  out expense_count         bigint,
  out category_count        bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform finance_private.assert_can_read();

  select
    least(
      (select min(least(
                i.due_date,
                (i.paid_at at time zone 'America/Sao_Paulo')::date,
                (coalesce(i.created_at, i.updated_at, i.paid_at) at time zone 'America/Sao_Paulo')::date))
         from public.invoices i
        where i.status is distinct from 'draft'),
      (select min(least(
                e.due_date,
                e.settled_on,
                e.competence_date,
                (coalesce(e.created_at, e.updated_at) at time zone 'America/Sao_Paulo')::date))
         from public.finance_entries e)
    ),
    greatest(
      (select max(a.occurred_at) from public.finance_audit_log a),
      (select max(i.updated_at) from public.invoices i where i.status is distinct from 'draft'),
      (select max(e.updated_at) from public.finance_entries e)
    ),
    (select m.audit_installed_at from finance_private.module_info m where m.id),
    finance_private.today_sp(),
    (select count(*) from public.invoices i where i.status is distinct from 'draft'),
    (select count(distinct a.entity_id)
       from public.finance_audit_log a
      where a.entity_type = 'invoice'
        and a.event = 'deleted'
        and not exists (select 1 from public.invoices li where li.id = a.entity_id)),
    (select count(*) from public.finance_entries e),
    (select count(*) from public.finance_entries e
      where e.direction = 'expense' and e.status <> 'cancelled'),
    (select count(*) from public.finance_categories c where c.archived_at is null)
  into first_record_on, last_change_at, audit_installed_at, today, invoice_count,
       deleted_invoice_count, entry_count, expense_count, category_count;
end;
$$;

-- Histórico de um item do ledger. 'invoice' → entity_type invoice;
-- 'manual' → finance_entry.
create or replace function public.finance_entry_history(p_source text, p_id uuid)
returns table (
  id             bigint,
  occurred_at    timestamptz,
  event          text,
  action         text,
  actor_name     text,
  actor_role     text,
  reason         text,
  changed_fields text[],
  old_values     jsonb,
  new_values     jsonb,
  total_rows     bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_entity_type text;
begin
  perform finance_private.assert_can_read();

  v_entity_type := case p_source
                     when 'invoice' then 'invoice'
                     when 'manual'  then 'finance_entry'
                   end;
  if v_entity_type is null then
    raise exception 'Origem inválida. Use invoice ou manual.'
      using errcode = '22023';
  end if;

  return query
  select
    a.id,
    a.occurred_at,
    a.event,
    a.action,
    case
      when a.actor_id is not null and ap.id is not null
        then finance_private.person_name(ap.full_name, ap.email)
      when a.actor_id is not null
        then 'Pessoa removida'
      when a.actor_role = 'service_role'
        then 'Sistema (Mercado Pago / Edge Function)'
      else 'Administração do banco'
    end,
    a.actor_role,
    a.reason,
    a.changed_fields,
    a.old_values,
    a.new_values,
    count(*) over ()
  from public.finance_audit_log a
  left join public.profiles ap on ap.id = a.actor_id
  where a.entity_type = v_entity_type
    and a.entity_id = p_id
  order by a.occurred_at desc, a.id desc;
end;
$$;

-- Clientes para o formulário de lançamento. Exige can_manage.
create or replace function public.finance_clients()
returns table (
  id           uuid,
  display_name text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  perform finance_private.assert_can_manage();

  return query
  select
    p.id,
    finance_private.display_name(p.company_name, p.full_name,
                                 coalesce(nullif(btrim(p.email), ''), 'Cliente sem nome'))
  from public.profiles p
  where p.role = 'client'
  order by 2, 1;
end;
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- Alteração (exigem can_manage)
-- ════════════════════════════════════════════════════════════════════════════

-- Cria um lançamento regular. Idempotente por p_idempotency_key: mesma chave
-- com os mesmos dados (direção, valor, descrição) devolve o mesmo id; com
-- outros dados → 23505.
create or replace function public.finance_create_entry(
  p_direction         text,
  p_description       text,
  p_amount_cents      bigint,
  p_status            text,
  p_due_date          date default null,
  p_settled_on        date default null,
  p_competence_date   date default null,
  p_category_id       uuid default null,
  p_client_id         uuid default null,
  p_counterparty_name text default null,
  p_source_reference  text default null,
  p_notes             text default null,
  p_idempotency_key   text default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_description  text;
  v_counterparty text;
  v_reference    text;
  v_notes        text;
  v_key          text;
  v_client_name  text;
  v_amount       numeric(14,2);
  v_id           uuid;
  v_ex_id        uuid;
  v_ex_direction text;
  v_ex_amount    numeric;
  v_ex_desc      text;
begin
  perform finance_private.assert_can_manage();

  v_description  := finance_private.clean_text(p_description);
  v_counterparty := finance_private.clean_text(p_counterparty_name);
  v_reference    := finance_private.clean_text(p_source_reference);
  v_notes        := finance_private.clean_text(p_notes);
  v_key          := finance_private.clean_text(p_idempotency_key);

  perform finance_private.validate_entry(
    p_direction, v_description, p_amount_cents, p_status,
    p_due_date, p_settled_on, v_counterparty, v_reference, v_notes);

  if v_key is not null and char_length(v_key) not between 8 and 100 then
    raise exception 'Chave de envio inválida (use de 8 a 100 caracteres).'
      using errcode = '22023';
  end if;

  if p_category_id is not null then
    perform finance_private.check_category(p_category_id, p_direction);
  end if;

  if p_client_id is not null then
    -- Recusa quem não é cliente SEMPRE, mesmo com contraparte informada
    -- (client_label fora do coalesce, que não avaliaria o segundo argumento);
    -- sem contraparte, grava o nome atual do cliente (snapshot que sobrevive
    -- à exclusão do cliente).
    v_client_name  := finance_private.client_label(p_client_id);
    v_counterparty := coalesce(v_counterparty, v_client_name);
  end if;

  v_amount := p_amount_cents::numeric / 100;

  perform set_config('pixelry.finance_change_reason', '', true);

  insert into public.finance_entries as e (
    direction, entry_kind, description, amount, currency, status,
    category_id, client_id, counterparty_name,
    competence_date, due_date, settled_on,
    source_reference, notes, idempotency_key
  ) values (
    p_direction, 'regular', v_description, v_amount, 'BRL', p_status,
    p_category_id, p_client_id, v_counterparty,
    p_competence_date, p_due_date, p_settled_on,
    v_reference, v_notes, v_key
  )
  on conflict (idempotency_key) where idempotency_key is not null do nothing
  returning e.id into v_id;

  if v_id is not null then
    return v_id;
  end if;

  -- Conflito de chave: mesma chave, mesmos dados → mesmo id.
  select x.id, x.direction, x.amount, x.description
    into v_ex_id, v_ex_direction, v_ex_amount, v_ex_desc
  from public.finance_entries x
  where x.idempotency_key = v_key;

  if v_ex_id is not null
     and v_ex_direction = p_direction
     and v_ex_amount = v_amount
     and btrim(v_ex_desc) = v_description then
    return v_ex_id;
  end if;

  raise exception 'Esta chave de envio já foi usada com outros dados.'
    using errcode = '23505';
end;
$$;

-- Corrige campos de um lançamento. p_changes: objeto JSON com chaves
-- snake_case; ausente = mantém, JSON null = limpa (se a coluna permitir).
create or replace function public.finance_correct_entry(p_id uuid, p_changes jsonb, p_reason text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_reason       text;
  v_row          public.finance_entries%rowtype;
  v_bad_key      text;
  v_num          numeric;
  v_old_cents    bigint;
  v_description  text;
  v_amount_cents bigint;
  v_status       text;
  v_due_date     date;
  v_settled_on   date;
  v_competence   date;
  v_category_id  uuid;
  v_client_id    uuid;
  v_counterparty text;
  v_reference    text;
  v_notes        text;
  v_rev_cents    bigint;
  v_rev_settled  date;
  v_orig_settled date;
begin
  perform finance_private.assert_can_manage();

  v_reason := finance_private.require_reason(p_reason);

  if p_changes is null or jsonb_typeof(p_changes) is distinct from 'object' or p_changes = '{}'::jsonb then
    raise exception 'Informe ao menos um campo para corrigir.'
      using errcode = '22023';
  end if;

  select k.key into v_bad_key
  from jsonb_object_keys(p_changes) as k(key)
  where k.key <> all (array[
    'description', 'amount_cents', 'status', 'due_date', 'settled_on', 'competence_date',
    'category_id', 'client_id', 'counterparty_name', 'source_reference', 'notes'
  ])
  order by k.key
  limit 1;

  if v_bad_key is not null then
    raise exception 'Campo não pode ser corrigido: %', v_bad_key
      using errcode = '22023';
  end if;

  select e.* into v_row
  from public.finance_entries e
  where e.id = p_id
  for update;

  if not found then
    raise exception 'Lançamento não encontrado.'
      using errcode = 'P0002';
  end if;
  if v_row.status = 'cancelled' then
    raise exception 'Lançamento cancelado não pode ser corrigido.'
      using errcode = '22023';
  end if;

  -- Ponto de partida: a linha atual.
  v_old_cents    := round(v_row.amount * 100)::bigint;
  v_description  := v_row.description;
  v_amount_cents := v_old_cents;
  v_status       := v_row.status;
  v_due_date     := v_row.due_date;
  v_settled_on   := v_row.settled_on;
  v_competence   := v_row.competence_date;
  v_category_id  := v_row.category_id;
  v_client_id    := v_row.client_id;
  v_counterparty := v_row.counterparty_name;
  v_reference    := v_row.source_reference;
  v_notes        := v_row.notes;

  if p_changes ? 'description' then
    if jsonb_typeof(p_changes -> 'description') is distinct from 'string' then
      raise exception 'A descrição precisa ser um texto.'
        using errcode = '22023';
    end if;
    v_description := finance_private.clean_text(p_changes ->> 'description');
  end if;

  if p_changes ? 'amount_cents' then
    if jsonb_typeof(p_changes -> 'amount_cents') is distinct from 'number' then
      raise exception 'O valor (amount_cents) precisa ser um número inteiro de centavos.'
        using errcode = '22023';
    end if;
    v_num := (p_changes ->> 'amount_cents')::numeric;
    if v_num <> trunc(v_num) or v_num <= 0 then
      raise exception 'O valor (amount_cents) precisa ser um número inteiro de centavos maior que zero.'
        using errcode = '22023';
    end if;
    if v_num > 99999999999999 then
      raise exception 'O valor passa do limite permitido.'
        using errcode = '22023';
    end if;
    v_amount_cents := v_num::bigint;
  end if;

  if p_changes ? 'status' then
    if jsonb_typeof(p_changes -> 'status') is distinct from 'string'
       or (p_changes ->> 'status') not in ('forecast', 'pending', 'settled') then
      raise exception 'Situação inválida. Use forecast, pending ou settled (para cancelar ou estornar, use a ação própria).'
        using errcode = '22023';
    end if;
    v_status := p_changes ->> 'status';
  end if;

  if p_changes ? 'due_date' then
    v_due_date := finance_private.change_date(p_changes, 'due_date');
  end if;
  if p_changes ? 'settled_on' then
    v_settled_on := finance_private.change_date(p_changes, 'settled_on');
  end if;
  if p_changes ? 'competence_date' then
    v_competence := finance_private.change_date(p_changes, 'competence_date');
  end if;
  if p_changes ? 'category_id' then
    v_category_id := finance_private.change_uuid(p_changes, 'category_id');
  end if;
  if p_changes ? 'client_id' then
    v_client_id := finance_private.change_uuid(p_changes, 'client_id');
  end if;
  if p_changes ? 'counterparty_name' then
    v_counterparty := finance_private.change_text(p_changes, 'counterparty_name');
  end if;
  if p_changes ? 'source_reference' then
    v_reference := finance_private.change_text(p_changes, 'source_reference');
  end if;
  if p_changes ? 'notes' then
    v_notes := finance_private.change_text(p_changes, 'notes');
  end if;

  -- Estorno não muda situação nem valor.
  if v_row.entry_kind = 'reversal'
     and (v_status is distinct from v_row.status or v_amount_cents is distinct from v_old_cents) then
    raise exception 'Estorno não muda situação nem valor. Para desfazer, cancele o estorno.'
      using errcode = '22023';
  end if;

  -- Reabrir exige limpar a data de pagamento no próprio payload.
  if v_row.status = 'settled'
     and v_status in ('forecast', 'pending')
     and not (p_changes ? 'settled_on' and jsonb_typeof(p_changes -> 'settled_on') = 'null') then
    raise exception 'Remova a data de pagamento ao reabrir o lançamento.'
      using errcode = '22023';
  end if;

  -- Cliente: novo vínculo precisa ser cliente; sem contraparte, grava o nome.
  if v_client_id is not null and v_client_id is distinct from v_row.client_id then
    if not (p_changes ? 'counterparty_name') or v_counterparty is null then
      v_counterparty := finance_private.client_label(v_client_id);
    else
      perform finance_private.client_label(v_client_id);
    end if;
  elsif v_client_id is not null and v_counterparty is null then
    select left(finance_private.display_name(p.company_name, p.full_name, 'Cliente sem nome'), 120)
      into v_counterparty
    from public.profiles p
    where p.id = v_client_id;
  end if;

  -- Categoria: só valida quando muda (uma categoria arquivada depois não
  -- impede corrigir outros campos).
  if v_category_id is not null and v_category_id is distinct from v_row.category_id then
    perform finance_private.check_category(v_category_id, v_row.direction);
  end if;

  -- A linha resultante passa pelas mesmas regras da criação.
  perform finance_private.validate_entry(
    v_row.direction, v_description, v_amount_cents, v_status,
    v_due_date, v_settled_on, v_counterparty, v_reference, v_notes);

  if v_row.entry_kind = 'regular' then
    select round(r.amount * 100)::bigint, r.settled_on
      into v_rev_cents, v_rev_settled
    from public.finance_entries r
    where r.reversal_of = v_row.id
      and r.status <> 'cancelled';

    if v_rev_cents is not null then
      if v_status is distinct from 'settled' then
        raise exception 'Lançamento com estorno ativo precisa continuar pago; cancele o estorno antes.'
          using errcode = '22023';
      end if;
      if v_amount_cents < v_rev_cents then
        raise exception 'O valor não pode ficar menor que o do estorno.'
          using errcode = '22023';
      end if;
      if v_settled_on > v_rev_settled then
        raise exception 'A data de pagamento não pode ficar depois da data do estorno.'
          using errcode = '22023';
      end if;
    end if;
  else
    select o.settled_on into v_orig_settled
    from public.finance_entries o
    where o.id = v_row.reversal_of;

    if v_settled_on < v_orig_settled then
      raise exception 'A data do estorno não pode ser anterior ao pagamento original.'
        using errcode = '22023';
    end if;
  end if;

  -- Sem mudança efetiva → nada a fazer.
  if v_description   is not distinct from v_row.description
     and v_amount_cents  =                v_old_cents
     and v_status        is not distinct from v_row.status
     and v_due_date      is not distinct from v_row.due_date
     and v_settled_on    is not distinct from v_row.settled_on
     and v_competence    is not distinct from v_row.competence_date
     and v_category_id   is not distinct from v_row.category_id
     and v_client_id     is not distinct from v_row.client_id
     and v_counterparty  is not distinct from v_row.counterparty_name
     and v_reference     is not distinct from v_row.source_reference
     and v_notes         is not distinct from v_row.notes then
    return;
  end if;

  perform set_config('pixelry.finance_change_reason', v_reason, true);

  update public.finance_entries e
     set description       = v_description,
         amount            = v_amount_cents::numeric / 100,
         status            = v_status,
         due_date          = v_due_date,
         settled_on        = v_settled_on,
         competence_date   = v_competence,
         category_id       = v_category_id,
         client_id         = v_client_id,
         counterparty_name = v_counterparty,
         source_reference  = v_reference,
         notes             = v_notes
   where e.id = p_id;

  perform set_config('pixelry.finance_change_reason', '', true);
end;
$$;

-- Marca como pago/recebido. Só de forecast/pending; data obrigatória e não futura.
create or replace function public.finance_settle_entry(p_id uuid, p_settled_on date, p_reason text default null)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_reason text;
  v_status text;
begin
  perform finance_private.assert_can_manage();

  v_reason := finance_private.optional_reason(p_reason);

  if p_settled_on is null then
    raise exception 'Informe a data de pagamento.'
      using errcode = '22023';
  end if;
  if p_settled_on > finance_private.today_sp() then
    raise exception 'A data de pagamento não pode ser futura.'
      using errcode = '22023';
  end if;

  select e.status into v_status
  from public.finance_entries e
  where e.id = p_id
  for update;

  if not found then
    raise exception 'Lançamento não encontrado.'
      using errcode = 'P0002';
  end if;
  if v_status is null or v_status not in ('forecast', 'pending') then
    raise exception 'Só lançamentos previstos ou pendentes podem ser marcados como pagos.'
      using errcode = '22023';
  end if;

  perform set_config('pixelry.finance_change_reason', coalesce(v_reason, ''), true);

  update public.finance_entries e
     set status     = 'settled',
         settled_on = p_settled_on
   where e.id = p_id;

  perform set_config('pixelry.finance_change_reason', '', true);
end;
$$;

-- Cancela (o registro não valeu). Final: depois disso a linha não muda mais.
create or replace function public.finance_cancel_entry(p_id uuid, p_reason text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_reason text;
  v_status text;
begin
  perform finance_private.assert_can_manage();

  v_reason := finance_private.require_reason(p_reason);

  select e.status into v_status
  from public.finance_entries e
  where e.id = p_id
  for update;

  if not found then
    raise exception 'Lançamento não encontrado.'
      using errcode = 'P0002';
  end if;
  if v_status = 'cancelled' then
    raise exception 'Este lançamento já está cancelado.'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.finance_entries r
    where r.reversal_of = p_id
      and r.status <> 'cancelled'
  ) then
    raise exception 'Cancele o estorno antes.'
      using errcode = '22023';
  end if;

  perform set_config('pixelry.finance_change_reason', v_reason, true);

  update public.finance_entries e
     set status        = 'cancelled',
         cancelled_at  = now(),
         cancelled_by  = auth.uid(),
         cancel_reason = v_reason
   where e.id = p_id;

  perform set_config('pixelry.finance_change_reason', '', true);
end;
$$;

-- Estorna (o dinheiro voltou). Cria uma linha 'reversal' com a mesma direção,
-- liquidada na data do estorno; o original continua 'settled'. Para desfazer,
-- cancele o estorno.
create or replace function public.finance_reverse_entry(
  p_id           uuid,
  p_reversed_on  date,
  p_reason       text,
  p_amount_cents bigint default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_reason     text;
  v_orig       public.finance_entries%rowtype;
  v_orig_cents bigint;
  v_cents      bigint;
  v_id         uuid;
begin
  perform finance_private.assert_can_manage();

  v_reason := finance_private.require_reason(p_reason);

  if p_reversed_on is null then
    raise exception 'Informe a data do estorno.'
      using errcode = '22023';
  end if;

  select e.* into v_orig
  from public.finance_entries e
  where e.id = p_id
  for update;

  if not found then
    raise exception 'Lançamento não encontrado.'
      using errcode = 'P0002';
  end if;
  if v_orig.entry_kind is distinct from 'regular' then
    raise exception 'Não é possível estornar um estorno.'
      using errcode = '22023';
  end if;
  if v_orig.status is distinct from 'settled' then
    raise exception 'Só lançamentos pagos ou recebidos podem ser estornados.'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.finance_entries r
    where r.reversal_of = p_id
      and r.status <> 'cancelled'
  ) then
    raise exception 'Este lançamento já tem um estorno ativo.'
      using errcode = '22023';
  end if;
  if p_reversed_on < v_orig.settled_on then
    raise exception 'A data do estorno não pode ser anterior ao pagamento original.'
      using errcode = '22023';
  end if;
  if p_reversed_on > finance_private.today_sp() then
    raise exception 'A data de pagamento não pode ser futura.'
      using errcode = '22023';
  end if;

  v_orig_cents := round(v_orig.amount * 100)::bigint;
  v_cents := coalesce(p_amount_cents, v_orig_cents);
  if v_cents <= 0 or v_cents > v_orig_cents then
    raise exception 'O valor do estorno precisa ser maior que zero e no máximo o valor original.'
      using errcode = '22023';
  end if;

  perform set_config('pixelry.finance_change_reason', v_reason, true);

  insert into public.finance_entries as e (
    direction, entry_kind, reversal_of, description, amount, currency, status,
    category_id, client_id, counterparty_name, settled_on, notes
  ) values (
    v_orig.direction, 'reversal', p_id, left('Estorno: ' || v_orig.description, 200),
    v_cents::numeric / 100, 'BRL', 'settled',
    v_orig.category_id, v_orig.client_id, v_orig.counterparty_name, p_reversed_on, v_reason
  )
  returning e.id into v_id;

  perform set_config('pixelry.finance_change_reason', '', true);

  return v_id;
end;
$$;

-- Cria categoria. Nome duplicado (sem diferenciar maiúsculas) → 23505.
create or replace function public.finance_create_category(p_name text, p_applies_to text default 'both')
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_id   uuid;
begin
  perform finance_private.assert_can_manage();

  v_name := finance_private.clean_text(p_name);
  if v_name is null or char_length(v_name) not between 2 and 60 then
    raise exception 'O nome da categoria precisa ter de 2 a 60 caracteres.'
      using errcode = '22023';
  end if;
  if p_applies_to is null or p_applies_to not in ('income', 'expense', 'both') then
    raise exception 'Tipo de categoria inválido. Use income, expense ou both.'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from public.finance_categories c where lower(btrim(c.name)) = lower(v_name)
  ) then
    raise exception 'Já existe uma categoria com esse nome.'
      using errcode = '23505';
  end if;

  perform set_config('pixelry.finance_change_reason', '', true);

  begin
    insert into public.finance_categories as c (name, applies_to)
    values (v_name, p_applies_to)
    returning c.id into v_id;
  exception when unique_violation then
    raise exception 'Já existe uma categoria com esse nome.'
      using errcode = '23505';
  end;

  return v_id;
end;
$$;

-- Arquiva ou reativa uma categoria. Já no estado pedido → nada a fazer.
create or replace function public.finance_set_category_archived(p_id uuid, p_archived boolean, p_reason text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_reason      text;
  v_archived_at timestamptz;
begin
  perform finance_private.assert_can_manage();

  v_reason := finance_private.require_reason(p_reason);

  if p_archived is null then
    raise exception 'Informe se a categoria deve ser arquivada ou reativada.'
      using errcode = '22023';
  end if;

  select c.archived_at into v_archived_at
  from public.finance_categories c
  where c.id = p_id
  for update;

  if not found then
    raise exception 'Categoria não encontrada.'
      using errcode = 'P0002';
  end if;

  if p_archived = (v_archived_at is not null) then
    return;
  end if;

  perform set_config('pixelry.finance_change_reason', v_reason, true);

  update public.finance_categories c
     set archived_at = case when p_archived then now() else null end
   where c.id = p_id;

  perform set_config('pixelry.finance_change_reason', '', true);
end;
$$;

-- ── Grants das RPCs ─────────────────────────────────────────────────────────
-- Default privileges do schema public dão EXECUTE direto a anon: revogar de
-- public não basta.
revoke execute on function public.finance_ledger(date, date)                     from public, anon;
revoke execute on function public.finance_overview_meta()                        from public, anon;
revoke execute on function public.finance_entry_history(text, uuid)              from public, anon;
revoke execute on function public.finance_clients()                              from public, anon;
revoke execute on function public.finance_create_entry(text, text, bigint, text, date, date, date, uuid, uuid, text, text, text, text)
  from public, anon;
revoke execute on function public.finance_correct_entry(uuid, jsonb, text)       from public, anon;
revoke execute on function public.finance_settle_entry(uuid, date, text)         from public, anon;
revoke execute on function public.finance_cancel_entry(uuid, text)               from public, anon;
revoke execute on function public.finance_reverse_entry(uuid, date, text, bigint) from public, anon;
revoke execute on function public.finance_create_category(text, text)            from public, anon;
revoke execute on function public.finance_set_category_archived(uuid, boolean, text) from public, anon;

grant execute on function public.finance_ledger(date, date)                      to authenticated;
grant execute on function public.finance_overview_meta()                         to authenticated;
grant execute on function public.finance_entry_history(text, uuid)               to authenticated;
grant execute on function public.finance_clients()                               to authenticated;
grant execute on function public.finance_create_entry(text, text, bigint, text, date, date, date, uuid, uuid, text, text, text, text)
  to authenticated;
grant execute on function public.finance_correct_entry(uuid, jsonb, text)        to authenticated;
grant execute on function public.finance_settle_entry(uuid, date, text)          to authenticated;
grant execute on function public.finance_cancel_entry(uuid, text)                to authenticated;
grant execute on function public.finance_reverse_entry(uuid, date, text, bigint) to authenticated;
grant execute on function public.finance_create_category(text, text)             to authenticated;
grant execute on function public.finance_set_category_archived(uuid, boolean, text) to authenticated;
