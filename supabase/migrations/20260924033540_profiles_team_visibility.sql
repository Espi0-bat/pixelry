-- S2 — Cliente não precisa enxergar a equipe.
--
-- team_members_see_each_other liberava SELECT nas linhas da equipe para
-- QUALQUER authenticated: clientes e, enquanto o cadastro público esteve
-- aberto, qualquer conta recém-criada — nome, e-mail e contact_info dos
-- sócios e funcionários.
--
-- Agora só quem é equipe vê a equipe. Cliente segue vendo o próprio perfil
-- (Users can view own profile); employee segue vendo os clientes atribuídos
-- (employees_see_assigned_clients); admin segue vendo tudo (Admin full access).

drop policy if exists team_members_see_each_other on public.profiles;

create policy team_members_see_each_other on public.profiles
  for select to authenticated
  using (
    (select public.is_team())
    and role = any (array['super_admin', 'manager', 'employee'])
  );
