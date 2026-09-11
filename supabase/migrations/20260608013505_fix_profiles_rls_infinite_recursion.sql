DROP POLICY IF EXISTS "employees_see_assigned_clients" ON public.profiles;

CREATE POLICY "employees_see_assigned_clients"
ON public.profiles
FOR SELECT
TO authenticated
USING (
  (auth.uid() = id)
  OR is_admin()
  OR (assigned_employee_id = auth.uid())
);
