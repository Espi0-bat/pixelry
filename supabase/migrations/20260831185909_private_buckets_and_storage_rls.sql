-- ─────────────────────────────────────────────────────────────
-- Arquivos: buckets privados + RLS correta por dono.
-- Downloads passam a usar URLs assinadas (createSignedUrl).
-- ─────────────────────────────────────────────────────────────

-- Helper: pertence à equipe (inclui employee, que precisa operar entregas)
create or replace function public.is_team()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('super_admin', 'manager', 'employee')
  )
$$;

revoke execute on function public.is_team() from public;
grant execute on function public.is_team() to authenticated;

-- 1. Buckets de arquivos de cliente deixam de ser públicos.
--    (avatars e pixelry-assets seguem públicos: são imagens de exibição.)
update storage.buckets set public = false where id in ('deliveries', 'client-uploads');

-- 2. deliveries — path: {client_id}/{arquivo}
drop policy if exists "Clientes autenticados podem baixar entregas" on storage.objects;
drop policy if exists "Admin pode fazer upload de entregas" on storage.objects;
drop policy if exists "Admin pode gerenciar entregas" on storage.objects;

create policy "deliveries_read_own_or_team"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'deliveries'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_team())
  );

create policy "deliveries_write_team"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'deliveries' and public.is_team());

create policy "deliveries_update_team"
  on storage.objects for update to authenticated
  using (bucket_id = 'deliveries' and public.is_team());

create policy "deliveries_delete_team"
  on storage.objects for delete to authenticated
  using (bucket_id = 'deliveries' and public.is_team());

-- 3. client-uploads — path: {user_id}/{arquivo}. Equipe precisa ler o que o cliente enviou.
drop policy if exists "cliente_le_proprios_arquivos" on storage.objects;
drop policy if exists "cliente_upload_proprios_arquivos" on storage.objects;

create policy "client_uploads_read_own_or_team"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'client-uploads'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_team())
  );

create policy "client_uploads_insert_own"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'client-uploads'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "client_uploads_delete_own_or_team"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'client-uploads'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_team())
  );

-- 4. internal-files — path: internal/{from_id}/{to_id}/{arquivo}. Só remetente, destinatário ou admin.
drop policy if exists "auth_read_internal_files" on storage.objects;

create policy "internal_files_read_participants"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'internal-files'
    and (
      (storage.foldername(name))[2] = auth.uid()::text
      or (storage.foldername(name))[3] = auth.uid()::text
      or public.is_admin()
    )
  );
