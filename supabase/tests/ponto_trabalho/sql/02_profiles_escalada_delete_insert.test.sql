-- 02 — Escalada de papel por DELETE+INSERT em profiles (era a pendência
-- global §6.1, resolvida pela migration de integração 20261102120000).
--
-- Pelas migrations antigas, "Admin full access" em profiles é FOR ALL com
-- is_admin() (inclui manager), authenticated tinha INSERT/DELETE de tabela e o
-- profiles_guard_role só cobre UPDATE. Um manager apagava o perfil de uma
-- segunda conta que controla e o reinseria com role = 'super_admin' — dois
-- pedidos PostgREST comuns. A conta passava a ser super_admin para o módulo
-- inteiro (pt_is_super_admin lê profiles.role) e enxergava o ponto de todos.
--
-- Agora authenticated não tem INSERT nem DELETE em profiles e, mesmo que um
-- grant seja reaberto, profiles_guard_insert_role só deixa a API criar perfil
-- como client. Cada asserção abaixo descreve o comportamento correto e passa.
begin;

select tests.create_user('mgr', 'manager');
select tests.create_user('alt', 'client');      -- segunda conta do manager (cadastro comum)
select tests.create_user('vitima', 'employee');
select tests.create_user('sa', 'super_admin');

-- Pré-requisito: os objetos do módulo usados abaixo existem. Se faltarem, é
-- falha REAL (o runner não deixa um módulo quebrado passar como pendência).
select tests.step('pré-requisito: objetos do módulo presentes',
  $$select 'private.pt_is_super_admin()'::regprocedure, 'public.time_shifts'::regclass,
           'public.time_review_shifts(jsonb, text)'::regprocedure, 'public.time_clock_in(uuid, text)'::regprocedure$$);

-- A vítima tem ponto registrado (pela RPC, como ela mesma).
select tests.login('vitima');
select tests.step('vítima bate a entrada', $$select public.time_clock_in()$$);

-- O ataque, como o manager, pedido a pedido.
select tests.login('mgr');
select tests.attempt('passo_delete', $$delete from public.profiles where id = tests.uid('alt')$$);
select tests.attempt('passo_insert', $$insert into public.profiles (id, full_name, email, role)
    values (tests.uid('alt'), 'Conta alternativa', 'alt@teste.local', 'super_admin')$$);
select tests.logout();
select tests.admin_capture('papel_final', $$select coalesce((select role from public.profiles where id = tests.uid('alt')), '(sem perfil)')$$);

select tests.ok('manager NÃO consegue apagar o perfil de outra pessoa',
  tests.var('passo_delete') is distinct from 'ok' or tests.var('papel_final') = 'client',
  'DELETE em profiles passou (Admin full access FOR ALL + grant DELETE de authenticated)');
select tests.ok('manager NÃO consegue inserir perfil com role super_admin',
  tests.var('passo_insert') is distinct from 'ok',
  'INSERT com role super_admin passou (WITH CHECK is_admin() aceita manager; guard só cobre UPDATE)');
select tests.eq('a segunda conta continua client', tests.var('papel_final'), 'client');

select tests.login('alt');
select tests.query_true('a segunda conta NÃO vira super_admin para o módulo', $$select not private.pt_is_super_admin()$$);
select tests.rows_eq('a segunda conta NÃO vê o ponto da vítima', $$select 1 from public.time_shifts where user_id = tests.uid('vitima')$$, 0);
select tests.query_true('a segunda conta NÃO revisa o ponto alheio (not_allowed)',
  $$select t.o_sqlstate = '42501' and t.o_message = 'not_allowed'
     from tests._try('select public.time_review_shifts(''[]''::jsonb)') t$$);

-- Controle: o caminho do UPDATE está fechado desde 20260902000050.
select tests.login('mgr');
select tests.throws('controle: UPDATE de role pelo manager é barrado (grant de coluna)',
  $$update public.profiles set role = 'super_admin' where id = tests.uid('mgr')$$, null, '42501');

select tests.done();
rollback;
