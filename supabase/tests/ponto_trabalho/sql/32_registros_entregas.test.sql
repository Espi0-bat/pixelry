-- 32 — Registros de trabalho (work_logs) e entregas/links (work_deliverables),
-- §2/§3.5: só inclusão; vínculo com tarefa visível e com jornada PRÓPRIA não
-- anulada; entrega ligada a registro da MESMA tarefa e do mesmo autor;
-- visibilidade; validações; eventos log_added/deliverable_added sem vazar o
-- conteúdo privado do registro. Como authenticated, inserts sem RETURNING.
begin;

select tests.create_user('sa', 'super_admin');
select tests.create_user('mgr', 'manager');
select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.create_user('cli', 'client');
select tests.create_user('ghost', null);
select tests.new_id('ta');
select tests.new_id('te');
select tests.new_id('t2');
select tests.new_id('l1');
select tests.new_id('l2');
select tests.new_id('l3');
select tests.new_id('ls');
select tests.new_id('d1');
select tests.new_id('d2');
select tests.new_id('d3');
select tests.new_id('d4');

select tests.login('sa');
select tests.step('ta: super_admin → emp', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('ta'), 'Campanha de novembro', tests.uid('emp'))$$);
select tests.login('emp');
select tests.step('te: emp para si', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('te'), 'Estudo de referência', auth.uid())$$);
select tests.capture('s_closed', $$select public.time_create_manual_shift(null, tests.brt('2026-10-20 08:00'), tests.brt('2026-10-20 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')::jsonb->>'id'$$);
select tests.capture('s_void', $$select public.time_create_manual_shift(null, tests.brt('2026-10-21 08:00'), tests.brt('2026-10-21 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')::jsonb->>'id'$$);
select tests.step('anula s_void', $$select public.time_void_shift(tests.uvar('s_void'), 'Lancei no dia errado')$$);
select tests.capture('s_open', $$select public.time_clock_in()::jsonb->>'id'$$);
select tests.login('emp2');
select tests.step('t2: emp2 para si', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('t2'), 'Tarefa da emp2', auth.uid())$$);
select tests.capture('s2', $$select public.time_clock_in()::jsonb->>'id'$$);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('registros do employee');
select tests.login('emp');
select tests.affects('registro na tarefa atribuída + jornada aberta própria',
  $$insert into public.work_logs (id, task_id, shift_id, summary, result, minutes_spent)
    values (tests.uvar('l1'), tests.uvar('ta'), tests.uvar('s_open'), 'Fiz o layout dos stories', 'Três telas aprovadas', 30)$$, 1);
select tests.affects('registro sem tarefa e sem jornada', $$insert into public.work_logs (id, summary) values (tests.uvar('l2'), 'Reunião interna')$$, 1);
select tests.affects('registro em tarefa criada por mim + jornada encerrada própria, com data e 1440 min',
  $$insert into public.work_logs (id, task_id, shift_id, summary, minutes_spent, logged_on)
    values (tests.uvar('l3'), tests.uvar('te'), tests.uvar('s_closed'), 'Pesquisa de referências', 1440, '2026-10-20')$$, 1);
select tests.admin_query_is('user_id forçado = auth.uid(); created_at = now(); logged_on padrão = hoje em Brasília',
  $$select (user_id = tests.uid('emp') and created_at = now() and logged_on = tests.today_brt())::text from public.work_logs where id = tests.uvar('l1')$$, 'true');
select tests.rls_denied('registro em tarefa que não vejo → RLS 42501',
  $$insert into public.work_logs (id, task_id, summary) values (gen_random_uuid(), tests.uvar('t2'), 'Tentativa')$$);
select tests.rls_denied('registro em tarefa inexistente → RLS 42501',
  $$insert into public.work_logs (id, task_id, summary) values (gen_random_uuid(), gen_random_uuid(), 'Tentativa')$$);
select tests.rls_denied('registro ligado à jornada de OUTRA pessoa → RLS 42501',
  $$insert into public.work_logs (id, shift_id, summary) values (gen_random_uuid(), tests.uvar('s2'), 'Tentativa')$$);
select tests.rls_denied('registro ligado a jornada própria ANULADA → RLS 42501',
  $$insert into public.work_logs (id, shift_id, summary) values (gen_random_uuid(), tests.uvar('s_void'), 'Tentativa')$$);
-- Mesmo erro para jornada inexistente e jornada alheia: a RLS barra antes da
-- FK (23503), senão o vínculo viraria oráculo de "este id é jornada de alguém".
select tests.rls_denied('registro ligado a jornada INEXISTENTE → RLS 42501 (mesmo erro da alheia, não FK 23503)',
  $$insert into public.work_logs (id, shift_id, summary) values (gen_random_uuid(), gen_random_uuid(), 'Tentativa')$$);
select tests.denied('enviar user_id → sem grant de coluna', $$insert into public.work_logs (id, user_id, summary) values (gen_random_uuid(), tests.uid('emp2'), 'Tentativa')$$);
select tests.denied('enviar created_at → sem grant', $$insert into public.work_logs (id, summary, created_at) values (gen_random_uuid(), 'Tentativa', now())$$);
select tests.throws('resumo em branco → 23514', $$insert into public.work_logs (id, summary) values (gen_random_uuid(), '   ')$$, null, '23514');
select tests.throws('resumo com 4001 caracteres → 23514', $$insert into public.work_logs (id, summary) values (gen_random_uuid(), repeat('s', 4001))$$, null, '23514');
select tests.throws('resultado com 4001 caracteres → 23514', $$insert into public.work_logs (id, summary, result) values (gen_random_uuid(), 'ok', repeat('r', 4001))$$, null, '23514');
select tests.throws('0 minutos → 23514', $$insert into public.work_logs (id, summary, minutes_spent) values (gen_random_uuid(), 'ok', 0)$$, null, '23514');
select tests.throws('1441 minutos → 23514', $$insert into public.work_logs (id, summary, minutes_spent) values (gen_random_uuid(), 'ok', 1441)$$, null, '23514');
select tests.throws_constraint('mesmo id de novo → 23505 work_logs_pkey', $$insert into public.work_logs (id, summary) values (tests.uvar('l2'), 'Reunião interna')$$, '23505', 'work_logs_pkey');
select tests.denied('sem UPDATE em registros', $$update public.work_logs set summary = 'editado' where id = tests.uvar('l1')$$);
select tests.denied('sem DELETE em registros', $$delete from public.work_logs where id = tests.uvar('l1')$$);

select tests.note('registros do super_admin e de quem não é interno');
select tests.login('sa');
select tests.affects('super_admin registra em tarefa alheia (sem jornada)', $$insert into public.work_logs (id, task_id, summary) values (tests.uvar('ls'), tests.uvar('ta'), 'Revisei a campanha')$$, 1);
select tests.rls_denied('super_admin NÃO liga registro à jornada de outra pessoa',
  $$insert into public.work_logs (id, shift_id, summary) values (gen_random_uuid(), tests.uvar('s_open'), 'Tentativa')$$);
select tests.denied('super_admin também não edita registros', $$update public.work_logs set summary = 'editado'$$);
select tests.login('cli');
select tests.rls_denied('client não registra', $$insert into public.work_logs (id, summary) values (gen_random_uuid(), 'Tentativa')$$);
select tests.login('ghost');
select tests.rls_denied('sem perfil não registra', $$insert into public.work_logs (id, summary) values (gen_random_uuid(), 'Tentativa')$$);
select tests.login_anon();
select tests.denied('anon: INSERT work_logs', $$insert into public.work_logs (id, summary) values (gen_random_uuid(), 'Tentativa')$$);
select tests.denied('anon: SELECT work_logs', $$select 1 from public.work_logs$$);

select tests.note('visibilidade dos registros (privados ao autor; super_admin vê todos)');
select tests.login('emp');
select tests.rows_eq('employee vê os próprios 3', $$select 1 from public.work_logs$$, 3);
select tests.rows_eq('… e não o do super_admin na tarefa dele', $$select 1 from public.work_logs where id = tests.uvar('ls')$$, 0);
select tests.rows_eq('registros da jornada aberta (ShiftWorkLogsPanel)', $$select 1 from public.work_logs where shift_id = tests.uvar('s_open')$$, 1);
select tests.login('emp2');
select tests.rows_eq('outra employee vê 0', $$select 1 from public.work_logs$$, 0);
select tests.login('mgr');
select tests.rows_eq('manager vê 0', $$select 1 from public.work_logs$$, 0);
select tests.login('cli');
select tests.rows_eq('client vê 0', $$select 1 from public.work_logs$$, 0);
select tests.login('sa');
select tests.rows_eq('super_admin vê os 4', $$select 1 from public.work_logs$$, 4);

select tests.note('eventos log_added (só o id)');
select tests.login('emp');
select tests.query_true('log_added em ta: changes = {"log_id": l1}, autor employee',
  $$select count(*) = 1 and bool_and(actor_id = auth.uid() and changes = jsonb_build_object('log_id', tests.uvar('l1')))
     from public.work_task_events where task_id = tests.uvar('ta') and action = 'log_added' and changes->>'log_id' = tests.var('l1')$$);
select tests.query_true('o evento não carrega resumo, minutos nem jornada',
  $$select bool_and(tests.keys(changes) = 'log_id') from public.work_task_events where action = 'log_added'$$);
select tests.admin_rows('registro sem tarefa não gera evento', $$select 1 from public.work_task_events where changes->>'log_id' = tests.var('l2')$$, 0);
select tests.admin_rows('verdade: 3 log_added (l1, l3, ls)', $$select 1 from public.work_task_events where action = 'log_added'$$, 3);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('entregas');
select tests.login('emp');
select tests.affects('entrega em tarefa atribuída a mim, com link',
  $$insert into public.work_deliverables (id, task_id, title, url, notes) values (tests.uvar('d1'), tests.uvar('ta'), 'Arte final', 'https://exemplo.com/arte.png', 'Versão aprovada')$$, 1);
select tests.affects('entrega em tarefa criada por mim, ligada a registro meu da MESMA tarefa',
  $$insert into public.work_deliverables (id, task_id, work_log_id, title, url) values (tests.uvar('d2'), tests.uvar('te'), tests.uvar('l3'), 'Moodboard', 'http://exemplo.com/mood')$$, 1);
select tests.admin_query_is('created_by forçado = auth.uid(); created_at = now()',
  $$select (created_by = tests.uid('emp') and created_at = now())::text from public.work_deliverables where id = tests.uvar('d1')$$, 'true');
select tests.rls_denied('entrega ligada a registro de OUTRA tarefa → RLS 42501',
  $$insert into public.work_deliverables (id, task_id, work_log_id, title) values (gen_random_uuid(), tests.uvar('ta'), tests.uvar('l3'), 'Tentativa')$$);
select tests.rls_denied('entrega ligada a registro de OUTRA pessoa na mesma tarefa → RLS 42501',
  $$insert into public.work_deliverables (id, task_id, work_log_id, title) values (gen_random_uuid(), tests.uvar('ta'), tests.uvar('ls'), 'Tentativa')$$);
select tests.rls_denied('entrega ligada a registro sem tarefa → RLS 42501',
  $$insert into public.work_deliverables (id, task_id, work_log_id, title) values (gen_random_uuid(), tests.uvar('ta'), tests.uvar('l2'), 'Tentativa')$$);
select tests.rls_denied('entrega em tarefa de outra pessoa → RLS 42501',
  $$insert into public.work_deliverables (id, task_id, title) values (gen_random_uuid(), tests.uvar('t2'), 'Tentativa')$$);
select tests.rls_denied('entrega em tarefa INEXISTENTE → RLS 42501 (mesmo erro da alheia, não FK 23503)',
  $$insert into public.work_deliverables (id, task_id, title) values (gen_random_uuid(), gen_random_uuid(), 'Tentativa')$$);
select tests.rls_denied('entrega ligada a registro INEXISTENTE → RLS 42501',
  $$insert into public.work_deliverables (id, task_id, work_log_id, title) values (gen_random_uuid(), tests.uvar('ta'), gen_random_uuid(), 'Tentativa')$$);
select tests.rls_denied('entrega ligada a registro de outra tarefa que NÃO vejo → RLS 42501',
  $$insert into public.work_deliverables (id, task_id, work_log_id, title) values (gen_random_uuid(), tests.uvar('t2'), tests.uvar('l3'), 'Tentativa')$$);
select tests.denied('enviar created_by → sem grant', $$insert into public.work_deliverables (id, task_id, title, created_by) values (gen_random_uuid(), tests.uvar('ta'), 'x', tests.uid('sa'))$$);
select tests.throws('link ftp → 23514', $$insert into public.work_deliverables (id, task_id, title, url) values (gen_random_uuid(), tests.uvar('ta'), 'x', 'ftp://exemplo.com/a')$$, null, '23514');
select tests.throws('link javascript: → 23514', $$insert into public.work_deliverables (id, task_id, title, url) values (gen_random_uuid(), tests.uvar('ta'), 'x', 'javascript:alert(1)')$$, null, '23514');
select tests.throws('link com espaço → 23514', $$insert into public.work_deliverables (id, task_id, title, url) values (gen_random_uuid(), tests.uvar('ta'), 'x', 'https://exemplo.com/a b')$$, null, '23514');
select tests.throws('link sem host → 23514', $$insert into public.work_deliverables (id, task_id, title, url) values (gen_random_uuid(), tests.uvar('ta'), 'x', 'https://')$$, null, '23514');
select tests.throws('link com 2001 caracteres → 23514',
  $$insert into public.work_deliverables (id, task_id, title, url) values (gen_random_uuid(), tests.uvar('ta'), 'x', 'https://exemplo.com/' || repeat('a', 1981))$$, null, '23514');
select tests.throws('título em branco → 23514', $$insert into public.work_deliverables (id, task_id, title) values (gen_random_uuid(), tests.uvar('ta'), '  ')$$, null, '23514');
select tests.throws('observações com 2001 caracteres → 23514', $$insert into public.work_deliverables (id, task_id, title, notes) values (gen_random_uuid(), tests.uvar('ta'), 'x', repeat('n', 2001))$$, null, '23514');
select tests.affects('link HTTPS maiúsculo é aceito (regex ~*)', $$insert into public.work_deliverables (id, task_id, title, url) values (gen_random_uuid(), tests.uvar('ta'), 'Link', 'HTTPS://EXEMPLO.COM/X')$$, 1);
select tests.affects('sem link é aceito', $$insert into public.work_deliverables (id, task_id, title) values (gen_random_uuid(), tests.uvar('ta'), 'Entrega offline')$$, 1);
select tests.denied('sem UPDATE em entregas', $$update public.work_deliverables set title = 'editado' where id = tests.uvar('d1')$$);
select tests.denied('sem DELETE em entregas', $$delete from public.work_deliverables where id = tests.uvar('d1')$$);

select tests.login('sa');
select tests.affects('super_admin entrega em qualquer tarefa (t2 da emp2)', $$insert into public.work_deliverables (id, task_id, title) values (tests.uvar('d3'), tests.uvar('t2'), 'Checklist')$$, 1);
select tests.affects('super_admin entrega em ta', $$insert into public.work_deliverables (id, task_id, work_log_id, title) values (tests.uvar('d4'), tests.uvar('ta'), tests.uvar('ls'), 'Revisão')$$, 1);
select tests.login('cli');
select tests.rls_denied('client não entrega', $$insert into public.work_deliverables (id, task_id, title) values (gen_random_uuid(), tests.uvar('ta'), 'x')$$);
select tests.login_anon();
select tests.denied('anon: SELECT work_deliverables', $$select 1 from public.work_deliverables$$);

select tests.note('visibilidade das entregas (de quem quer que seja, nas tarefas que criei ou me foram atribuídas)');
select tests.login('emp');
select tests.rows_eq('employee: as 4 dele + a do super_admin em ta', $$select 1 from public.work_deliverables$$, 5);
select tests.rows_eq('… não vê a de t2', $$select 1 from public.work_deliverables where id = tests.uvar('d3')$$, 0);
select tests.login('emp2');
select tests.rows_eq('emp2: só a de t2 (criada pelo super_admin)', $$select 1 from public.work_deliverables$$, 1);
select tests.login('mgr');
select tests.rows_eq('manager: 0', $$select 1 from public.work_deliverables$$, 0);
select tests.login('cli');
select tests.rows_eq('client: 0', $$select 1 from public.work_deliverables$$, 0);
select tests.login('sa');
select tests.rows_eq('super_admin: todas (6)', $$select 1 from public.work_deliverables$$, 6);

select tests.note('eventos deliverable_added');
select tests.login('emp');
select tests.query_true('deliverable_added: changes = {"deliverable_id", "title"} exatos, autor employee',
  $$select count(*) = 1 and bool_and(actor_id = auth.uid() and changes = jsonb_build_object('deliverable_id', tests.uvar('d1'), 'title', 'Arte final'))
     from public.work_task_events where action = 'deliverable_added' and changes->>'deliverable_id' = tests.var('d1')$$);
select tests.query_true('evento do super_admin visível ao responsável',
  $$select count(*) = 1 from public.work_task_events where action = 'deliverable_added' and changes->>'deliverable_id' = tests.var('d4')$$);
select tests.login('emp2');
select tests.rows_eq('emp2 não vê eventos de ta', $$select 1 from public.work_task_events where task_id = tests.uvar('ta')$$, 0);

select tests.note('FK restrict: tarefa com registro não é apagada');
select tests.logout();
select tests.throws('postgres: apagar tarefa com registros → 23503', $$delete from public.work_tasks where id = tests.uvar('te')$$, null, '23503');

select tests.done();
rollback;
