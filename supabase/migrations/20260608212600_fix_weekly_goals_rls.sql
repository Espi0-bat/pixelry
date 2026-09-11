-- Fix weekly_goals RLS: policy was named "admins_only" but used
-- auth.role() = 'authenticated', granting ALL operations to every
-- logged-in user. Replaced with is_admin() to match the intended behaviour.
drop policy if exists "admins_only" on weekly_goals;

create policy "admins_only" on weekly_goals
  for all
  using (is_admin())
  with check (is_admin());
