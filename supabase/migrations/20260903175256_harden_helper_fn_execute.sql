-- APLICADA EM PRODUCAO em 2026-09-03 17:52 (via MCP) e REVERTIDA 3 minutos
-- depois pela 20260903175521_revert_harden_helper_fn_execute. Mantida aqui
-- porque consta no historico remoto; o conteudo abaixo e o que foi executado.
--
-- Efeito real: derrubou TODAS as policies que chamam is_admin()/is_team()
-- ("permission denied for function is_admin"). Ver o revert para a explicacao.

revoke execute on function public.is_admin() from anon, authenticated, public;
revoke execute on function public.is_team()  from anon, authenticated, public;

grant execute on function public.is_admin() to service_role;
grant execute on function public.is_team()  to service_role;
