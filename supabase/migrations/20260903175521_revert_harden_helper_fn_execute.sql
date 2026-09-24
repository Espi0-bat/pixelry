-- REVERSAO IMEDIATA da 20260903175256_harden_helper_fn_execute.
--
-- O revoke de EXECUTE em is_admin()/is_team() derrubou TODAS as policies que
-- as chamam: "permission denied for function is_admin" em profiles, invoices,
-- deliveries, projects, messages, client_files, portal_events, weekly_goals
-- e nas policies de storage. Painel e portal fora do ar.
--
-- O teste que eu fiz antes revogava so de anon+authenticated e passou porque
-- o EXECUTE continuava chegando pelo papel PUBLIC (default do Postgres). A
-- migration revogou tambem de PUBLIC, e ai a heranca acabou. Teste invalido:
-- nao reproduzia o que a migration faz.
--
-- Conclusao: no Postgres a expressao da policy EXIGE EXECUTE do papel que faz
-- a query. Fechar esse advisor exige outro caminho (mover as funcoes para um
-- schema fora da API exposta), nao revoke.

grant execute on function public.is_admin() to anon, authenticated, service_role;
grant execute on function public.is_team()  to anon, authenticated, service_role;
