-- 1. Adicionar colunas à tabela profiles
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS email text,
  ADD COLUMN IF NOT EXISTS contact_info jsonb DEFAULT '{}';

-- 2. Backfill email dos usuários existentes
UPDATE profiles p
SET email = u.email
FROM auth.users u
WHERE p.id = u.id AND p.email IS NULL;

-- 3. Trigger para sincronizar email ao criar novo usuário
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email)
  VALUES (NEW.id, NEW.raw_user_meta_data->>'full_name', NEW.email)
  ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 4. Função is_admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$
  SELECT auth.email() = 'moutinhoezer@gmail.com'
$$;

-- 5. Policies admin em todas as tabelas
CREATE POLICY "Admin full access" ON profiles
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Admin full access" ON deliveries
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Admin full access" ON projects
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Admin full access" ON messages
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Admin full access" ON assets
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Admin full access" ON client_files
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY "Admin full access" ON portal_events
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

-- 6. Storage policies para o bucket deliveries
CREATE POLICY "Admin pode fazer upload de entregas"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'deliveries' AND is_admin());

CREATE POLICY "Admin pode gerenciar entregas"
  ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'deliveries' AND is_admin());

CREATE POLICY "Clientes autenticados podem baixar entregas"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'deliveries');
