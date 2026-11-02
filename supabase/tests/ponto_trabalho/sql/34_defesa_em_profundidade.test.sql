-- 34 — Segunda linha de defesa (§3.2, §3.5). Os grants de coluna do contrato
-- já barram o usuário final antes de qualquer trigger ("permission denied",
-- arquivos 20/30/31/32). Aqui eles são ABERTOS de propósito, só dentro da
-- transação deste arquivo (o rollback desfaz), para provar que as outras
-- camadas seguram as mesmas regras sozinhas se um grant futuro escapar:
--   * work_tasks_before_write: id/created_by/created_at imutáveis para
--     usuário final, inclusive super_admin (§2: "todos exceto id/created_by/
--     created_at"); no INSERT força created_by = auth.uid() e as datas;
--     completed_at/updated_at sempre do servidor;
--   * work_logs_before_insert / work_deliverables_before_insert: autor e data
--     do servidor;
--   * RLS sem policy de escrita: nada de INSERT/UPDATE/DELETE direto no ponto
--     e nas auditorias; sem DELETE em tarefas; sem UPDATE/DELETE em registros
--     e entregas.
begin;

select tests.create_user('sa', 'super_admin');
select tests.create_user('mgr', 'manager');
select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.new_id('ta');
select tests.new_id('tm');
select tests.new_id('tf1');
select tests.new_id('tf2');
select tests.new_id('tf3');
select tests.new_id('l1');
select tests.new_id('lf');
select tests.new_id('df');

select tests.login('sa');
select tests.step('ta: super_admin → emp',
  $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('ta'), 'Arte A', tests.uid('emp'))$$);
select tests.login('mgr');
select tests.step('tm: manager para si',
  $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('tm'), 'Tarefa do manager', auth.uid())$$);
select tests.login('emp');
select tests.step('l1: registro do emp em ta', $$insert into public.work_logs (id, task_id, summary) values (tests.uvar('l1'), tests.uvar('ta'), 'Primeiro rascunho')$$);
select tests.capture('s_open', $$select public.time_clock_in()::jsonb->>'id'$$);
select tests.step('intervalo aberto na jornada do emp', $$select public.time_start_break()$$);
select tests.login('emp2');
select tests.capture('s_other', $$select public.time_clock_in()::jsonb->>'id'$$);

-- Grants que o contrato NÃO dá. Só neste banco descartável e só nesta
-- transação (o runner faz rollback no fim do arquivo).
select tests.logout();
grant update (id, created_by, created_at, updated_at, completed_at) on public.work_tasks to authenticated;
grant insert (created_by, created_at, updated_at, completed_at) on public.work_tasks to authenticated;
grant delete on public.work_tasks to authenticated;
grant insert (user_id, created_at) on public.work_logs to authenticated;
grant insert (created_by, created_at) on public.work_deliverables to authenticated;
grant update, delete on public.work_logs, public.work_deliverables to authenticated;
grant insert, update, delete on public.work_task_events to authenticated;
grant insert, update, delete on public.time_shifts, public.time_breaks, public.time_audit_events to authenticated;
select tests.query_true('preparação: authenticated tem os grants extras nesta transação',
  $$select has_column_privilege('authenticated', 'public.work_tasks', 'created_by', 'UPDATE')
       and has_table_privilege('authenticated', 'public.time_shifts', 'INSERT')$$);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('work_tasks UPDATE: id/created_by/created_at imutáveis pelo trigger');
select tests.login('emp');
select tests.throws_detail('responsável: created_by → task_field_not_allowed (trigger)',
  $$update public.work_tasks set created_by = auth.uid() where id = tests.uvar('ta')$$,
  'task_field_not_allowed', '42501', 'Você não pode alterar este campo desta tarefa.');
select tests.throws_detail('responsável: created_at → task_field_not_allowed',
  $$update public.work_tasks set created_at = now() - interval '1 day' where id = tests.uvar('ta')$$,
  'task_field_not_allowed', '42501', 'Você não pode alterar este campo desta tarefa.');
select tests.throws_detail('responsável: id → task_field_not_allowed',
  $$update public.work_tasks set id = gen_random_uuid() where id = tests.uvar('ta')$$,
  'task_field_not_allowed', '42501', 'Você não pode alterar este campo desta tarefa.');
select tests.login('mgr');
select tests.throws('criador: created_by → task_field_not_allowed',
  $$update public.work_tasks set created_by = tests.uid('emp') where id = tests.uvar('tm')$$, 'task_field_not_allowed', '42501');
select tests.throws('criador: created_at → task_field_not_allowed',
  $$update public.work_tasks set created_at = now() - interval '1 day' where id = tests.uvar('tm')$$, 'task_field_not_allowed', '42501');
select tests.throws('criador: id → task_field_not_allowed',
  $$update public.work_tasks set id = gen_random_uuid() where id = tests.uvar('tm')$$, 'task_field_not_allowed', '42501');
select tests.login('sa');
select tests.throws('super_admin: created_by → task_field_not_allowed (§2: todos exceto id/created_by/created_at)',
  $$update public.work_tasks set created_by = tests.uid('mgr') where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.throws('super_admin: created_at → task_field_not_allowed',
  $$update public.work_tasks set created_at = now() - interval '1 day' where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.throws('super_admin: id → task_field_not_allowed',
  $$update public.work_tasks set id = gen_random_uuid() where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.admin_query_is('verdade: ta e tm com id, criador e data de criação originais',
  $$select (count(*) = 2 and bool_and(created_at = now())
            and bool_and(case when id = tests.uvar('ta') then created_by = tests.uid('sa') else created_by = tests.uid('mgr') end))::text
     from public.work_tasks where id in (tests.uvar('ta'), tests.uvar('tm'))$$, 'true');

select tests.note('work_tasks UPDATE: updated_at e completed_at sempre do servidor');
select tests.login('emp');
select tests.affects('responsável muda o status mandando updated_at antigo',
  $$update public.work_tasks set status = 'in_progress', updated_at = '2000-01-01' where id = tests.uvar('ta')$$, 1);
select tests.admin_query_is('… updated_at = now() (valor enviado ignorado)',
  $$select (updated_at = now())::text from public.work_tasks where id = tests.uvar('ta')$$, 'true');
select tests.affects('responsável manda completed_at sem concluir',
  $$update public.work_tasks set completed_at = '2000-01-01' where id = tests.uvar('ta')$$, 1);
select tests.admin_query_is('… completed_at continua nulo (tarefa não concluída)',
  $$select (completed_at is null)::text from public.work_tasks where id = tests.uvar('ta')$$, 'true');
select tests.affects('responsável conclui mandando completed_at antigo',
  $$update public.work_tasks set status = 'done', completed_at = '2000-01-01' where id = tests.uvar('ta')$$, 1);
select tests.admin_query_is('… completed_at = now() ao entrar em done',
  $$select (completed_at = now())::text from public.work_tasks where id = tests.uvar('ta')$$, 'true');
select tests.affects('tarefa concluída: responsável tenta reescrever completed_at',
  $$update public.work_tasks set completed_at = '2000-01-01' where id = tests.uvar('ta')$$, 1);
select tests.admin_query_is('… completed_at mantém a data em que foi concluída (§3.5 "Sempre")',
  $$select (completed_at = now())::text from public.work_tasks where id = tests.uvar('ta')$$, 'true');

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('work_tasks INSERT: autor e datas do servidor');
select tests.login('emp');
select tests.affects('employee insere dizendo que a tarefa foi criada pelo super_admin, com datas antigas',
  $$insert into public.work_tasks (id, title, assignee_id, created_by, created_at, updated_at, completed_at)
    values (tests.uvar('tf1'), 'Forjada', auth.uid(), tests.uid('sa'), '2000-01-01', '2000-01-01', '2000-01-01')$$, 1);
select tests.admin_query_is('… created_by = auth.uid(); created_at = updated_at = now(); completed_at nulo (todo)',
  $$select (created_by = tests.uid('emp') and created_at = now() and updated_at = now() and completed_at is null)::text
     from public.work_tasks where id = tests.uvar('tf1')$$, 'true');
select tests.admin_query_is('… evento created com autor = quem chamou',
  $$select (actor_id = tests.uid('emp'))::text from public.work_task_events where task_id = tests.uvar('tf1') and action = 'created'$$, 'true');
select tests.affects('employee insere já concluída com completed_at antigo',
  $$insert into public.work_tasks (id, title, assignee_id, status, completed_at)
    values (tests.uvar('tf2'), 'Já feita', auth.uid(), 'done', '2000-01-01')$$, 1);
select tests.admin_query_is('… completed_at = now()',
  $$select (completed_at = now())::text from public.work_tasks where id = tests.uvar('tf2')$$, 'true');
select tests.login('mgr');
select tests.affects('manager insere para si dizendo que quem criou foi o employee',
  $$insert into public.work_tasks (id, title, assignee_id, created_by) values (tests.uvar('tf3'), 'Atribuição disfarçada', auth.uid(), tests.uid('emp'))$$, 1);
select tests.admin_query_is('… created_by forçado = manager (o employee não ganha a tarefa como criador)',
  $$select (created_by = tests.uid('mgr'))::text from public.work_tasks where id = tests.uvar('tf3')$$, 'true');
select tests.login('emp');
select tests.rows_eq('… e o employee não a vê', $$select 1 from public.work_tasks where id = tests.uvar('tf3')$$, 0);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('work_logs / work_deliverables INSERT: autor e data do servidor');
select tests.affects('employee insere registro com user_id de outra pessoa e created_at antigo',
  $$insert into public.work_logs (id, summary, user_id, created_at) values (tests.uvar('lf'), 'Forjado', tests.uid('emp2'), '2000-01-01')$$, 1);
select tests.admin_query_is('… user_id = auth.uid() e created_at = now()',
  $$select (user_id = tests.uid('emp') and created_at = now())::text from public.work_logs where id = tests.uvar('lf')$$, 'true');
select tests.login('emp2');
select tests.rows_eq('… a outra pessoa não recebe o registro', $$select 1 from public.work_logs where id = tests.uvar('lf')$$, 0);
select tests.login('emp');
select tests.affects('employee insere entrega dizendo que foi do super_admin, com data antiga',
  $$insert into public.work_deliverables (id, task_id, title, created_by, created_at)
    values (tests.uvar('df'), tests.uvar('ta'), 'Entrega forjada', tests.uid('sa'), '2000-01-01')$$, 1);
select tests.admin_query_is('… created_by = auth.uid() e created_at = now()',
  $$select (created_by = tests.uid('emp') and created_at = now())::text from public.work_deliverables where id = tests.uvar('df')$$, 'true');

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('trabalho: sem policy de DELETE/UPDATE onde o contrato diz "sem"');
select tests.affects('employee: DELETE da própria tarefa → 0 linhas (sem policy)', $$delete from public.work_tasks where id = tests.uvar('tf1')$$, 0);
select tests.affects('employee: UPDATE do próprio registro → 0 linhas', $$update public.work_logs set summary = 'Reescrito' where id = tests.uvar('l1')$$, 0);
select tests.affects('employee: DELETE do próprio registro → 0 linhas', $$delete from public.work_logs where id = tests.uvar('l1')$$, 0);
select tests.affects('employee: UPDATE da própria entrega → 0 linhas', $$update public.work_deliverables set title = 'Outra' where id = tests.uvar('df')$$, 0);
select tests.affects('employee: DELETE da própria entrega → 0 linhas', $$delete from public.work_deliverables where id = tests.uvar('df')$$, 0);
select tests.rls_denied('employee: INSERT no histórico → RLS',
  $$insert into public.work_task_events (task_id, actor_id, action) values (tests.uvar('ta'), auth.uid(), 'updated')$$);
select tests.affects('employee: UPDATE no histórico → 0 linhas', $$update public.work_task_events set changes = '{}' where task_id = tests.uvar('ta')$$, 0);
select tests.affects('employee: DELETE no histórico → 0 linhas', $$delete from public.work_task_events where task_id = tests.uvar('ta')$$, 0);
select tests.login('sa');
select tests.affects('super_admin: DELETE de tarefa → 0 linhas', $$delete from public.work_tasks where id = tests.uvar('ta')$$, 0);
select tests.affects('super_admin: DELETE de registro alheio → 0 linhas', $$delete from public.work_logs where id = tests.uvar('l1')$$, 0);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('ponto: sem policy de escrita — com grant, a RLS ainda barra tudo');
select tests.login('emp');
select tests.rls_denied('employee: INSERT da própria jornada → RLS',
  $$insert into public.time_shifts (user_id, started_at, ended_at) values (auth.uid(), now() - interval '3 days', now() - interval '3 days' + interval '1 hour')$$);
select tests.affects('employee: UPDATE da própria jornada (nota) → 0 linhas',
  $$update public.time_shifts set note = 'saí mais cedo' where id = tests.uvar('s_open')$$, 0);
select tests.affects('employee: DELETE da própria jornada → 0 linhas', $$delete from public.time_shifts where id = tests.uvar('s_open')$$, 0);
select tests.affects('employee: UPDATE do próprio intervalo (fechar) → 0 linhas',
  $$update public.time_breaks set ended_at = clock_timestamp() where shift_id = tests.uvar('s_open')$$, 0);
select tests.affects('employee: DELETE do próprio intervalo → 0 linhas', $$delete from public.time_breaks where shift_id = tests.uvar('s_open')$$, 0);
select tests.rls_denied('employee: INSERT de intervalo na própria jornada → RLS',
  $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at)
    select s.id, s.user_id, s.started_at, s.started_at + interval '1 microsecond' from public.time_shifts s where s.id = tests.uvar('s_open')$$);
select tests.rls_denied('employee: INSERT na auditoria → RLS',
  $$insert into public.time_audit_events (shift_id, subject_user_id, actor_id, action) values (tests.uvar('s_open'), auth.uid(), auth.uid(), 'clock_out')$$);
select tests.affects('employee: UPDATE na própria auditoria → 0 linhas',
  $$update public.time_audit_events set reason = 'apagando rastro' where subject_user_id = auth.uid()$$, 0);
select tests.affects('employee: DELETE na própria auditoria → 0 linhas',
  $$delete from public.time_audit_events where subject_user_id = auth.uid()$$, 0);
select tests.login('sa');
select tests.rls_denied('super_admin: INSERT de jornada para outra pessoa → RLS',
  $$insert into public.time_shifts (user_id, started_at, ended_at) values (tests.uid('emp2'), now() - interval '3 days', now() - interval '3 days' + interval '1 hour')$$);
select tests.affects('super_admin: UPDATE de jornada alheia → 0 linhas (revisão só pela RPC)',
  $$update public.time_shifts set note = 'ajuste' where id = tests.uvar('s_other')$$, 0);
select tests.affects('super_admin: DELETE de auditoria → 0 linhas', $$delete from public.time_audit_events$$, 0);

select tests.admin_query_is('verdade: jornadas, intervalos e auditorias como as RPCs deixaram',
  $$select (select count(*) from public.time_shifts where user_id in (tests.uid('emp'), tests.uid('emp2')) and ended_at is null and note is null)
        || '|' || (select count(*) from public.time_breaks where shift_id = tests.uvar('s_open') and ended_at is null)
        || '|' || (select count(*) from public.time_audit_events where subject_user_id in (tests.uid('emp'), tests.uid('emp2')))$$,
  '2|1|3');
select tests.admin_query_is('verdade: tarefas, registros e entregas intactos',
  $$select (select count(*) from public.work_tasks)
        || '|' || (select string_agg(summary, ',' order by summary) from public.work_logs)
        || '|' || (select string_agg(title, ',' order by title) from public.work_deliverables)$$,
  '5|Forjado,Primeiro rascunho|Entrega forjada');

select tests.done();
rollback;
