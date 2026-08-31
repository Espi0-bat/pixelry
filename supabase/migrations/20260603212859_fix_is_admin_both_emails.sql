CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT auth.email() IN ('socio1@exemplo.com', 'ex-membro-1@exemplo.com')
$$;
