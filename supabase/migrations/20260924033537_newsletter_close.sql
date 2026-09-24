-- S3 — newsletter_subscribers: insert público sem limite.
--
-- A tabela foi criada pelo dashboard (não há migration) com a policy
-- "Permitir inserções públicas no formulário" (with check true, papel public),
-- sem constraint de tamanho/formato além de unique(email), sem trigger e sem
-- rate limit. Nenhum arquivo do front usa a tabela. Era só uma porta de flood.
--
-- Fecha a policy e os grants. Se a newsletter voltar, entra pelo mesmo padrão
-- do submit-lead (Edge Function + service_role + rate limit).

drop policy if exists "Permitir inserções públicas no formulário" on public.newsletter_subscribers;
revoke all on public.newsletter_subscribers from anon, authenticated;
