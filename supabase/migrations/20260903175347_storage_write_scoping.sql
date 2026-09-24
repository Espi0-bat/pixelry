-- Escopo de escrita nos buckets de storage.
--
-- internal-files: INSERT só checava bucket_id — qualquer autenticado (inclusive
--   cliente) podia despejar arquivos lá (não conseguia ler os dos outros, mas
--   inflava o bucket). Alinha com deliveries_write_team: exige is_team().
-- avatars: INSERT/UPDATE/DELETE não checavam dono — um usuário podia
--   sobrescrever/apagar o avatar de outro. Convenção do app: nome = "<uid>.<ext>".

-- ── internal-files ────────────────────────────────────────────────────────
drop policy if exists auth_upload_internal_files on storage.objects;
create policy auth_upload_internal_files on storage.objects
  for insert to authenticated
  with check (bucket_id = 'internal-files' and is_team());

-- ── avatars ──────────────────────────────────────────────────────────────
drop policy if exists avatars_upload on storage.objects;
create policy avatars_upload on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and split_part(name, '.', 1) = auth.uid()::text);

drop policy if exists avatars_update on storage.objects;
create policy avatars_update on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and split_part(name, '.', 1) = auth.uid()::text)
  with check (bucket_id = 'avatars' and split_part(name, '.', 1) = auth.uid()::text);

drop policy if exists avatars_delete on storage.objects;
create policy avatars_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and split_part(name, '.', 1) = auth.uid()::text);

-- SELECT em avatars segue público (bucket de exibição) — inalterado.
