-- E1 — Admin não conseguia atualizar entregas.
--
-- Em produção o papel authenticated tinha UPDATE em deliveries apenas na
-- coluna `status` (grant por coluna feito à mão, sem migration). A tela
-- Status do painel envia `status` e `updated_at`, e o Postgres respondia
-- "permission denied for table deliveries". O portal do cliente não sofria
-- porque só envia `status`.
--
-- Esta migration torna o estado explícito e reproduzível:
--   * revoga o UPDATE de tabela (o que também derruba os grants de coluna)
--     e reconcede só status + updated_at para authenticated;
--   * anon perde UPDATE (tinha UPDATE total sem nenhuma policy que o usasse).
--
-- O grant vale para todo authenticated, equipe inclusive. Hoje nenhuma tela
-- edita outra coluna de deliveries depois de criada; se um dia a equipe
-- precisar editar título/descrição, ampliar a lista de colunas AQUI.
-- O trigger deliveries_client_update_guard continua impedindo o cliente de
-- alterar qualquer coisa além do status.

revoke update on public.deliveries from anon;
revoke update on public.deliveries from authenticated;
grant update (status, updated_at) on public.deliveries to authenticated;
