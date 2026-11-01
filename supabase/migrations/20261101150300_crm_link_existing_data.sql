-- CRM (app móvel) — 4/4: ligação com os dados que o dashboard já tem.
--
-- 1. Lead do site entra no funil sozinho. Cada linha nova em leads (gravada
--    pela Edge Function submit-lead) gera um contato e uma oportunidade na
--    etapa 'novo', sem responsável, com lead_id apontando para o lead.
--    A tabela leads, as policies dela e a tela Leads do dashboard não mudam:
--    sales_trial e sdr não leem leads; leem a cópia ligada no CRM.
--    O gatilho NUNCA derruba o cadastro do lead: qualquer erro vira WARNING
--    no log do Postgres e o lead é gravado mesmo assim.
--
-- 2. Leads que já existem entram do mesmo jeito (idempotente: só os que
--    ainda não têm contato ou oportunidade ligados).
--
-- 3. Clientes do portal (profiles.role = 'client') viram contas, ligadas por
--    client_profile_id, sem responsável. Idempotente. Clientes criados
--    depois NÃO entram sozinhos (ver handoff: pendência de integração).

-- ── 1. Gatilho em leads ─────────────────────────────────────────────────────
create or replace function crm_private.lead_to_crm()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contact_id uuid;
begin
  begin
    insert into public.crm_contacts (full_name, email, phone, instagram, lead_id, owner_id, created_by, created_at)
    values (new.name, new.email, new.whatsapp, new.instagram, new.id, null, null, coalesce(new.created_at, now()))
    returning id into v_contact_id;

    insert into public.crm_opportunities (
      title, contact_id, stage_id, source, lead_id, owner_id, created_by,
      qualification, created_at, stage_changed_at
    ) values (
      new.name, v_contact_id, 'novo', new.source, new.id, null, null,
      jsonb_strip_nulls(jsonb_build_object(
        'segment',          new.clinic_type,
        'revenue_range',    new.revenue_range,
        'investment_range', new.investment_range
      )),
      coalesce(new.created_at, now()),
      coalesce(new.created_at, now())
    );
  exception when others then
    raise warning '[crm] lead % não entrou no CRM: % (%)', new.id, sqlerrm, sqlstate;
  end;
  return null;
end;
$$;

revoke execute on function crm_private.lead_to_crm() from public;

create or replace trigger leads_to_crm_trg
  after insert on public.leads
  for each row execute function crm_private.lead_to_crm();

-- ── 2. Leads existentes ─────────────────────────────────────────────────────
with pendentes as (
  select l.*
  from public.leads l
  where not exists (select 1 from public.crm_contacts c where c.lead_id = l.id)
    and not exists (select 1 from public.crm_opportunities o where o.lead_id = l.id)
),
contatos as (
  insert into public.crm_contacts (full_name, email, phone, instagram, lead_id, owner_id, created_by, created_at)
  select p.name, p.email, p.whatsapp, p.instagram, p.id, null, null, coalesce(p.created_at, now())
  from pendentes p
  returning id, lead_id
)
insert into public.crm_opportunities (
  title, contact_id, stage_id, source, lead_id, owner_id, created_by,
  qualification, created_at, stage_changed_at
)
select
  p.name, c.id, 'novo', p.source, p.id, null, null,
  jsonb_strip_nulls(jsonb_build_object(
    'segment',          p.clinic_type,
    'revenue_range',    p.revenue_range,
    'investment_range', p.investment_range
  )),
  coalesce(p.created_at, now()),
  coalesce(p.created_at, now())
from pendentes p
join contatos c on c.lead_id = p.id;

-- ── 3. Clientes do portal como contas ───────────────────────────────────────
insert into public.crm_accounts (name, email, client_profile_id, owner_id, created_by)
select
  left(coalesce(nullif(btrim(p.company_name), ''), nullif(btrim(p.full_name), ''), p.email), 200),
  left(p.email, 320),
  p.id,
  null,
  null
from public.profiles p
where p.role = 'client'
  and coalesce(nullif(btrim(p.company_name), ''), nullif(btrim(p.full_name), ''), p.email) is not null
  and not exists (select 1 from public.crm_accounts a where a.client_profile_id = p.id);
