-- E2 — Destinatário não conseguia marcar mensagens/arquivos internos como lidos.
--
-- users_see_own_messages / users_see_own_files eram FOR ALL com
-- WITH CHECK (from_id = auth.uid()). Quem recebe passa no USING (to_id) mas o
-- UPDATE de read_at falha no WITH CHECK, porque não é o remetente:
-- "new row violates row-level security policy". O front engolia o erro e o
-- contador de não lidas nunca zerava de verdade.
--
-- Nova forma, uma policy por operação:
--   SELECT  remetente ou destinatário
--   INSERT  remetente = quem chama, e só equipe (as tabelas são internas)
--   UPDATE  só o destinatário, e só a coluna read_at (grant por coluna)
--   DELETE  nenhuma tela apaga; fica sem policy
-- (select auth.uid()) em vez de auth.uid() para o planner avaliar uma vez
-- (advisor auth_rls_initplan).

-- ── internal_messages ──────────────────────────────────────────────────────
drop policy if exists users_see_own_messages on public.internal_messages;

create policy internal_messages_select on public.internal_messages
  for select to authenticated
  using (from_id = (select auth.uid()) or to_id = (select auth.uid()));

create policy internal_messages_insert on public.internal_messages
  for insert to authenticated
  with check (from_id = (select auth.uid()) and (select public.is_team()));

create policy internal_messages_mark_read on public.internal_messages
  for update to authenticated
  using (to_id = (select auth.uid()))
  with check (to_id = (select auth.uid()));

revoke update, delete, truncate, references, trigger
  on public.internal_messages from authenticated;
grant update (read_at) on public.internal_messages to authenticated;
revoke all on public.internal_messages from anon;

-- ── internal_files ─────────────────────────────────────────────────────────
drop policy if exists users_see_own_files on public.internal_files;

create policy internal_files_select on public.internal_files
  for select to authenticated
  using (from_id = (select auth.uid()) or to_id = (select auth.uid()));

create policy internal_files_insert on public.internal_files
  for insert to authenticated
  with check (from_id = (select auth.uid()) and (select public.is_team()));

create policy internal_files_mark_read on public.internal_files
  for update to authenticated
  using (to_id = (select auth.uid()))
  with check (to_id = (select auth.uid()));

revoke update, delete, truncate, references, trigger
  on public.internal_files from authenticated;
grant update (read_at) on public.internal_files to authenticated;
revoke all on public.internal_files from anon;
