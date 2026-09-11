DROP POLICY IF EXISTS "Admin full access" ON public.kanban_tasks;

CREATE POLICY "Admin full access" ON public.kanban_tasks
  FOR ALL
  USING (is_admin())
  WITH CHECK (is_admin());
