-- 01 — O schema integrado (baseline + migrations 202611*) e o que o módulo
-- do Ponto NÃO mexe. A migration de integração 20261102120000 resolveu as
-- pendências §6.1 (authenticated sem INSERT/DELETE em profiles + guarda
-- compartilhada) e §6.2 (profiles_role_check com os oito papéis). O módulo
-- continua sem alterar profiles, is_admin() ou is_team() (contrato §1, §3.0).
begin;

select tests.note('profiles_role_check aceita os oito papéis do app e só eles');
select tests.lives('aceita super_admin', $$select tests.create_user('p_sa', 'super_admin')$$);
select tests.lives('aceita manager', $$select tests.create_user('p_mgr', 'manager')$$);
select tests.lives('aceita employee', $$select tests.create_user('p_emp', 'employee')$$);
select tests.lives('aceita client', $$select tests.create_user('p_cli', 'client')$$);
select tests.lives('aceita partner (§6.2 resolvida)', $$select tests.create_user('p_partner', 'partner')$$);
select tests.lives('aceita sales_trial (§6.2 resolvida)', $$select tests.create_user('p_trial', 'sales_trial')$$);
select tests.lives('aceita employee_dev (§6.2 resolvida)', $$select tests.create_user('p_dev', 'employee_dev')$$);
select tests.lives('aceita sdr (§6.2 resolvida)', $$select tests.create_user('p_sdr', 'sdr')$$);
select tests.throws_constraint('rejeita o papel legado admin',
  $$select tests.create_user('p_admin', 'admin')$$, '23514', 'profiles_role_check');
select tests.throws_constraint('rejeita papel inventado',
  $$select tests.create_user('p_x', 'owner')$$, '23514', 'profiles_role_check');

select tests.note('profiles depois da integração: só o que CRM e integração acrescentaram');
select tests.query_is('profiles_role_check com o texto da 20261102120000',
  $$select pg_get_constraintdef(c.oid) from pg_constraint c
     where c.conrelid = 'public.profiles'::regclass and c.conname = 'profiles_role_check'$$,
  $$CHECK ((role = ANY (ARRAY['super_admin'::text, 'partner'::text, 'manager'::text, 'sales_trial'::text, 'employee_dev'::text, 'employee'::text, 'sdr'::text, 'client'::text])))$$);
select tests.query_is('constraints de profiles (histórico + crm_access do CRM)',
  $$select string_agg(conname, ',' order by conname collate "C") from pg_constraint where conrelid = 'public.profiles'::regclass$$,
  'profiles_assigned_employee_id_fkey,profiles_crm_access_check,profiles_id_fkey,profiles_pkey,profiles_role_check');
select tests.query_is('policies de profiles (nenhuma do módulo)',
  $$select string_agg(polname, ',' order by polname collate "C") from pg_policy where polrelid = 'public.profiles'::regclass$$,
  'Admin full access,Users can view own profile,employees_see_assigned_clients,profiles_update_own,team_members_see_each_other');
select tests.query_is('triggers de profiles: profiles_guard_role (UPDATE) e a guarda compartilhada de INSERT',
  $$select string_agg(tgname, ',' order by tgname collate "C") from pg_trigger where tgrelid = 'public.profiles'::regclass and not tgisinternal$$,
  'profiles_guard_insert_role,profiles_guard_role');
select tests.query_true('a guarda de INSERT é a compartilhada (public), SECURITY INVOKER, search_path vazio, sem EXECUTE para a API',
  $$select not p.prosecdef
       and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=""'
       and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
       and not has_function_privilege('anon', p.oid, 'EXECUTE')
     from pg_proc p where p.oid = 'public.guard_profile_insert_role()'::regprocedure$$);
select tests.query_true('a guarda do financeiro em profiles não existe mais',
  $$select not exists (select 1 from pg_trigger where tgrelid = 'public.profiles'::regclass and tgname = 'finance_profiles_insert_role_guard_trg')
       and to_regprocedure('finance_private.guard_profile_insert_role()') is null$$);
select tests.query_is('colunas de profiles (histórico + crm_access do CRM)',
  $$select string_agg(attname, ',' order by attname collate "C") from pg_attribute
     where attrelid = 'public.profiles'::regclass and attnum > 0 and not attisdropped$$,
  'assigned_employee_id,avatar_url,company_name,contact_info,crm_access,email,full_name,id,job_title,role,updated_at');
select tests.query_true('is_admin() continua super_admin OU manager (partner e sales_trial fora)',
  $$select pg_get_functiondef('public.is_admin()'::regprocedure) ilike '%role in (''super_admin'', ''manager'')%'$$);
select tests.query_true('is_team() é a equipe de entrega: super_admin, partner, manager, employee, employee_dev',
  $$select pg_get_functiondef('public.is_team()'::regprocedure) ilike '%role in (''super_admin'', ''partner'', ''manager'', ''employee'', ''employee_dev'')%'$$);
select tests.query_true('grants de profiles: authenticated sem INSERT/DELETE de tabela, UPDATE só por coluna (sem role)',
  $$select not has_table_privilege('authenticated', 'public.profiles', 'INSERT')
       and not has_table_privilege('authenticated', 'public.profiles', 'DELETE')
       and has_table_privilege('authenticated', 'public.profiles', 'SELECT')
       and not has_table_privilege('authenticated', 'public.profiles', 'UPDATE')
       and has_column_privilege('authenticated', 'public.profiles', 'full_name', 'UPDATE')
       and not has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE')
       and not has_column_privilege('authenticated', 'public.profiles', 'crm_access', 'UPDATE')$$);

select tests.note('helpers globais por papel (is_admin/is_team são do painel; o módulo não os usa)');
select tests.login('p_partner');
select tests.query_true('partner: is_team() sim, is_admin() não', $$select public.is_team() and not public.is_admin()$$);
select tests.login('p_trial');
select tests.query_true('sales_trial: nem is_team() nem is_admin()', $$select not public.is_team() and not public.is_admin()$$);
select tests.login('p_dev');
select tests.query_true('employee_dev: is_team() sim, is_admin() não', $$select public.is_team() and not public.is_admin()$$);
select tests.login('p_sdr');
select tests.query_true('sdr: nem is_team() nem is_admin()', $$select not public.is_team() and not public.is_admin()$$);
select tests.login('p_mgr');
select tests.query_true('manager: is_team() e is_admin()', $$select public.is_team() and public.is_admin()$$);
select tests.login('p_cli');
select tests.query_true('client: nem is_team() nem is_admin()', $$select not public.is_team() and not public.is_admin()$$);
select tests.logout();

select tests.note('o SQL do módulo trata papéis por texto: os sete internos são internos');
select tests.login('p_sa');
select tests.query_true('pt_is_super_admin() verdadeiro para super_admin', $$select private.pt_is_super_admin()$$);
select tests.query_true('pt_is_internal() verdadeiro para super_admin', $$select private.pt_is_internal()$$);
select tests.query_is('pt_current_role() devolve o papel', $$select private.pt_current_role()$$, 'super_admin');
select tests.login('p_mgr');
select tests.query_true('pt_is_internal() verdadeiro para manager', $$select private.pt_is_internal()$$);
select tests.query_true('pt_is_super_admin() FALSO para manager', $$select not private.pt_is_super_admin()$$);
select tests.query_is('pt_current_role() = manager', $$select private.pt_current_role()$$, 'manager');
select tests.login('p_emp');
select tests.query_true('pt_is_internal() verdadeiro para employee', $$select private.pt_is_internal()$$);
select tests.query_true('pt_is_super_admin() falso para employee', $$select not private.pt_is_super_admin()$$);
select tests.login('p_partner');
select tests.query_true('pt_is_internal() verdadeiro para partner; pt_is_super_admin() falso', $$select private.pt_is_internal() and not private.pt_is_super_admin()$$);
select tests.login('p_trial');
select tests.query_true('pt_is_internal() verdadeiro para sales_trial; pt_is_super_admin() falso', $$select private.pt_is_internal() and not private.pt_is_super_admin()$$);
select tests.login('p_dev');
select tests.query_true('pt_is_internal() verdadeiro para employee_dev; pt_is_super_admin() falso', $$select private.pt_is_internal() and not private.pt_is_super_admin()$$);
select tests.login('p_sdr');
select tests.query_true('pt_is_internal() verdadeiro para sdr; pt_is_super_admin() falso', $$select private.pt_is_internal() and not private.pt_is_super_admin()$$);
select tests.login('p_cli');
select tests.query_true('pt_is_internal() FALSO para client', $$select not private.pt_is_internal()$$);
select tests.query_true('pt_is_super_admin() falso para client', $$select not private.pt_is_super_admin()$$);
select tests.query_is('pt_current_role() = client', $$select private.pt_current_role()$$, 'client');
select tests.logout();
select tests.create_user('p_ghost', null);
select tests.login('p_ghost');
select tests.query_true('pt_is_internal() falso (não nulo) sem perfil', $$select private.pt_is_internal() is false$$);
select tests.query_true('pt_is_super_admin() falso (não nulo) sem perfil', $$select private.pt_is_super_admin() is false$$);
select tests.query_true('pt_current_role() nulo sem perfil', $$select private.pt_current_role() is null$$);
select tests.login_without_sub();
select tests.query_true('pt_is_internal() falso sem sub no JWT', $$select private.pt_is_internal() is false$$);
select tests.login_anon();
select tests.denied('anon não usa o schema private', $$select private.pt_is_internal()$$);
select tests.logout();

select tests.done();
rollback;
