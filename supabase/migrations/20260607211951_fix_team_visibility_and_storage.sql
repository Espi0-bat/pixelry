-- Permite que todos os usuários autenticados vejam perfis de admin e employee
CREATE POLICY "team_members_see_each_other" ON public.profiles
  FOR SELECT TO authenticated
  USING (role IN ('admin', 'employee'));

-- Bucket para arquivos internos
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('internal-files', 'internal-files', false, 52428800)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: só autenticados podem fazer upload
CREATE POLICY "auth_upload_internal_files" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'internal-files');

-- Storage RLS: só autenticados podem baixar/ver
CREATE POLICY "auth_read_internal_files" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'internal-files');

-- Storage RLS: uploader pode deletar seus próprios arquivos (owner é uuid no Supabase)
CREATE POLICY "auth_delete_own_internal_files" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'internal-files' AND owner = auth.uid());
