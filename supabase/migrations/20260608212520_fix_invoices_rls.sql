-- Remove the overly permissive policy that grants ALL authenticated users
-- full access to every invoice. The service_role bypasses RLS automatically
-- and does not need a dedicated policy.
drop policy if exists "service_full_access" on invoices;
