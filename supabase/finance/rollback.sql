-- Financeiro — interruptor de emergência e remoção completa.
-- Ver supabase/finance/README.md antes de rodar qualquer parte.
--
-- PASSO 1 (sempre roda; seguro a qualquer momento; NÃO perde dados)
--   Desliga a auditoria de public.invoices. create-invoice, payment-webhook e
--   o cancelamento do dashboard voltam a funcionar exatamente como antes do
--   financeiro, mesmo que algo no gatilho tolerante dê errado. Lançamentos,
--   categorias, concessões e o histórico já gravado ficam intactos; o app
--   continua lendo tudo, só deixa de registrar mudanças novas em invoices.
--   Para religar: ver "Religar a auditoria de invoices" no README.
--
-- PASSO 2 (remoção completa; DESTRÓI lançamentos, categorias, concessões e
--   toda a auditoria; irreversível). Só roda com decisão explícita: na mesma
--   sessão/execução, antes deste arquivo,
--       set pixelry.finance_remove_all = 'apagar-tudo';
--   Sem isso o bloco só avisa e não faz nada. Depois dele o app mostra
--   "Financeiro ainda não está disponível neste servidor".

-- ── Passo 1: interruptor ────────────────────────────────────────────────────
drop trigger if exists finance_audit_invoice_trg on public.invoices;

-- ── Passo 2: remoção completa (protegida) ───────────────────────────────────
do $$
begin
  if coalesce(current_setting('pixelry.finance_remove_all', true), '') <> 'apagar-tudo' then
    raise notice 'Financeiro: passo 1 aplicado (auditoria de invoices desligada). Passo 2 (remoção completa) NÃO executado.';
    return;
  end if;

  -- RPCs
  drop function if exists public.finance_my_access();
  drop function if exists public.finance_set_access(uuid, text, text);
  drop function if exists public.finance_access_list();
  drop function if exists public.finance_ledger(date, date);
  drop function if exists public.finance_overview_meta();
  drop function if exists public.finance_entry_history(text, uuid);
  drop function if exists public.finance_clients();
  drop function if exists public.finance_create_entry(text, text, bigint, text, date, date, date, uuid, uuid, text, text, text, text);
  drop function if exists public.finance_correct_entry(uuid, jsonb, text);
  drop function if exists public.finance_settle_entry(uuid, date, text);
  drop function if exists public.finance_cancel_entry(uuid, text);
  drop function if exists public.finance_reverse_entry(uuid, date, text, bigint);
  drop function if exists public.finance_create_category(text, text);
  drop function if exists public.finance_set_category_archived(uuid, boolean, text);

  -- Tabelas (DROP TABLE não passa pelos gatilhos de DELETE/TRUNCATE).
  -- finance_entries antes de finance_categories (FK).
  drop table if exists public.finance_audit_log;
  drop table if exists public.finance_entries;
  drop table if exists public.finance_categories;
  drop table if exists public.finance_access_grants;

  -- Índices aditivos em invoices
  drop index if exists public.idx_invoices_due_date, public.idx_invoices_paid_at;

  -- Funções privadas, gatilhos órfãos e module_info
  drop schema if exists finance_private cascade;

  -- Histórico de migrations do Supabase (sem isso o próximo db push
  -- acharia que o financeiro ainda está aplicado).
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    delete from supabase_migrations.schema_migrations
    where version in ('20261101174500', '20261101174510', '20261101174520', '20261101174530');
  end if;

  raise notice 'Financeiro: remoção completa executada.';
end $$;
