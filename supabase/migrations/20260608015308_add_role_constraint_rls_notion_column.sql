-- Constraint de roles válidos
ALTER TABLE public.profiles 
  ADD CONSTRAINT profiles_role_check 
  CHECK (role IN ('super_admin', 'manager', 'employee', 'client'));

-- RLS kanban_tasks: remover policy antiga e criar a nova
DROP POLICY IF EXISTS "Admin full access" ON public.kanban_tasks;

CREATE POLICY "Staff full access"
  ON public.kanban_tasks
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
      AND role IN ('super_admin', 'manager', 'employee')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
      AND role IN ('super_admin', 'manager', 'employee')
    )
  );

-- Coluna notion_page_id na weekly_goals
ALTER TABLE public.weekly_goals
  ADD COLUMN IF NOT EXISTS notion_page_id text;
