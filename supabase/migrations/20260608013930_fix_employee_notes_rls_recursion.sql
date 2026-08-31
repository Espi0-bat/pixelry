DROP POLICY IF EXISTS "admins_all_employee_notes" ON public.employee_notes;

CREATE POLICY "admins_all_employee_notes"
ON public.employee_notes
FOR ALL
TO authenticated
USING (is_admin())
WITH CHECK (is_admin());
