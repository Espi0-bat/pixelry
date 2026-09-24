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
