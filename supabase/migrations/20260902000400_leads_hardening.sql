-- Higiene e trava de flood na tabela de leads (formulário público).
--
-- A política de INSERT anônima continua existindo por ora (ver
-- 20260902000800_leads_insert_service_role_only.sql para o corte final,
-- que deve subir junto com o front novo). Enquanto isso, estes limites
-- valem para qualquer caminho de escrita, inclusive service_role.

-- 1. Limites de tamanho / formato — barram payloads absurdos e lixo.
alter table public.leads
  add constraint leads_name_len  check (char_length(name)  between 1 and 200),
  add constraint leads_email_fmt check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 320),
  add constraint leads_wa_len    check (whatsapp  is null or char_length(whatsapp)  <= 40),
  add constraint leads_ig_len    check (instagram is null or char_length(instagram) <= 120),
  add constraint leads_src_len   check (source    is null or char_length(source)    <= 80),
  add constraint leads_clinic_len check (clinic_type      is null or char_length(clinic_type)      <= 120),
  add constraint leads_rev_len    check (revenue_range     is null or char_length(revenue_range)    <= 60),
  add constraint leads_inv_len    check (investment_range  is null or char_length(investment_range) <= 60);

-- 2. Trava de flood: no máximo 30 leads/minuto no total (rajada de campanha
--    real cabe folgado; script de spam não). Rede de segurança independente
--    do rate limit por IP da Edge Function.
create or replace function public.leads_flood_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_recent integer;
begin
  select count(*) into v_recent
  from public.leads
  where created_at > now() - interval '1 minute';

  if v_recent >= 30 then
    raise exception 'rate limited: too many lead submissions, retry shortly'
      using errcode = '53400';
  end if;

  return new;
end;
$$;

drop trigger if exists leads_flood_guard_trg on public.leads;
create trigger leads_flood_guard_trg
  before insert on public.leads
  for each row execute function public.leads_flood_guard();
