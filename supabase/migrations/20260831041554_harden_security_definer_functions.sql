-- 1. get_vault_secret: leitura de segredos do Vault só pelo service_role (usado só pelo sync-notion).
--    Fecha /rest/v1/rpc/get_vault_secret para anon/authenticated (chave anônima é pública).
revoke execute on function public.get_vault_secret(text) from anon, authenticated, public;

-- 2. handle_new_user: é função de trigger, não deve ser chamável via RPC. Fixa search_path.
alter function public.handle_new_user() set search_path = '';
revoke execute on function public.handle_new_user() from anon, authenticated, public;

-- 3. is_admin: usada em RLS. Fixa search_path (corpo já é schema-qualificado).
--    Mantém execute para authenticated/anon (retorna false quando não é admin).
alter function public.is_admin() set search_path = '';
