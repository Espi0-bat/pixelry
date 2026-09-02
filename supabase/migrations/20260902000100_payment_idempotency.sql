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
