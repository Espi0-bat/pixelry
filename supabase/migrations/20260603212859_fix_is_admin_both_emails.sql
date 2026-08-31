CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT auth.email() IN ('moutinhoezer@gmail.com', 'erickvin49@gmail.com')
$$;
