-- CORTE FINAL do INSERT anônimo em leads.
--
-- ⚠️  APLICAR JUNTO COM O DEPLOY DO FRONT que passa a usar a Edge Function
--     `submit-lead` (honeypot + rate limit por IP + validação). Se aplicar
--     antes, o formulário do site para de gravar lead até o front novo subir.
--
-- Depois deste corte, o único caminho de escrita em leads é o service_role
-- (que ignora RLS) dentro de submit-lead. A leitura pela equipe continua.

drop policy if exists allow_insert_leads on public.leads;

-- (admin_read_leads permanece — equipe logada lê os leads.)
