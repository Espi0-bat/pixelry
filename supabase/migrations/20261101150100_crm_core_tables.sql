-- CRM (app móvel) — 2/4: tabelas, índices, travas e auditoria.
--
-- O que já existia e é reaproveitado:
--   profiles  → responsável (owner_id), SDR (sdr_id), autor (created_by) e o
--               cliente do portal ligado a uma conta (client_profile_id).
--   leads     → origem das oportunidades que chegam pelo site (lead_id).
--               A ligação automática fica na migration 4/4.
--   leads.source → mesma convenção em crm_opportunities.source, para o app
--               traduzir com as mesmas regras de src/admin/utils/leadSource.js.
-- Não havia contas, contatos, oportunidades, etapas nem atividades no banco:
-- o dashboard só lista leads (src/admin/pages/Leads.jsx).
--
-- Regras de escrita que valem para qualquer tela (as policies ficam na 3/4):
--   * created_by é sempre quem chamou e não muda depois.
--   * Quem não tem CRM completo não escolhe nem troca responsável/SDR.
--   * lead_id e client_request_id não mudam depois de gravados.
--   * client_request_id é a chave de idempotência do app: o mesmo envio
--     repetido (toque duplo, retry de rede) bate no índice único.
--   * Ir para uma etapa de perda exige motivo.
--   * Toda inclusão, alteração e exclusão vira linha em crm_audit_log, com o
--     antes e o depois de cada campo. Ninguém do app escreve no log.

-- ── Etapas do funil ─────────────────────────────────────────────────────────
create table if not exists public.crm_stages (
  id          text primary key
              constraint crm_stages_id_fmt check (id ~ '^[a-z][a-z0-9_]{0,39}$'),
  label       text not null
              constraint crm_stages_label_len check (char_length(btrim(label)) between 1 and 60),
  position    smallint not null,
  kind        text not null default 'open'
              constraint crm_stages_kind_check check (kind in ('open', 'won', 'lost')),
  probability smallint
              constraint crm_stages_probability_range check (probability between 0 and 100),
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Funil comercial do SOP (prospecção → diagnóstico → proposta → fechamento).
-- Rótulos, ordem e probabilidade podem ser mudados depois sem novo APK.
insert into public.crm_stages (id, label, position, kind, probability) values
  ('novo',        'Novo',        10, 'open', 10),
  ('contato',     'Em contato',  20, 'open', 20),
  ('diagnostico', 'Diagnóstico', 30, 'open', 40),
  ('proposta',    'Proposta',    40, 'open', 60),
  ('negociacao',  'Negociação',  50, 'open', 80),
  ('ganho',       'Ganho',       60, 'won',  100),
  ('perdido',     'Perdido',     70, 'lost', 0)
on conflict (id) do nothing;

-- ── Contas / empresas ───────────────────────────────────────────────────────
create table if not exists public.crm_accounts (
  id                uuid primary key default gen_random_uuid(),
  name              text not null
                    constraint crm_accounts_name_len check (char_length(btrim(name)) between 1 and 200),
  segment           text constraint crm_accounts_segment_len   check (char_length(segment)   <= 120),
  city              text constraint crm_accounts_city_len      check (char_length(city)      <= 120),
  phone             text constraint crm_accounts_phone_len     check (char_length(phone)     <= 40),
  email             text constraint crm_accounts_email_len     check (char_length(email)     <= 320),
  instagram         text constraint crm_accounts_instagram_len check (char_length(instagram) <= 120),
  website           text constraint crm_accounts_website_len   check (char_length(website)   <= 300),
  notes             text constraint crm_accounts_notes_len     check (char_length(notes)     <= 5000),
  owner_id          uuid default auth.uid() references public.profiles(id) on delete set null,
  client_profile_id uuid references public.profiles(id) on delete set null,
  client_request_id uuid,
  created_by        uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  archived_at       timestamptz
);

comment on column public.crm_accounts.client_profile_id is
  'Cliente do portal (profiles.role = client) que corresponde a esta conta.';

-- ── Contatos ────────────────────────────────────────────────────────────────
create table if not exists public.crm_contacts (
  id                uuid primary key default gen_random_uuid(),
  account_id        uuid references public.crm_accounts(id) on delete set null,
  full_name         text not null
                    constraint crm_contacts_name_len check (char_length(btrim(full_name)) between 1 and 200),
  job_title         text constraint crm_contacts_job_title_len check (char_length(job_title) <= 120),
  email             text constraint crm_contacts_email_len     check (char_length(email)     <= 320),
  phone             text constraint crm_contacts_phone_len     check (char_length(phone)     <= 40),
  instagram         text constraint crm_contacts_instagram_len check (char_length(instagram) <= 120),
  notes             text constraint crm_contacts_notes_len     check (char_length(notes)     <= 5000),
  owner_id          uuid default auth.uid() references public.profiles(id) on delete set null,
  lead_id           uuid references public.leads(id) on delete set null,
  client_request_id uuid,
  created_by        uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  archived_at       timestamptz
);

-- ── Leads e oportunidades ───────────────────────────────────────────────────
-- Um lead é uma oportunidade nas primeiras etapas: não há tabela separada.
create table if not exists public.crm_opportunities (
  id                  uuid primary key default gen_random_uuid(),
  title               text not null
                      constraint crm_opportunities_title_len check (char_length(btrim(title)) between 1 and 200),
  account_id          uuid references public.crm_accounts(id) on delete set null,
  contact_id          uuid references public.crm_contacts(id) on delete set null,
  stage_id            text not null default 'novo' references public.crm_stages(id) on update cascade,
  owner_id            uuid default auth.uid() references public.profiles(id) on delete set null,
  sdr_id              uuid references public.profiles(id) on delete set null,
  source              text constraint crm_opportunities_source_len check (char_length(source) <= 80),
  lead_id             uuid references public.leads(id) on delete set null,
  estimated_value     numeric(12, 2)
                      constraint crm_opportunities_value_positive check (estimated_value >= 0),
  next_action         text constraint crm_opportunities_next_action_len check (char_length(next_action) <= 300),
  next_action_at      timestamptz,
  expected_close_date date,
  lost_reason         text constraint crm_opportunities_lost_reason_len check (char_length(lost_reason) <= 500),
  qualification       jsonb not null default '{}'::jsonb
                      constraint crm_opportunities_qualification_obj check (jsonb_typeof(qualification) = 'object'),
  stage_changed_at    timestamptz not null default now(),
  closed_at           timestamptz,
  client_request_id   uuid,
  created_by          uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  archived_at         timestamptz
);

comment on column public.crm_opportunities.owner_id is 'Responsável pela oportunidade.';
comment on column public.crm_opportunities.sdr_id is
  'SDR que trabalha ou trouxe a oportunidade. Continua vendo o registro depois do repasse.';
comment on column public.crm_opportunities.qualification is
  'Respostas de qualificação (segment, revenue_range, investment_range), como no formulário do site.';

-- ── Atividades comerciais ───────────────────────────────────────────────────
-- account_id/contact_id usam SET NULL para a linha do tempo sobreviver à
-- exclusão definitiva de uma conta ou contato (só o super_admin exclui).
create table if not exists public.crm_activities (
  id                uuid primary key default gen_random_uuid(),
  opportunity_id    uuid references public.crm_opportunities(id) on delete cascade,
  account_id        uuid references public.crm_accounts(id) on delete set null,
  contact_id        uuid references public.crm_contacts(id) on delete set null,
  type              text not null
                    constraint crm_activities_type_check check (type in ('call', 'meeting', 'message', 'note')),
  summary           text not null
                    constraint crm_activities_summary_len check (char_length(btrim(summary)) between 1 and 300),
  details           text constraint crm_activities_details_len check (char_length(details) <= 5000),
  occurred_at       timestamptz not null default now(),
  client_request_id uuid,
  created_by        uuid default auth.uid() references public.profiles(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- ── Histórico auditável ─────────────────────────────────────────────────────
-- Sem FK em actor_id: o histórico não pode mudar quando um perfil some.
create table if not exists public.crm_audit_log (
  id          bigint generated always as identity primary key,
  entity_type text not null
              constraint crm_audit_log_entity_check
              check (entity_type in ('account', 'contact', 'opportunity', 'activity', 'stage', 'member_access')),
  entity_id   text not null,
  action      text not null constraint crm_audit_log_action_check check (action in ('insert', 'update', 'delete')),
  changes     jsonb not null default '{}'::jsonb,
  actor_id    uuid,
  occurred_at timestamptz not null default now()
);

comment on table public.crm_audit_log is
  'Histórico do CRM. changes = {campo: {old, new}}. Gravado só por gatilho/RPC.';

-- ── Índices ─────────────────────────────────────────────────────────────────
-- Relações (FKs que as listas e as policies do SDR percorrem)
create index if not exists idx_crm_accounts_owner          on public.crm_accounts (owner_id);
create index if not exists idx_crm_contacts_account        on public.crm_contacts (account_id);
create index if not exists idx_crm_contacts_owner          on public.crm_contacts (owner_id);
create index if not exists idx_crm_opportunities_account   on public.crm_opportunities (account_id);
create index if not exists idx_crm_opportunities_contact   on public.crm_opportunities (contact_id);
create index if not exists idx_crm_opportunities_owner     on public.crm_opportunities (owner_id);
create index if not exists idx_crm_opportunities_sdr       on public.crm_opportunities (sdr_id);
create index if not exists idx_crm_activities_created_by   on public.crm_activities (created_by);

-- Filtros e ordenações do app (só o funil ativo)
create index if not exists idx_crm_opportunities_stage_open
  on public.crm_opportunities (stage_id) where archived_at is null;
create index if not exists idx_crm_opportunities_next_action
  on public.crm_opportunities (next_action_at) where archived_at is null and next_action_at is not null;
create index if not exists idx_crm_opportunities_updated
  on public.crm_opportunities (updated_at desc);

-- Linhas do tempo
create index if not exists idx_crm_activities_opportunity on public.crm_activities (opportunity_id, occurred_at desc);
create index if not exists idx_crm_activities_account     on public.crm_activities (account_id, occurred_at desc);
create index if not exists idx_crm_activities_contact     on public.crm_activities (contact_id, occurred_at desc);
create index if not exists idx_crm_audit_log_entity       on public.crm_audit_log (entity_type, entity_id, occurred_at desc);

-- Unicidade: um contato e uma oportunidade por lead; uma conta por cliente
-- do portal; um registro por chave de envio.
create unique index if not exists crm_contacts_lead_uniq
  on public.crm_contacts (lead_id) where lead_id is not null;
create unique index if not exists crm_opportunities_lead_uniq
  on public.crm_opportunities (lead_id) where lead_id is not null;
create unique index if not exists crm_accounts_client_profile_uniq
  on public.crm_accounts (client_profile_id) where client_profile_id is not null;
create unique index if not exists crm_accounts_request_uniq
  on public.crm_accounts (client_request_id) where client_request_id is not null;
create unique index if not exists crm_contacts_request_uniq
  on public.crm_contacts (client_request_id) where client_request_id is not null;
create unique index if not exists crm_opportunities_request_uniq
  on public.crm_opportunities (client_request_id) where client_request_id is not null;
create unique index if not exists crm_activities_request_uniq
  on public.crm_activities (client_request_id) where client_request_id is not null;

-- ── RLS ligada desde já ─────────────────────────────────────────────────────
-- Sem policy, nega tudo. As policies chegam na 3/4; se ela falhar no push,
-- as tabelas ficam fechadas, não abertas.
alter table public.crm_stages        enable row level security;
alter table public.crm_accounts      enable row level security;
alter table public.crm_contacts      enable row level security;
alter table public.crm_opportunities enable row level security;
alter table public.crm_activities    enable row level security;
alter table public.crm_audit_log     enable row level security;

-- ── Grants ──────────────────────────────────────────────────────────────────
-- O default do projeto dá tudo a anon e authenticated em tabela nova de
-- public. Aqui fica o mínimo: anon sem nada; authenticated com o necessário,
-- e a RLS (3/4) decide as linhas. TRUNCATE/REFERENCES/TRIGGER ficam de fora.
revoke all on table
  public.crm_stages, public.crm_accounts, public.crm_contacts,
  public.crm_opportunities, public.crm_activities, public.crm_audit_log
  from anon, authenticated;

grant select, insert, update, delete on table
  public.crm_stages, public.crm_accounts, public.crm_contacts,
  public.crm_opportunities, public.crm_activities
  to authenticated;

-- Log: só leitura, e só do que a pessoa pode ver.
grant select on table public.crm_audit_log to authenticated;

-- ── Gatilhos ────────────────────────────────────────────────────────────────

-- updated_at
create or replace function crm_private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Autoria, atribuição e campos imutáveis.
-- SECURITY INVOKER de propósito (mesmo motivo de guard_profile_role):
-- current_user é o papel real da conexão. Edge Functions (service_role),
-- SQL Editor (postgres) e o gatilho de leads (SECURITY DEFINER) passam
-- direto; as conexões do app e do painel (authenticated) passam pela trava.
-- Usa jsonb para servir às três tabelas: chave inexistente vale NULL nos dois
-- lados, e jsonb_populate_record ignora colunas que a tabela não tem.
create or replace function crm_private.guard_row()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_level text;
  v_new   jsonb;
  v_old   jsonb;
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  v_level := crm_private.access_level();

  if tg_op = 'INSERT' then
    new := jsonb_populate_record(new, jsonb_build_object('created_by', v_uid));

    -- Sem CRM completo, o registro novo é sempre da própria pessoa e sem SDR
    -- escolhido à mão (crm_opportunities_sdr preenche quando ela é SDR).
    if v_level <> 'full' and tg_table_name <> 'crm_activities' then
      new := jsonb_populate_record(new, jsonb_build_object('owner_id', v_uid, 'sdr_id', null));
    end if;
    return new;
  end if;

  v_new := to_jsonb(new);
  v_old := to_jsonb(old);

  if v_new -> 'created_by'        is distinct from v_old -> 'created_by'
  or v_new -> 'lead_id'           is distinct from v_old -> 'lead_id'
  or v_new -> 'client_request_id' is distinct from v_old -> 'client_request_id' then
    raise exception 'Autor, lead de origem e chave de envio não podem ser alterados.'
      using errcode = '42501';
  end if;

  if v_level <> 'full'
     and (v_new -> 'owner_id' is distinct from v_old -> 'owner_id'
          or v_new -> 'sdr_id' is distinct from v_old -> 'sdr_id') then
    raise exception 'Somente quem tem acesso completo ao CRM pode alterar o responsável.'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

-- Responsável SDR vira também o SDR da oportunidade, se o campo estiver
-- vazio. Assim o SDR continua vendo o registro depois do repasse ao closer;
-- para tirar o acesso, quem tem CRM completo limpa sdr_id.
create or replace function crm_private.opportunity_sdr()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.sdr_id is null
     and new.owner_id is not null
     and (tg_op = 'INSERT' or new.owner_id is distinct from old.owner_id)
     and crm_private.role_of(new.owner_id) = 'sdr' then
    new.sdr_id := new.owner_id;
  end if;
  return new;
end;
$$;

-- Etapa: carimbos de data, etapa ativa e motivo de perda.
create or replace function crm_private.opportunity_stage()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind   text;
  v_active boolean;
begin
  if tg_op = 'UPDATE' and new.stage_id is not distinct from old.stage_id then
    return new;
  end if;

  select s.kind, s.active into v_kind, v_active
  from public.crm_stages s
  where s.id = new.stage_id;

  if not coalesce(v_active, false) then
    raise exception 'Esta etapa está desativada.' using errcode = '23514';
  end if;

  if v_kind = 'lost' and coalesce(btrim(new.lost_reason), '') = '' then
    raise exception 'Informe o motivo da perda.' using errcode = '23514';
  end if;

  if tg_op = 'UPDATE' then
    new.stage_changed_at := now();
  end if;
  new.closed_at := case when v_kind in ('won', 'lost') then now() end;
  return new;
end;
$$;

-- Atividade: precisa de um registro de origem; conta e contato vêm da
-- oportunidade quando não informados, para aparecer nas três linhas do tempo.
create or replace function crm_private.activity_defaults()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.opportunity_id is not null and (new.account_id is null or new.contact_id is null) then
    select coalesce(new.account_id, o.account_id), coalesce(new.contact_id, o.contact_id)
      into new.account_id, new.contact_id
    from public.crm_opportunities o
    where o.id = new.opportunity_id;
  end if;

  if num_nonnulls(new.opportunity_id, new.account_id, new.contact_id) = 0 then
    raise exception 'A atividade precisa estar ligada a uma oportunidade, conta ou contato.'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

-- Auditoria genérica. changes = {campo: {old, new}}; em inclusão só "new",
-- em exclusão só "old". updated_at e stage_changed_at são derivados e ficam
-- de fora; update que não muda nada não gera linha.
create or replace function crm_private.audit_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old     jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_new     jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  v_skip    text[] := array['updated_at', 'stage_changed_at', 'created_at', 'client_request_id'];
  v_changes jsonb := '{}'::jsonb;
  v_key     text;
begin
  for v_key in
    select k from jsonb_object_keys(coalesce(v_new, v_old)) as k
  loop
    continue when v_key = any (v_skip);
    if tg_op = 'INSERT' and v_new -> v_key <> 'null'::jsonb then
      v_changes := v_changes || jsonb_build_object(v_key, jsonb_build_object('new', v_new -> v_key));
    elsif tg_op = 'DELETE' and v_old -> v_key <> 'null'::jsonb then
      v_changes := v_changes || jsonb_build_object(v_key, jsonb_build_object('old', v_old -> v_key));
    elsif tg_op = 'UPDATE' and v_new -> v_key is distinct from v_old -> v_key then
      v_changes := v_changes || jsonb_build_object(
        v_key, jsonb_build_object('old', v_old -> v_key, 'new', v_new -> v_key));
    end if;
  end loop;

  if tg_op = 'UPDATE' and v_changes = '{}'::jsonb then
    return null;
  end if;

  insert into public.crm_audit_log (entity_type, entity_id, action, changes, actor_id)
  values (
    case tg_table_name
      when 'crm_accounts'      then 'account'
      when 'crm_contacts'      then 'contact'
      when 'crm_opportunities' then 'opportunity'
      when 'crm_activities'    then 'activity'
      when 'crm_stages'        then 'stage'
    end,
    coalesce(v_new ->> 'id', v_old ->> 'id'),
    lower(tg_op),
    v_changes,
    auth.uid()
  );
  return null;
end;
$$;

-- Funções de gatilho não são chamadas por RPC nem exigem EXECUTE de quem
-- dispara o gatilho (verificado em 20260924033541).
revoke execute on function crm_private.touch_updated_at()  from public;
revoke execute on function crm_private.guard_row()         from public;
revoke execute on function crm_private.opportunity_sdr()   from public;
revoke execute on function crm_private.opportunity_stage() from public;
revoke execute on function crm_private.activity_defaults() from public;
revoke execute on function crm_private.audit_row()         from public;

-- updated_at
create or replace trigger crm_stages_touch        before update on public.crm_stages
  for each row execute function crm_private.touch_updated_at();
create or replace trigger crm_accounts_touch      before update on public.crm_accounts
  for each row execute function crm_private.touch_updated_at();
create or replace trigger crm_contacts_touch      before update on public.crm_contacts
  for each row execute function crm_private.touch_updated_at();
create or replace trigger crm_opportunities_touch before update on public.crm_opportunities
  for each row execute function crm_private.touch_updated_at();
create or replace trigger crm_activities_touch    before update on public.crm_activities
  for each row execute function crm_private.touch_updated_at();

-- Travas (antes da RLS checar o WITH CHECK, que vê a linha já ajustada)
create or replace trigger crm_accounts_guard      before insert or update on public.crm_accounts
  for each row execute function crm_private.guard_row();
create or replace trigger crm_contacts_guard      before insert or update on public.crm_contacts
  for each row execute function crm_private.guard_row();
create or replace trigger crm_opportunities_guard before insert or update on public.crm_opportunities
  for each row execute function crm_private.guard_row();
create or replace trigger crm_activities_guard    before insert or update on public.crm_activities
  for each row execute function crm_private.guard_row();

-- (gatilhos BEFORE rodam em ordem alfabética: guard → sdr → stage → touch)
create or replace trigger crm_opportunities_sdr   before insert or update of owner_id on public.crm_opportunities
  for each row execute function crm_private.opportunity_sdr();
create or replace trigger crm_opportunities_stage before insert or update of stage_id on public.crm_opportunities
  for each row execute function crm_private.opportunity_stage();
create or replace trigger crm_activities_defaults before insert on public.crm_activities
  for each row execute function crm_private.activity_defaults();

-- Histórico
create or replace trigger crm_stages_audit        after insert or update or delete on public.crm_stages
  for each row execute function crm_private.audit_row();
create or replace trigger crm_accounts_audit      after insert or update or delete on public.crm_accounts
  for each row execute function crm_private.audit_row();
create or replace trigger crm_contacts_audit      after insert or update or delete on public.crm_contacts
  for each row execute function crm_private.audit_row();
create or replace trigger crm_opportunities_audit after insert or update or delete on public.crm_opportunities
  for each row execute function crm_private.audit_row();
create or replace trigger crm_activities_audit    after insert or update or delete on public.crm_activities
  for each row execute function crm_private.audit_row();
