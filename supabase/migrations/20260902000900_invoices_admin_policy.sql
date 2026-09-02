-- Política de admin para invoices (estava faltando).
--
-- invoices só tinha: service_role_full_access + client_read_own_invoices.
-- Não havia policy para a equipe logada escrever — ou seja, o botão
-- "Cancelar cobrança" do admin (update status='cancelled' com o JWT do
-- usuário) batia na RLS e não fazia nada (0 linhas, sem erro).
--
-- Alinha invoices com o resto do schema, onde toda tabela de negócio tem
-- "Admin full access" via is_admin(). Clientes seguem só lendo as próprias.

create policy "Admin full access" on public.invoices
  for all
  to authenticated
  using (is_admin())
  with check (is_admin());
