-- ============================================================
-- PIXELRY — endurecimento de seguranca — PASSO 1 de 2
--
-- JA APLICADO em producao em 2026-09-02 via MCP.
-- Mantido aqui como registro do que foi rodado.
-- ============================================================

-- ─────────────────────────────────────────────────────────
-- 20260902000100_payment_idempotency
-- ─────────────────────────────────────────────────────────
-- Idempotência do webhook de pagamento.
--
-- O Mercado Pago envia várias notificações por pagamento e faz retry.
-- Sem uma trava, cada re-entrega reprocessava a fatura e reenviava e-mails.
-- Esta tabela registra cada payment_id já tratado; o webhook consulta antes
-- de agir e grava só depois de confirmar a transição (ou já-pago).

create table if not exists public.processed_payments (
  payment_id    text        primary key,
  preference_id text,
  processed_at  timestamptz not null default now()
);

alter table public.processed_payments enable row level security;

-- Sem policies: apenas o service_role (Edge Function, ignora RLS) escreve/lê aqui.
revoke all on table public.processed_payments from anon, authenticated;

-- ─────────────────────────────────────────────────────────
-- 20260902000200_invoice_idempotency
-- ─────────────────────────────────────────────────────────
-- Idempotência + atomicidade na criação de cobranças.
--
-- Antes: cada chamada de create-invoice gerava X-Idempotency-Key aleatória e
-- inseria a fatura por último. Duplo-clique ou retry => 2 preferências no
-- Mercado Pago, 2 pagamentos Pix e 2 linhas em invoices.
--
-- Agora a Edge Function calcula uma chave determinística a partir de
-- (client_id, amount, description, due_date), grava a fatura como 'draft'
-- ANTES de falar com o Mercado Pago e finaliza para 'pending' depois.
-- O índice único abaixo é a trava real contra duplicidade.

alter table public.invoices
  add column if not exists idempotency_key text;

-- 'draft'  = criada, ainda não confirmada no Mercado Pago (janela de poucos segundos)
-- 'error'  = reservado para depuração manual
alter table public.invoices drop constraint if exists invoices_status_check;
alter table public.invoices add constraint invoices_status_check
  check (status = any (array['draft','pending','paid','cancelled','overdue','error']));

-- Uma cobrança viva por combinação idêntica. Cancelar libera a chave para recriação.
-- Linhas antigas (idempotency_key null) não entram no índice.
create unique index if not exists invoices_idempotency_key_uniq
  on public.invoices (idempotency_key)
  where idempotency_key is not null and status <> 'cancelled';

-- ─────────────────────────────────────────────────────────
-- 20260902000300_rate_limits
-- ─────────────────────────────────────────────────────────
-- Rate limiting de aplicação, compartilhado pelas Edge Functions.
--
-- Não substitui um WAF (Cloudflare) na frente do domínio — é a camada de
-- defesa que roda dentro do Supabase, contíguo aos dados. Janela fixa simples.

create table if not exists public.rate_limits (
  bucket       text        not null,
  window_start timestamptz not null,
  hits         integer     not null default 0,
  primary key (bucket, window_start)
);

alter table public.rate_limits enable row level security;
revoke all on table public.rate_limits from anon, authenticated;

-- Retorna true se a chamada está DENTRO do limite; false se estourou.
-- Uso: select public.check_rate_limit('lead:' || ip, 5, 60);
create or replace function public.check_rate_limit(
  p_bucket         text,
  p_limit          integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_window timestamptz;
  v_hits   integer;
begin
  v_window := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );

  insert into public.rate_limits (bucket, window_start, hits)
  values (p_bucket, v_window, 1)
  on conflict (bucket, window_start)
  do update set hits = public.rate_limits.hits + 1
  returning hits into v_hits;

  -- Limpeza oportunista (~1% das chamadas) — não há pg_cron neste projeto.
  if random() < 0.01 then
    delete from public.rate_limits where window_start < now() - interval '1 hour';
  end if;

  return v_hits <= p_limit;
end;
$$;

revoke all on function public.check_rate_limit(text, integer, integer) from anon, authenticated, public;
grant execute on function public.check_rate_limit(text, integer, integer) to service_role;

-- ─────────────────────────────────────────────────────────
-- 20260902000400_leads_hardening
-- ─────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────
-- 20260902000600_deliveries_client_update_guard
-- ─────────────────────────────────────────────────────────
-- Cliente só pode mudar o STATUS de uma entrega, não o conteúdo.
--
-- A policy "Clientes podem atualizar status das suas entregas" é UPDATE em
-- todas as colunas — nada impedia um cliente de reescrever title/description/
-- file_url da própria entrega. RLS não restringe coluna; este trigger sim.

create or replace function public.deliveries_client_update_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Equipe (super_admin / manager / employee) mantém acesso total.
  if is_team() then
    return new;
  end if;

  if new.project_id  is distinct from old.project_id
  or new.title       is distinct from old.title
  or new.description is distinct from old.description
  or new.type        is distinct from old.type
  or new.file_url    is distinct from old.file_url
  or new.created_at  is distinct from old.created_at
  or new.client_id   is distinct from old.client_id
  or new.due_date    is distinct from old.due_date then
    raise exception 'clients may only change delivery status' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists deliveries_client_update_guard_trg on public.deliveries;
create trigger deliveries_client_update_guard_trg
  before update on public.deliveries
  for each row execute function public.deliveries_client_update_guard();

-- ─────────────────────────────────────────────────────────
-- 20260902000700_storage_write_scoping
-- ─────────────────────────────────────────────────────────
-- Escopo de escrita nos buckets de storage.
--
-- internal-files: INSERT só checava bucket_id — qualquer autenticado (inclusive
--   cliente) podia despejar arquivos lá (não conseguia ler os dos outros, mas
--   inflava o bucket). Alinha com deliveries_write_team: exige is_team().
-- avatars: INSERT/UPDATE/DELETE não checavam dono — um usuário podia
--   sobrescrever/apagar o avatar de outro. Convenção do app: nome = "<uid>.<ext>".

-- ── internal-files ────────────────────────────────────────────────────────
drop policy if exists auth_upload_internal_files on storage.objects;
create policy auth_upload_internal_files on storage.objects
  for insert to authenticated
  with check (bucket_id = 'internal-files' and is_team());

-- ── avatars ──────────────────────────────────────────────────────────────
drop policy if exists avatars_upload on storage.objects;
create policy avatars_upload on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and split_part(name, '.', 1) = auth.uid()::text);

drop policy if exists avatars_update on storage.objects;
create policy avatars_update on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and split_part(name, '.', 1) = auth.uid()::text)
  with check (bucket_id = 'avatars' and split_part(name, '.', 1) = auth.uid()::text);

drop policy if exists avatars_delete on storage.objects;
create policy avatars_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and split_part(name, '.', 1) = auth.uid()::text);

-- SELECT em avatars segue público (bucket de exibição) — inalterado.

-- ─────────────────────────────────────────────────────────
-- 20260902000900_invoices_admin_policy
-- ─────────────────────────────────────────────────────────
-- Política de admin para invoices (estava faltando).
--
-- invoices só tinha: service_role_full_access + client_read_own_invoices.
-- Não havia policy para a equipe logada escrever — ou seja, o botão
-- "Cancelar cobrança" do admin (update status='cancelled' com o JWT do
-- usuário) batia na RLS e não fazia nada (0 linhas, sem erro).
--
-- Alinha invoices com o resto do schema, onde toda tabela de negócio tem
-- "Admin full access" via is_admin(). Clientes seguem só lendo as próprias.

create policy "Admin full access" on public.invoices
  for all
  to authenticated
  using (is_admin())
  with check (is_admin());

