-- ── 1. Colunas novas em profiles ──────────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'client'
    CHECK (role IN ('admin', 'employee', 'client')),
  ADD COLUMN IF NOT EXISTS job_title text,
  ADD COLUMN IF NOT EXISTS assigned_employee_id uuid REFERENCES auth.users(id);

-- ── 2. Setar roles iniciais por email ─────────────────────────────────────
UPDATE public.profiles SET role = 'admin',    job_title = 'Sócio'    WHERE email ILIKE '%moutinhoezer%';
UPDATE public.profiles SET role = 'admin',    job_title = 'Sócio'    WHERE email ILIKE '%erickvin49%';
UPDATE public.profiles SET role = 'employee', job_title = 'Designer' WHERE email ILIKE '%sofiagramelich%';

-- ── 3. Tabela: notas/avaliações de funcionários ───────────────────────────
CREATE TABLE IF NOT EXISTS public.employee_notes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id uuid NOT NULL REFERENCES auth.users(id),
  author_id   uuid NOT NULL REFERENCES auth.users(id),
  content     text NOT NULL,
  rating      smallint CHECK (rating BETWEEN 1 AND 5),
  created_at  timestamptz DEFAULT now()
);
ALTER TABLE public.employee_notes ENABLE ROW LEVEL SECURITY;

-- ── 4. Tabela: mensagens internas 1-on-1 ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.internal_messages (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_id    uuid NOT NULL REFERENCES auth.users(id),
  to_id      uuid NOT NULL REFERENCES auth.users(id),
  content    text NOT NULL,
  read_at    timestamptz,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.internal_messages ENABLE ROW LEVEL SECURITY;

-- ── 5. Tabela: arquivos internos ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.internal_files (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_id    uuid NOT NULL REFERENCES auth.users(id),
  to_id      uuid NOT NULL REFERENCES auth.users(id),
  file_url   text NOT NULL,
  file_name  text NOT NULL,
  file_size  text,
  message    text,
  read_at    timestamptz,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE public.internal_files ENABLE ROW LEVEL SECURITY;

-- ── 6. RLS: employee_notes ────────────────────────────────────────────────
CREATE POLICY "admins_all_employee_notes" ON public.employee_notes
  FOR ALL TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "employees_read_own_notes" ON public.employee_notes
  FOR SELECT TO authenticated
  USING (employee_id = auth.uid());

-- ── 7. RLS: internal_messages ─────────────────────────────────────────────
CREATE POLICY "users_see_own_messages" ON public.internal_messages
  FOR ALL TO authenticated
  USING (from_id = auth.uid() OR to_id = auth.uid())
  WITH CHECK (from_id = auth.uid());

-- ── 8. RLS: internal_files ────────────────────────────────────────────────
CREATE POLICY "users_see_own_files" ON public.internal_files
  FOR ALL TO authenticated
  USING (from_id = auth.uid() OR to_id = auth.uid())
  WITH CHECK (from_id = auth.uid());

-- ── 9. RLS extra: employees veem perfis de clientes atribuídos a eles ─────
CREATE POLICY "employees_see_assigned_clients" ON public.profiles
  FOR SELECT TO authenticated
  USING (
    auth.uid() = id
    OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.role = 'admin')
    OR assigned_employee_id = auth.uid()
  );
