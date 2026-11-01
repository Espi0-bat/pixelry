-- Carga inicial da migration 4/5 sobre dados que já existiam
-- (supabase/tests/local/existing_data.sql). Só no ambiente local; o runner
-- aplica a migration 4/5 duas vezes antes deste arquivo, para provar que a
-- carga não duplica.

create temp table crm_t (
  n        integer generated always as identity,
  test     text not null,
  expected text not null,
  actual   text
);

create function pg_temp.chk(p_test text, p_expected text, p_actual text)
returns void
language sql
as $$
  insert into crm_t (test, expected, actual) values (p_test, p_expected, p_actual)
$$;

select pg_temp.chk('cliente do portal vira uma conta ligada, sem responsável', '1',
  (select count(*)::text from public.crm_accounts
   where client_profile_id = '00000000-0000-4000-8000-0000000000c1'
     and name = 'Clínica Existente' and owner_id is null));

select pg_temp.chk('lead que já existia vira um contato e uma oportunidade', '1/1',
  (select count(*) from public.crm_contacts where lead_id = '00000000-0000-4000-8000-0000000000d1')
  || '/' || (select count(*) from public.crm_opportunities where lead_id = '00000000-0000-4000-8000-0000000000d1'));

select pg_temp.chk('oportunidade do lead antigo: Novo, sem dono, origem, qualificação e data do lead',
  'novo/sem dono/lp_clinicas_hero_geral/Estética/Até 20 mil/true',
  (select o.stage_id
          || '/' || case when o.owner_id is null then 'sem dono' else 'com dono' end
          || '/' || o.source
          || '/' || (o.qualification ->> 'segment')
          || '/' || (o.qualification ->> 'revenue_range')
          || '/' || (o.created_at = timestamptz '2026-10-01 12:00:00+00')::text
   from public.crm_opportunities o
   where o.lead_id = '00000000-0000-4000-8000-0000000000d1'));

select pg_temp.chk('contato do lead antigo leva nome, e-mail e WhatsApp', 'Lead Antigo/lead-antigo@example.invalid/61 98888-0000',
  (select c.full_name || '/' || c.email || '/' || c.phone
   from public.crm_contacts c where c.lead_id = '00000000-0000-4000-8000-0000000000d1'));

select pg_temp.chk('a carga entrou no histórico como inclusão do sistema', 'true',
  (select (count(*) > 0 and bool_and(actor_id is null))::text
   from public.crm_audit_log l
   join public.crm_opportunities o on l.entity_type = 'opportunity' and l.entity_id = o.id::text
   where o.lead_id = '00000000-0000-4000-8000-0000000000d1' and l.action = 'insert'));

select
  'CRMTEST' as marcador,
  n,
  case when actual is not distinct from expected then 'PASSOU' else 'FALHOU' end as resultado,
  test,
  expected,
  actual
from crm_t
order by (actual is not distinct from expected), n;
