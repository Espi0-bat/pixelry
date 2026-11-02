-- 33 — Diretório public.ponto_people() (§3.6): super_admin vê todos os perfis
-- internos; os demais veem a si mesmos ∪ criadores/responsáveis das tarefas em
-- que são criadores/responsáveis ∪ autores dos eventos dessas tarefas ∪
-- criadores das entregas dessas tarefas ∪ autores de auditorias do PRÓPRIO
-- ponto. Não interno → vazio. full_name nunca nulo.
begin;

select tests.create_user('sa', 'super_admin');
select tests.create_user('sa2', 'super_admin');
select tests.create_user('sa3', 'super_admin');
select tests.create_user('sa4', 'super_admin');
select tests.create_user('mgr', 'manager');
select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.create_user('emp3', 'employee');
select tests.create_user('noname', 'employee');
select tests.create_user('cli', 'client');
select tests.create_user('ghost', null);
select tests.lives('perfil interno sem nome', $$update public.profiles set full_name = null where id = tests.uid('noname')$$);
select tests.new_id('t1');
select tests.new_id('t2');

select tests.note('formato');
select tests.query_is('retorna TABLE(id uuid, full_name text, role text)',
  $$select pg_get_function_result('public.ponto_people()'::regprocedure)$$, 'TABLE(id uuid, full_name text, role text)');

select tests.note('super_admin: todos os internos');
select tests.login('sa');
select tests.rows_eq('9 perfis internos (sem client e sem quem não tem perfil)', $$select 1 from public.ponto_people()$$, 9);
select tests.rows_eq('client fora', $$select 1 from public.ponto_people() where id = tests.uid('cli')$$, 0);
select tests.rows_eq('sem perfil fora', $$select 1 from public.ponto_people() where id = tests.uid('ghost')$$, 0);
select tests.query_is('papel devolvido como texto', $$select role from public.ponto_people() where id = tests.uid('mgr')$$, 'manager');
select tests.query_is('full_name nulo vira string vazia', $$select full_name from public.ponto_people() where id = tests.uid('noname')$$, '');
select tests.query_is('full_name preenchido', $$select full_name from public.ponto_people() where id = tests.uid('emp')$$, 'Pessoa emp');
select tests.query_true('sem ids repetidos', $$select count(*) = count(distinct id) from public.ponto_people()$$);

select tests.note('employee sem relações: só ele mesmo');
select tests.login('emp');
select tests.query_is('emp vê só a si', $$select string_agg(id::text, ',') from public.ponto_people()$$, tests.uid('emp')::text);

select tests.note('relações por tarefa');
select tests.login('sa');
select tests.step('sa cria t1 para emp', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('t1'), 'Campanha', tests.uid('emp'))$$);
select tests.login('sa3');
select tests.step('sa3 muda a prioridade de t1 (evento)', $$update public.work_tasks set priority = 'high' where id = tests.uvar('t1')$$);
select tests.login('sa4');
select tests.step('sa4 entrega em t1', $$insert into public.work_deliverables (id, task_id, title) values (gen_random_uuid(), tests.uvar('t1'), 'Peças')$$);
select tests.login('emp');
select tests.step('emp cria t2 para si', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('t2'), 'Minha tarefa', auth.uid())$$);
select tests.login('sa');
select tests.step('sa reatribui t2 para emp3 (emp continua criador)', $$update public.work_tasks set assignee_id = tests.uid('emp3') where id = tests.uvar('t2')$$);

select tests.note('relação pelo próprio ponto');
select tests.login('sa2');
select tests.step('sa2 lança uma jornada para emp', $$select public.time_create_manual_shift(tests.uid('emp'), tests.brt('2026-10-28 08:00'), tests.brt('2026-10-28 12:00'), '[]'::jsonb, 'Lançado pelo administrador')$$);

select tests.login('emp');
select tests.rows_eq('emp: eu, sa (criador de t1), sa3 (evento), sa4 (entrega), emp3 (responsável de t2), sa2 (auditoria do meu ponto)',
  $$select 1 from public.ponto_people()$$, 6);
select tests.query_true('… exatamente essas pessoas',
  $$select array_agg(id order by id) = array(select unnest(array[tests.uid('emp'), tests.uid('sa'), tests.uid('sa2'), tests.uid('sa3'), tests.uid('sa4'), tests.uid('emp3')]) order by 1)
     from public.ponto_people()$$);
select tests.rows_eq('… emp2 e mgr não aparecem', $$select 1 from public.ponto_people() where id in (tests.uid('emp2'), tests.uid('mgr'))$$, 0);
select tests.query_true('sem ids repetidos', $$select count(*) = count(distinct id) from public.ponto_people()$$);

select tests.login('emp3');
select tests.rows_eq('emp3: eu, emp (criador de t2), sa (autor da reatribuição e do evento)', $$select 1 from public.ponto_people()$$, 3);
select tests.rows_eq('… não vê sa2 (auditoria do ponto de OUTRA pessoa)', $$select 1 from public.ponto_people() where id = tests.uid('sa2')$$, 0);

select tests.login('emp2');
select tests.query_is('emp2 sem relações: só ela', $$select string_agg(id::text, ',') from public.ponto_people()$$, tests.uid('emp2')::text);
select tests.login('mgr');
select tests.query_is('manager sem relações: só ele (não vê a equipe)', $$select string_agg(id::text, ',') from public.ponto_people()$$, tests.uid('mgr')::text);

select tests.note('não internos');
select tests.login('cli');
select tests.rows_eq('client → vazio', $$select 1 from public.ponto_people()$$, 0);
select tests.login('ghost');
select tests.rows_eq('sem perfil → vazio', $$select 1 from public.ponto_people()$$, 0);
select tests.login_without_sub();
select tests.rows_eq('JWT sem sub → vazio', $$select 1 from public.ponto_people()$$, 0);
select tests.login_anon();
select tests.denied('anon → sem EXECUTE', $$select 1 from public.ponto_people()$$);

select tests.done();
rollback;
