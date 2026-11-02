-- 01 — O schema atual (migrations versionadas) e o que o módulo NÃO pode mexer.
-- Documenta a pendência §6.2: profiles_role_check rejeita os papéis novos
-- (partner, sales_trial, employee_dev, sdr). O módulo não altera a constraint,
-- nem profiles, nem is_admin/is_team (contrato §1, §3.0, §6).
begin;

select tests.note('profiles_role_check aceita só os quatro papéis do histórico');
select tests.lives('aceita super_admin', $$select tests.create_user('p_sa', 'super_admin')$$);
select tests.lives('aceita manager', $$select tests.create_user('p_mgr', 'manager')$$);
select tests.lives('aceita employee', $$select tests.create_user('p_emp', 'employee')$$);
select tests.lives('aceita client', $$select tests.create_user('p_cli', 'client')$$);
select tests.throws_constraint('REJEITA partner (pendência §6.2)',
  $$select tests.create_user('p_partner', 'partner')$$, '23514', 'profiles_role_check');
select tests.throws_constraint('REJEITA sales_trial (pendência §6.2)',
  $$select tests.create_user('p_trial', 'sales_trial')$$, '23514', 'profiles_role_check');
select tests.throws_constraint('REJEITA employee_dev (pendência §6.2)',
  $$select tests.create_user('p_dev', 'employee_dev')$$, '23514', 'profiles_role_check');
select tests.throws_constraint('REJEITA sdr (pendência §6.2)',
  $$select tests.create_user('p_sdr', 'sdr')$$, '23514', 'profiles_role_check');
select tests.throws_constraint('rejeita o papel legado admin',
  $$select tests.create_user('p_admin', 'admin')$$, '23514', 'profiles_role_check');

select tests.note('o módulo não mexe em profiles nem nos helpers globais');
select tests.query_is('profiles_role_check continua com o texto da 20260608015308',
  $$select pg_get_constraintdef(c.oid) from pg_constraint c
     where c.conrelid = 'public.profiles'::regclass and c.conname = 'profiles_role_check'$$,
  $$CHECK ((role = ANY (ARRAY['super_admin'::text, 'manager'::text, 'employee'::text, 'client'::text])))$$);
select tests.query_is('constraints de profiles inalteradas',
  $$select string_agg(conname, ',' order by conname collate "C") from pg_constraint where conrelid = 'public.profiles'::regclass$$,
  'profiles_assigned_employee_id_fkey,profiles_id_fkey,profiles_pkey,profiles_role_check');
select tests.query_is('policies de profiles inalteradas (nenhuma do módulo)',
  $$select string_agg(polname, ',' order by polname collate "C") from pg_policy where polrelid = 'public.profiles'::regclass$$,
  'Admin full access,Users can view own profile,employees_see_assigned_clients,profiles_update_own,team_members_see_each_other');
select tests.query_is('triggers de profiles inalterados (só profiles_guard_role)',
  $$select string_agg(tgname, ',' order by tgname collate "C") from pg_trigger where tgrelid = 'public.profiles'::regclass and not tgisinternal$$,
  'profiles_guard_role');
select tests.query_is('colunas de profiles inalteradas',
  $$select string_agg(attname, ',' order by attname collate "C") from pg_attribute
     where attrelid = 'public.profiles'::regclass and attnum > 0 and not attisdropped$$,
  'assigned_employee_id,avatar_url,company_name,contact_info,email,full_name,id,job_title,role,updated_at');
select tests.query_true('is_admin() continua super_admin OU manager',
  $$select pg_get_functiondef('public.is_admin()'::regprocedure) ilike '%role IN (''super_admin'', ''manager'')%'$$);
select tests.query_true('is_team() continua super_admin/manager/employee',
  $$select pg_get_functiondef('public.is_team()'::regprocedure) ilike '%role in (''super_admin'', ''manager'', ''employee'')%'$$);
select tests.query_true('grants de profiles inalterados (authenticated: INSERT/DELETE de tabela, UPDATE só por coluna)',
  $$select has_table_privilege('authenticated', 'public.profiles', 'INSERT')
       and has_table_privilege('authenticated', 'public.profiles', 'DELETE')
       and not has_table_privilege('authenticated', 'public.profiles', 'UPDATE')
       and not has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE')$$);

select tests.note('o SQL do módulo trata papéis por texto: funciona com os quatro aceitos');
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
