-- 30 — Tarefas: RLS de SELECT/INSERT, grants por coluna, validações, sem
-- DELETE, e o evento "created" (§2, §3.5). Como authenticated; inserts sem
-- RETURNING (a RLS de SELECT não entra no INSERT): conta-se linhas.
begin;

select tests.create_user('sa', 'super_admin');
select tests.create_user('mgr', 'manager');
select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.create_user('cli', 'client');
select tests.create_user('ghost', null);
select tests.new_id('t1');
select tests.new_id('t2');
select tests.new_id('t3');
select tests.new_id('t4');
select tests.new_id('t5');
select tests.new_id('t6');
select tests.new_id('tx');

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('super_admin cria para qualquer pessoa interna ou sem responsável');
select tests.login('sa');
select tests.affects('super_admin: tarefa para employee',
  $$insert into public.work_tasks (id, title, description, assignee_id, due_date)
    values (tests.uvar('t1'), 'Arte do post de segunda', 'Formato 1080x1350', tests.uid('emp'), '2026-11-10')$$, 1);
select tests.affects('super_admin: tarefa sem responsável', $$insert into public.work_tasks (id, title) values (tests.uvar('t2'), 'Organizar o drive')$$, 1);
select tests.affects('super_admin: tarefa urgente para manager',
  $$insert into public.work_tasks (id, title, assignee_id, priority) values (tests.uvar('t3'), 'Proposta do cliente X', tests.uid('mgr'), 'urgent')$$, 1);
select tests.throws('super_admin: responsável client → invalid_assignee 23514',
  $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', tests.uid('cli'))$$, 'invalid_assignee', '23514');
select tests.throws('super_admin: responsável sem perfil → invalid_assignee 23514',
  $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', tests.uid('ghost'))$$, 'invalid_assignee', '23514');
select tests.throws('super_admin: responsável inexistente → invalid_assignee 23514',
  $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', gen_random_uuid())$$, 'invalid_assignee', '23514');
select tests.logout();
select tests.admin_query_is('created_by forçado = auth.uid(); padrões medium/todo/rank 2; completed_at nulo',
  $$select (created_by = tests.uid('sa') and priority = 'medium' and status = 'todo' and priority_rank = 2 and completed_at is null)::text
     from public.work_tasks where id = tests.uvar('t1')$$, 'true');
select tests.admin_query_is('created_at e updated_at = now()',
  $$select (created_at = now() and updated_at = now())::text from public.work_tasks where id = tests.uvar('t1')$$, 'true');
select tests.admin_query_is('priority_rank de urgent = 0', $$select priority_rank::text from public.work_tasks where id = tests.uvar('t3')$$, '0');

select tests.note('manager e employee criam só para si');
select tests.login('mgr');
select tests.affects('manager: tarefa para si', $$insert into public.work_tasks (id, title, assignee_id, priority) values (tests.uvar('t4'), 'Revisar contrato', auth.uid(), 'high')$$, 1);
select tests.rls_denied('manager: tarefa para employee → RLS', $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', tests.uid('emp'))$$);
select tests.rls_denied('manager: tarefa sem responsável → RLS', $$insert into public.work_tasks (id, title) values (gen_random_uuid(), 'x')$$);
select tests.login('emp');
select tests.affects('employee: tarefa para si', $$insert into public.work_tasks (id, title, assignee_id, priority) values (tests.uvar('t5'), 'Estudar o briefing', auth.uid(), 'low')$$, 1);
select tests.rls_denied('employee: tarefa para outra pessoa → RLS', $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', tests.uid('emp2'))$$);
select tests.rls_denied('employee: tarefa sem responsável → RLS', $$insert into public.work_tasks (id, title) values (gen_random_uuid(), 'x')$$);
select tests.denied('employee: enviar created_by → sem grant de coluna',
  $$insert into public.work_tasks (id, title, assignee_id, created_by) values (gen_random_uuid(), 'x', auth.uid(), tests.uid('sa'))$$);
select tests.denied('employee: enviar created_at → sem grant', $$insert into public.work_tasks (id, title, assignee_id, created_at) values (gen_random_uuid(), 'x', auth.uid(), now())$$);
select tests.denied('employee: enviar updated_at → sem grant', $$insert into public.work_tasks (id, title, assignee_id, updated_at) values (gen_random_uuid(), 'x', auth.uid(), now())$$);
select tests.denied('employee: enviar completed_at → sem grant', $$insert into public.work_tasks (id, title, assignee_id, completed_at) values (gen_random_uuid(), 'x', auth.uid(), now())$$);
select tests.throws_constraint('repetir o mesmo id → 23505 work_tasks_pkey (repetição idempotente do app)',
  $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('t5'), 'Estudar o briefing', auth.uid())$$, '23505', 'work_tasks_pkey');

select tests.note('validações');
select tests.throws('título só com espaços → 23514', $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), '   ', auth.uid())$$, null, '23514');
select tests.throws('título com 201 caracteres → 23514', $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), repeat('t', 201), auth.uid())$$, null, '23514');
select tests.affects('título com 200 caracteres', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('t6'), repeat('t', 200), auth.uid())$$, 1);
select tests.throws('descrição com 10001 caracteres → 23514',
  $$insert into public.work_tasks (id, title, assignee_id, description) values (gen_random_uuid(), 'x', auth.uid(), repeat('d', 10001))$$, null, '23514');
select tests.throws('prioridade fora da lista → 23514', $$insert into public.work_tasks (id, title, assignee_id, priority) values (gen_random_uuid(), 'x', auth.uid(), 'critical')$$, null, '23514');
select tests.throws('status fora da lista → 23514', $$insert into public.work_tasks (id, title, assignee_id, status) values (gen_random_uuid(), 'x', auth.uid(), 'archived')$$, null, '23514');

select tests.note('client, desconhecido, anon');
-- Client e "desconhecido" não criam tarefa. O contrato garante a negação
-- (RLS: "interno e …"), mas não fixa QUAL camada nega primeiro: um trigger
-- BEFORE roda antes do WITH CHECK e pode levantar um código do contrato
-- (not_allowed / invalid_assignee). Aceita-se qualquer um deles, desde que
-- SQLSTATE 42501/23514 e nenhuma linha criada (ver lacuna no relatório).
select tests.login('cli');
select tests.query_true('client: criar tarefa para si → negado (RLS, not_allowed ou invalid_assignee)',
  $$select (t.o_sqlstate = '42501' and (t.o_message = 'not_allowed' or t.o_message like 'new row violates row-level security policy%'))
        or (t.o_sqlstate = '23514' and t.o_message = 'invalid_assignee')
     from tests._try($q$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', auth.uid())$q$) t$$);
select tests.query_true('client: criar tarefa sem responsável → negado com 42501 (RLS ou not_allowed)',
  $$select t.o_sqlstate = '42501' and (t.o_message = 'not_allowed' or t.o_message like 'new row violates row-level security policy%')
     from tests._try($q$insert into public.work_tasks (id, title) values (gen_random_uuid(), 'x')$q$) t$$);
select tests.query_true('client: criar tarefa para pessoa interna → negado com 42501 (RLS ou not_allowed)',
  $$select t.o_sqlstate = '42501' and (t.o_message = 'not_allowed' or t.o_message like 'new row violates row-level security policy%')
     from tests._try($q$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', tests.uid('emp'))$q$) t$$);
select tests.login('ghost');
select tests.query_true('sem perfil: criar tarefa para si → negado (RLS, not_allowed ou invalid_assignee)',
  $$select (t.o_sqlstate = '42501' and (t.o_message = 'not_allowed' or t.o_message like 'new row violates row-level security policy%'))
        or (t.o_sqlstate = '23514' and t.o_message = 'invalid_assignee')
     from tests._try($q$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', auth.uid())$q$) t$$);
select tests.query_true('sem perfil: criar tarefa sem responsável → negado com 42501 (RLS ou not_allowed)',
  $$select t.o_sqlstate = '42501' and (t.o_message = 'not_allowed' or t.o_message like 'new row violates row-level security policy%')
     from tests._try($q$insert into public.work_tasks (id, title) values (gen_random_uuid(), 'x')$q$) t$$);
select tests.admin_rows('verdade: nenhuma tarefa criada por client ou sem perfil',
  $$select 1 from public.work_tasks where created_by in (tests.uid('cli'), tests.uid('ghost'))$$, 0);
select tests.login_anon();
select tests.denied('anon: INSERT work_tasks', $$insert into public.work_tasks (id, title) values (gen_random_uuid(), 'x')$$);
select tests.denied('anon: SELECT work_tasks', $$select 1 from public.work_tasks$$);
select tests.denied('anon: SELECT work_task_events', $$select 1 from public.work_task_events$$);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('visibilidade (6 tarefas: t1 sa→emp, t2 sa→ninguém, t3 sa→mgr, t4 mgr, t5 emp, t6 emp)');
select tests.login('sa');
select tests.rows_eq('super_admin vê todas', $$select 1 from public.work_tasks$$, 6);
select tests.query_is('ordem por prioridade (priority_rank)',
  $$select string_agg(priority, ',' order by priority_rank, title) from public.work_tasks where id in (tests.uvar('t3'), tests.uvar('t4'), tests.uvar('t1'), tests.uvar('t5'))$$,
  'urgent,high,medium,low');
select tests.login('mgr');
select tests.rows_eq('manager: atribuída a mim (t3) + criada por mim (t4)', $$select 1 from public.work_tasks$$, 2);
select tests.rows_eq('manager não vê a tarefa do employee', $$select 1 from public.work_tasks where id = tests.uvar('t1')$$, 0);
select tests.login('emp');
select tests.rows_eq('employee: t1 (atribuída) + t5/t6 (criadas)', $$select 1 from public.work_tasks$$, 3);
select tests.rows_eq('"Minhas tarefas" do employee (assignee = eu)', $$select 1 from public.work_tasks where assignee_id = auth.uid()$$, 3);
select tests.rows_eq('employee não vê a sem responsável do super_admin', $$select 1 from public.work_tasks where id = tests.uvar('t2')$$, 0);
select tests.login('emp2');
select tests.rows_eq('employee sem tarefas vê 0', $$select 1 from public.work_tasks$$, 0);
select tests.login('cli');
select tests.rows_eq('client vê 0', $$select 1 from public.work_tasks$$, 0);
select tests.rows_eq('client vê 0 eventos', $$select 1 from public.work_task_events$$, 0);
select tests.login('ghost');
select tests.rows_eq('sem perfil vê 0', $$select 1 from public.work_tasks$$, 0);

select tests.note('sem DELETE ("cancelar = excluir")');
select tests.login('sa');
select tests.denied('super_admin: DELETE work_tasks', $$delete from public.work_tasks where id = tests.uvar('t2')$$);
select tests.denied('super_admin: TRUNCATE work_tasks', $$truncate public.work_tasks cascade$$);
select tests.login('emp');
select tests.denied('employee: DELETE da própria tarefa', $$delete from public.work_tasks where id = tests.uvar('t5')$$);

select tests.note('evento "created"');
select tests.login('emp');
select tests.query_true('created: retrato exato de title/status/priority/assignee_id/due_date, autor = criador',
  $$select count(*) = 1 and bool_and(actor_id = tests.uid('sa') and changes = jsonb_build_object(
       'title', 'Arte do post de segunda', 'status', 'todo', 'priority', 'medium',
       'assignee_id', tests.uid('emp'), 'due_date', '2026-11-10'))
     from public.work_task_events where task_id = tests.uvar('t1') and action = 'created'$$);
select tests.query_true('created da tarefa do próprio employee: autor = ele, due_date nulo',
  $$select count(*) = 1 and bool_and(actor_id = auth.uid() and changes->'due_date' = 'null'::jsonb and changes->>'priority' = 'low')
     from public.work_task_events where task_id = tests.uvar('t5') and action = 'created'$$);
select tests.query_true('created_at do evento = clock_timestamp()',
  $$select bool_and(created_at > now()) from public.work_task_events where task_id in (tests.uvar('t1'), tests.uvar('t5'))$$);
select tests.rows_eq('employee vê os eventos das tarefas que vê (t1, t5, t6)', $$select 1 from public.work_task_events$$, 3);
select tests.login('mgr');
select tests.rows_eq('manager não vê eventos de tarefas alheias', $$select 1 from public.work_task_events where task_id = tests.uvar('t1')$$, 0);
select tests.login('sa');
select tests.rows_eq('super_admin vê todos os eventos (6 created)', $$select 1 from public.work_task_events where action = 'created'$$, 6);

select tests.note('evento de tarefa criada fora da API (postgres): actor_id nulo');
select tests.logout();
select tests.lives('postgres insere tarefa informando created_by',
  $$insert into public.work_tasks (id, title, assignee_id, created_by) values (tests.uvar('tx'), 'Migrada do painel', tests.uid('emp'), tests.uid('sa'))$$);
select tests.admin_query_is('… created_by respeitado para quem não é usuário final', $$select created_by::text from public.work_tasks where id = tests.uvar('tx')$$, tests.uid('sa')::text);
select tests.admin_query_is('… evento created com actor_id nulo',
  $$select (actor_id is null)::text from public.work_task_events where task_id = tests.uvar('tx') and action = 'created'$$, 'true');

select tests.done();
rollback;
