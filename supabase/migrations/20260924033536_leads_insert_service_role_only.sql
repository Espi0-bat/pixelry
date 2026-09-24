-- S1 — Corte final do INSERT anônimo em leads.
--
-- A policy allow_insert_leads (with check true, papel public) continuava em
-- produção: qualquer um com a anon key fazia POST /rest/v1/leads pulando o
-- honeypot, o rate limit por IP e a validação da Edge Function submit-lead.
-- Pior: mantendo 30 inserts/min, o trigger leads_flood_guard (limite global)
-- bloqueava os leads reais do site.
--
-- Pré-requisitos cumpridos: submit-lead deployada (v1, 2026-09-03) e o front
-- (LeadCaptureModal) só grava por ela. Depois desta migration o único caminho
-- de escrita em leads é o service_role dentro da Edge Function. A leitura pela
-- equipe (admin_read_leads) não muda.

drop policy if exists allow_insert_leads on public.leads;

-- Sem a policy o RLS já barra, mas o grant fica fechado também: uma policy
-- futura mal escrita não reabre a porta sozinha.
revoke insert, update, delete, truncate, references, trigger
  on public.leads from anon, authenticated;
revoke select on public.leads from anon;

-- O trigger de flood conta leads do último minuto e a tela Leads ordena por
-- created_at desc; sem índice os dois viram seq scan quando a tabela crescer.
create index if not exists idx_leads_created_at on public.leads (created_at desc);
