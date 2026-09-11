-- Remove duplicate SELECT policy on deliveries
DROP POLICY IF EXISTS "Clients can view own deliveries" ON public.deliveries;

-- Remove duplicate SELECT policy on projects
DROP POLICY IF EXISTS "Clients can view own projects" ON public.projects;
