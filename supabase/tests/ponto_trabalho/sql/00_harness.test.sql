-- 00 — Autoteste do harness: stub do Supabase + helpers.
-- Não depende da migration do módulo (roda também com --somente-harness).
-- Confere que o stub reproduz o que as migrations versionadas descrevem e que
-- os helpers detectam erro, ausência de erro e trocam de papel de verdade.
begin;

select tests.note('usuários de teste e handle_new_user');
select tests.create_user('sa', 'super_admin');
select tests.create_user('mgr', 'manager');
select tests.create_user('emp', 'employee');
select tests.create_user('cli', 'client');
select tests.create_user('ghost', null);

select tests.admin_rows('handle_new_user criou um perfil por usuário com papel',
  $$select 1 from public.profiles p
     where p.id in (tests.uid('sa'), tests.uid('mgr'), tests.uid('emp'), tests.uid('cli'))$$, 4);
select tests.admin_rows('"desconhecido" fica sem linha em profiles',
  $$select 1 from public.profiles p where p.id = tests.uid('ghost')$$, 0);
select tests.admin_query_is('papel gravado no perfil',
  $$select string_agg(p.role, ',' order by p.role) from public.profiles p
     where p.id in (tests.uid('sa'), tests.uid('mgr'), tests.uid('emp'), tests.uid('cli'))$$,
  'client,employee,manager,super_admin');

select tests.note('login/logout trocam o papel real e o JWT');
select tests.eq('sessão começa como postgres', current_user::text, 'postgres');
select tests.login('emp');
select tests.eq('login → current_user = authenticated', current_user::text, 'authenticated');
select tests.eq('login → session_user continua o da conexão', session_user::text, 'postgres');
select tests.is('login → auth.uid() = id do usuário', auth.uid(), tests.uid('emp'));
select tests.eq('login → auth.role() = authenticated', auth.role(), 'authenticated');
select tests.ok('login → auth.email() preenchido', auth.email() like 'emp.%@teste.local');
select tests.login('sa');
select tests.is('troca direta de usuário', auth.uid(), tests.uid('sa'));
select tests.login_anon();
select tests.eq('login_anon → current_user = anon', current_user::text, 'anon');
select tests.ok('login_anon → auth.uid() nulo', auth.uid() is null);
select tests.login_without_sub();
select tests.eq('JWT sem sub → authenticated', current_user::text, 'authenticated');
select tests.ok('JWT sem sub → auth.uid() nulo', auth.uid() is null);
select tests.login_service();
select tests.eq('login_service → service_role', current_user::text, 'service_role');
select tests.logout();
select tests.eq('logout → volta a postgres', current_user::text, 'postgres');
select tests.ok('logout → auth.uid() nulo', auth.uid() is null);

select tests.note('banco descartável fiel ao Supabase');
select tests.eq('server_encoding = UTF8 (como o Supabase; char_length conta caracteres)', current_setting('server_encoding'), 'UTF8');
select tests.is('char_length conta caracteres, não bytes', char_length('ação'), 4);

select tests.note('helpers de asserção');
select tests.ok('_try: SQL sem erro → sqlstate nulo',
  (select t.o_sqlstate is null from tests._try('select 1') t));
select tests.eq('_try: divisão por zero → 22012',
  (select t.o_sqlstate from tests._try('select 1/0') t), '22012');
select tests.eq('_try: raise com código → message exata',
  (select t.o_message from tests._try($q$do $b$ begin raise exception 'shift_already_open' using errcode = 'P0001'; end $b$$q$) t),
  'shift_already_open');
select tests.eq('_try: constraint_name exposto',
  (select t.o_constraint from tests._try($$insert into public.profiles (id, role) values (gen_random_uuid(), 'x')$$) t),
  'profiles_role_check');
select tests.capture('try_ins',
  $$select (tests._try($q$insert into auth.users (email) values ('sonda@teste.local')$q$)).o_sqlstate$$);
select tests.admin_rows('_try desfaz o efeito mesmo sem erro',
  $$select 1 from auth.users where email = 'sonda@teste.local'$$, 0);
select tests.throws('throws: message + sqlstate exatos',
  $q$do $b$ begin raise exception 'no_open_shift' using errcode = 'P0001'; end $b$$q$, 'no_open_shift', 'P0001');
select tests.throws_like('throws_like: padrão', $$select 1/0$$, 'division%', '22012');
select tests.throws_constraint('throws_constraint: nome da constraint',
  $$insert into public.profiles (id, role) values (gen_random_uuid(), 'x')$$, '23514', 'profiles_role_check');
select tests.eq('_try: detail exposto',
  (select t.o_detail from tests._try($q$do $b$ begin raise exception 'no_open_break' using errcode = 'P0001', detail = 'Não há intervalo aberto.'; end $b$$q$) t),
  'Não há intervalo aberto.');
select tests.ok('_try: detail nulo quando não há erro',
  (select t.o_detail is null from tests._try('select 1') t));
select tests.throws_detail('throws_detail: message + sqlstate + detail exatos',
  $q$do $b$ begin raise exception 'no_open_break' using errcode = 'P0001', detail = 'Não há intervalo aberto.'; end $b$$q$,
  'no_open_break', 'P0001', 'Não há intervalo aberto.');
-- Controles negativos do próprio helper: com client_min_messages acima de
-- NOTICE o runner não recebe a asserção interna (não conta), e o valor de
-- retorno mostra se o helper reprovou como devia.
set local client_min_messages = warning;
select tests.set_var('td_wrong', tests.throws_detail('x',
  $q$do $b$ begin raise exception 'no_open_break' using errcode = 'P0001', detail = 'Não há intervalo aberto.'; end $b$$q$,
  'no_open_break', 'P0001', 'Outra frase.')::text);
select tests.set_var('td_missing', tests.throws_detail('x',
  $q$do $b$ begin raise exception 'no_open_break' using errcode = 'P0001'; end $b$$q$,
  'no_open_break', 'P0001', 'Não há intervalo aberto.')::text);
select tests.set_var('td_state', tests.throws_detail('x',
  $q$do $b$ begin raise exception 'no_open_break' using errcode = '42501', detail = 'Não há intervalo aberto.'; end $b$$q$,
  'no_open_break', 'P0001', 'Não há intervalo aberto.')::text);
select tests.set_var('td_noerr', tests.throws_detail('x', 'select 1', 'no_open_break', 'P0001', 'Não há intervalo aberto.')::text);
set local client_min_messages = notice;
select tests.eq('throws_detail reprova detail diferente (controle)', tests.var('td_wrong'), 'false');
select tests.eq('throws_detail reprova detail ausente (controle)', tests.var('td_missing'), 'false');
select tests.eq('throws_detail reprova SQLSTATE diferente (controle)', tests.var('td_state'), 'false');
select tests.eq('throws_detail reprova ausência de erro (controle)', tests.var('td_noerr'), 'false');
select tests.affects('affects conta linhas', $$update public.profiles set job_title = 'x' where id = tests.uid('emp')$$, 1);
select tests.rows_eq('rows_eq conta linhas', $$select * from generate_series(1, 3)$$, 3);
select tests.capture('cap', $$select 40 + 2$$);
select tests.eq('capture guarda o valor', tests.var('cap'), '42');
select tests.set_var('nao_json', 'x{');
select tests.ok('jvar inválido → nulo (sem abortar)', tests.jvar('nao_json') is null);
select tests.ok('uvar inválido → nulo (sem abortar)', tests.uvar('nao_json') is null);
select tests.is('brt converte relógio de Brasília', tests.brt('2026-10-05 22:00'), '2026-10-06 01:00:00+00'::timestamptz);
select tests.eq('keys lista as chaves ordenadas', tests.keys('{"b":1,"a":2}'::jsonb), 'a,b');
select tests.is('today_brt é a data de Brasília', tests.today_brt(), (now() at time zone 'America/Sao_Paulo')::date);

select tests.note('baseline + migrations: profiles no estado integrado');
select tests.query_is('profiles_role_check com os oito papéis do app (20261102120000)',
  $$select pg_get_constraintdef(c.oid) from pg_constraint c
     where c.conrelid = 'public.profiles'::regclass and c.conname = 'profiles_role_check'$$,
  $$CHECK ((role = ANY (ARRAY['super_admin'::text, 'partner'::text, 'manager'::text, 'sales_trial'::text, 'employee_dev'::text, 'employee'::text, 'sdr'::text, 'client'::text])))$$);
select tests.query_is('policies de profiles (estado final)',
  $$select string_agg(polname || ':' || polcmd::text, ',' order by polname) from pg_policy where polrelid = 'public.profiles'::regclass$$,
  'Admin full access:*,Users can view own profile:r,employees_see_assigned_clients:r,profiles_update_own:w,team_members_see_each_other:r');
select tests.ok('authenticated SEM INSERT e DELETE de tabela em profiles (20261102120000 fechou o furo §6.1)',
  not has_table_privilege('authenticated', 'public.profiles', 'INSERT')
  and not has_table_privilege('authenticated', 'public.profiles', 'DELETE'));
select tests.ok('authenticated sem UPDATE em profiles.role', not has_column_privilege('authenticated', 'public.profiles', 'role', 'UPDATE'));
select tests.ok('authenticated com UPDATE em profiles.full_name', has_column_privilege('authenticated', 'public.profiles', 'full_name', 'UPDATE'));
select tests.ok('anon sem INSERT/UPDATE/DELETE em profiles',
  not has_table_privilege('anon', 'public.profiles', 'INSERT')
  and not has_table_privilege('anon', 'public.profiles', 'UPDATE')
  and not has_table_privilege('anon', 'public.profiles', 'DELETE'));
select tests.ok('is_admin/is_team: EXECUTE para anon e authenticated, não para PUBLIC',
  has_function_privilege('anon', 'public.is_admin()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.is_team()', 'EXECUTE')
  and not exists (select 1 from pg_proc p, unnest(p.proacl) a
                   where p.oid in ('public.is_admin()'::regprocedure, 'public.is_team()'::regprocedure)
                     and a::text like '=%'));
select tests.ok('handle_new_user sem EXECUTE para authenticated',
  not has_function_privilege('authenticated', 'public.handle_new_user()', 'EXECUTE'));

select tests.login('mgr');
select tests.ok('is_admin() inclui manager', public.is_admin());
select tests.rows_eq('manager vê todos os perfis (Admin full access)',
  $$select 1 from public.profiles where id in (tests.uid('sa'), tests.uid('mgr'), tests.uid('emp'), tests.uid('cli'))$$, 4);
select tests.login('emp');
select tests.ok('is_admin() falso para employee', not public.is_admin());
select tests.ok('is_team() verdadeiro para employee', public.is_team());
select tests.rows_eq('employee vê o próprio perfil e a equipe, não o cliente',
  $$select 1 from public.profiles where id in (tests.uid('sa'), tests.uid('mgr'), tests.uid('emp'), tests.uid('cli'))$$, 3);
select tests.throws('profiles_guard_role: employee não muda o próprio role (sem grant de coluna)',
  $$update public.profiles set role = 'super_admin' where id = auth.uid()$$, null, '42501');
select tests.affects('profiles_update_own: employee muda o próprio nome',
  $$update public.profiles set full_name = 'Novo nome' where id = auth.uid()$$, 1);
select tests.login('cli');
select tests.ok('is_team() falso para client', not public.is_team());
select tests.rows_eq('client vê só o próprio perfil',
  $$select 1 from public.profiles where id in (tests.uid('sa'), tests.uid('mgr'), tests.uid('emp'), tests.uid('cli'))$$, 1);
select tests.login_anon();
select tests.rows_eq('anon não vê perfis', $$select 1 from public.profiles$$, 0);
select tests.logout();

select tests.note('stub: privilégios padrão e papéis do Supabase');
create table public.pt_sonda (id int);
create function public.pt_sonda_fn() returns int language sql as 'select 1';
select tests.ok('tabela nova em public nasce com ALL (inclui MAINTAIN) para anon/authenticated',
  has_table_privilege('anon', 'public.pt_sonda', 'MAINTAIN')
  and has_table_privilege('authenticated', 'public.pt_sonda', 'INSERT')
  and has_table_privilege('authenticated', 'public.pt_sonda', 'UPDATE')
  and has_table_privilege('authenticated', 'public.pt_sonda', 'DELETE')
  and has_table_privilege('authenticated', 'public.pt_sonda', 'TRUNCATE'));
select tests.ok('função nova em public nasce com EXECUTE para PUBLIC e anon',
  has_function_privilege('anon', 'public.pt_sonda_fn()', 'EXECUTE')
  and exists (select 1 from pg_proc p, unnest(p.proacl) a
               where p.oid = 'public.pt_sonda_fn()'::regprocedure and a::text like '=X/%'));
create table public.pt_sonda_ident (seq bigint generated always as identity);
select tests.ok('sequência de coluna identity em public nasce com USAGE/SELECT/UPDATE para anon/authenticated',
  has_sequence_privilege('anon', pg_get_serial_sequence('public.pt_sonda_ident', 'seq'), 'UPDATE')
  and has_sequence_privilege('authenticated', pg_get_serial_sequence('public.pt_sonda_ident', 'seq'), 'USAGE')
  and has_sequence_privilege('authenticated', pg_get_serial_sequence('public.pt_sonda_ident', 'seq'), 'UPDATE'));
select tests.ok('service_role ignora RLS', (select rolbypassrls from pg_roles where rolname = 'service_role'));
select tests.ok('authenticator: LOGIN NOINHERIT, membro de anon/authenticated/service_role',
  (select rolcanlogin and not rolinherit from pg_roles where rolname = 'authenticator')
  and pg_has_role('authenticator', 'anon', 'MEMBER')
  and pg_has_role('authenticator', 'authenticated', 'MEMBER')
  and pg_has_role('authenticator', 'service_role', 'MEMBER'));
select tests.ok('anon/authenticated NOLOGIN NOINHERIT',
  (select bool_and(not rolcanlogin and not rolinherit) from pg_roles where rolname in ('anon', 'authenticated')));
select tests.ok('btree_gist disponível no servidor', exists (select 1 from pg_available_extensions where name = 'btree_gist'));

select tests.done();
rollback;
