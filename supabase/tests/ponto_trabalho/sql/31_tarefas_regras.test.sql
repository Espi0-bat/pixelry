-- 31 — Regras de coluna do trigger work_tasks_before_write e eventos
-- "updated" (§2, §3.5): responsável que não criou só muda status (nunca para
-- canceled) e não mexe em created_by/assignee_id/created_at; criador muda
-- título/descrição/prioridade/prazo/status; só super_admin reatribui;
-- completed_at/updated_at automáticos; histórico com from/to exatos.
begin;

select tests.create_user('sa', 'super_admin');
select tests.create_user('mgr', 'manager');
select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.create_user('cli', 'client');
select tests.new_id('ta');
select tests.new_id('tm');

select tests.login('sa');
select tests.step('ta: super_admin → employee',
  $$insert into public.work_tasks (id, title, description, assignee_id, priority, due_date)
    values (tests.uvar('ta'), 'Arte A', 'Descrição A', tests.uid('emp'), 'medium', '2026-11-10')$$);
select tests.login('mgr');
select tests.step('tm: manager para si', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('tm'), 'Tarefa do manager', auth.uid())$$);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('responsável que não criou (employee em ta): só status, sem canceled');
select tests.login('emp');
select tests.affects('status → in_progress', $$update public.work_tasks set status = 'in_progress' where id = tests.uvar('ta')$$, 1);
select tests.query_true('evento updated com {"status": {"from": "todo", "to": "in_progress"}} exato, autor employee',
  $$select count(*) = 1 and bool_and(actor_id = auth.uid() and changes = '{"status": {"from": "todo", "to": "in_progress"}}'::jsonb)
     from public.work_task_events where task_id = tests.uvar('ta') and action = 'updated'$$);
select tests.affects('status → done', $$update public.work_tasks set status = 'done' where id = tests.uvar('ta')$$, 1);
select tests.query_true('entrar em done preenche completed_at = now()', $$select completed_at = now() from public.work_tasks where id = tests.uvar('ta')$$);
select tests.affects('status → in_review (sai de done)', $$update public.work_tasks set status = 'in_review' where id = tests.uvar('ta')$$, 1);
select tests.query_true('sair de done zera completed_at', $$select completed_at is null from public.work_tasks where id = tests.uvar('ta')$$);
select tests.affects('status → blocked', $$update public.work_tasks set status = 'blocked' where id = tests.uvar('ta')$$, 1);
select tests.throws('status → canceled → task_field_not_allowed 42501',
  $$update public.work_tasks set status = 'canceled' where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.throws('título → task_field_not_allowed', $$update public.work_tasks set title = 'Outro título' where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.throws('descrição → task_field_not_allowed', $$update public.work_tasks set description = 'Outra' where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.throws('prioridade → task_field_not_allowed', $$update public.work_tasks set priority = 'urgent' where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.throws('prazo → task_field_not_allowed', $$update public.work_tasks set due_date = '2026-12-01' where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.throws('limpar o prazo → task_field_not_allowed', $$update public.work_tasks set due_date = null where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.throws('reatribuir a outra pessoa → task_field_not_allowed', $$update public.work_tasks set assignee_id = tests.uid('emp2') where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.throws('tirar o responsável → task_field_not_allowed', $$update public.work_tasks set assignee_id = null where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
-- work_tasks_before_write dispara antes de work_tasks_validate_assignee (ordem
-- alfabética dos triggers BEFORE): quem não pode reatribuir ouve
-- task_field_not_allowed, e não invalid_assignee — senão saberia se um uuid
-- qualquer é ou não perfil interno.
select tests.throws('reatribuir a um client → task_field_not_allowed (antes de invalid_assignee: sem oráculo)',
  $$update public.work_tasks set assignee_id = tests.uid('cli') where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.throws('reatribuir a uuid inexistente → task_field_not_allowed (idem)',
  $$update public.work_tasks set assignee_id = gen_random_uuid() where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.throws('status + título juntos → task_field_not_allowed (nada muda)',
  $$update public.work_tasks set status = 'todo', title = 'Outro' where id = tests.uvar('ta')$$, 'task_field_not_allowed', '42501');
select tests.denied('created_by → sem grant de coluna', $$update public.work_tasks set created_by = auth.uid() where id = tests.uvar('ta')$$);
select tests.denied('created_at → sem grant', $$update public.work_tasks set created_at = now() - interval '1 day' where id = tests.uvar('ta')$$);
select tests.denied('id → sem grant', $$update public.work_tasks set id = gen_random_uuid() where id = tests.uvar('ta')$$);
select tests.denied('completed_at → sem grant', $$update public.work_tasks set completed_at = now() where id = tests.uvar('ta')$$);
select tests.denied('updated_at → sem grant', $$update public.work_tasks set updated_at = now() where id = tests.uvar('ta')$$);
select tests.admin_query_is('ta intacta: título, descrição, prioridade, prazo, responsável, criador',
  $$select title || '|' || description || '|' || priority || '|' || due_date || '|' || (assignee_id = tests.uid('emp')) || '|' || (created_by = tests.uid('sa')) || '|' || status
     from public.work_tasks where id = tests.uvar('ta')$$, 'Arte A|Descrição A|medium|2026-11-10|true|true|blocked');
select tests.admin_rows('verdade: 4 eventos updated (in_progress, done, in_review, blocked)',
  $$select 1 from public.work_task_events where task_id = tests.uvar('ta') and action = 'updated'$$, 4);
select tests.affects('UPDATE sem mudança real (status = status)', $$update public.work_tasks set status = status where id = tests.uvar('ta')$$, 1);
select tests.admin_rows('… não gera evento', $$select 1 from public.work_task_events where task_id = tests.uvar('ta') and action = 'updated'$$, 4);

select tests.note('updated_at automático');
select tests.logout();
select tests.lives('envelhece updated_at (sem triggers)',
  $$select set_config('session_replication_role', 'replica', true)$$);
select tests.lives('… updated_at = 2000-01-01', $$update public.work_tasks set updated_at = '2000-01-01T00:00:00Z' where id = tests.uvar('ta')$$);
select tests.lives('… triggers de volta', $$select set_config('session_replication_role', 'origin', true)$$);
select tests.login('emp');
select tests.affects('employee muda o status', $$update public.work_tasks set status = 'in_progress' where id = tests.uvar('ta')$$, 1);
select tests.query_true('updated_at = now() depois do UPDATE', $$select updated_at = now() from public.work_tasks where id = tests.uvar('ta')$$);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('criador (manager em tm): título, descrição, prioridade, prazo, status — não reatribui');
select tests.login('mgr');
select tests.affects('título + prioridade', $$update public.work_tasks set title = 'Tarefa do manager (v2)', priority = 'high' where id = tests.uvar('tm')$$, 1);
select tests.query_true('evento com exatamente os campos alterados (from/to)',
  $$select changes = jsonb_build_object('title', jsonb_build_object('from', 'Tarefa do manager', 'to', 'Tarefa do manager (v2)'),
                                        'priority', jsonb_build_object('from', 'medium', 'to', 'high'))
     from public.work_task_events where task_id = tests.uvar('tm') and action = 'updated'$$);
select tests.affects('descrição e prazo', $$update public.work_tasks set description = 'Detalhes', due_date = '2026-11-20' where id = tests.uvar('tm')$$, 1);
select tests.query_true('evento description de null → texto e due_date de null → data',
  $$select changes = jsonb_build_object('description', jsonb_build_object('from', null, 'to', 'Detalhes'),
                                        'due_date', jsonb_build_object('from', null, 'to', '2026-11-20'))
     from public.work_task_events where task_id = tests.uvar('tm') and action = 'updated' order by seq desc limit 1$$);
select tests.throws('criador não reatribui → task_field_not_allowed',
  $$update public.work_tasks set assignee_id = tests.uid('emp') where id = tests.uvar('tm')$$, 'task_field_not_allowed', '42501');
select tests.denied('criador não muda created_by', $$update public.work_tasks set created_by = tests.uid('sa') where id = tests.uvar('tm')$$);
select tests.affects('criador cancela a própria tarefa', $$update public.work_tasks set status = 'canceled' where id = tests.uvar('tm')$$, 1);
select tests.rows_eq('cancelada continua existindo (não é apagada)', $$select 1 from public.work_tasks where id = tests.uvar('tm') and status = 'canceled'$$, 1);
select tests.affects('criador reabre', $$update public.work_tasks set status = 'todo' where id = tests.uvar('tm')$$, 1);

select tests.note('quem não vê a tarefa não altera nada');
select tests.login('emp2');
select tests.affects('employee sem relação: UPDATE afeta 0 linhas', $$update public.work_tasks set status = 'done' where id = tests.uvar('ta')$$, 0);
select tests.login('cli');
select tests.affects('client: UPDATE afeta 0 linhas', $$update public.work_tasks set status = 'done' where id = tests.uvar('ta')$$, 0);
select tests.login('mgr');
select tests.affects('manager em tarefa alheia: UPDATE afeta 0 linhas', $$update public.work_tasks set status = 'done' where id = tests.uvar('ta')$$, 0);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('super_admin: tudo, inclusive reatribuir e cancelar');
select tests.login('sa');
select tests.affects('reatribuir ta para emp2', $$update public.work_tasks set assignee_id = tests.uid('emp2') where id = tests.uvar('ta')$$, 1);
select tests.query_true('evento {"assignee_id": {from emp, to emp2}}, autor super_admin',
  $$select actor_id = tests.uid('sa') and changes = jsonb_build_object('assignee_id', jsonb_build_object('from', tests.uid('emp'), 'to', tests.uid('emp2')))
     from public.work_task_events where task_id = tests.uvar('ta') and action = 'updated' order by seq desc limit 1$$);
select tests.throws('reatribuir para client → invalid_assignee 23514',
  $$update public.work_tasks set assignee_id = tests.uid('cli') where id = tests.uvar('ta')$$, 'invalid_assignee', '23514');
select tests.affects('título, descrição, prioridade, prazo de tarefa alheia',
  $$update public.work_tasks set title = 'Arte A (final)', description = 'Nova', priority = 'urgent', due_date = '2026-11-05' where id = tests.uvar('ta')$$, 1);
select tests.denied('nem o super_admin muda created_by', $$update public.work_tasks set created_by = tests.uid('mgr') where id = tests.uvar('ta')$$);
select tests.affects('reatribuir tm (criada pelo manager) para o employee', $$update public.work_tasks set assignee_id = tests.uid('emp') where id = tests.uvar('tm')$$, 1);
select tests.login('emp');
select tests.rows_eq('o antigo responsável deixa de ver ta', $$select 1 from public.work_tasks where id = tests.uvar('ta')$$, 0);
select tests.affects('… e não altera mais (0 linhas)', $$update public.work_tasks set status = 'done' where id = tests.uvar('ta')$$, 0);
select tests.rows_eq('o novo responsável de tm vê a tarefa', $$select 1 from public.work_tasks where id = tests.uvar('tm')$$, 1);
select tests.affects('… muda o status', $$update public.work_tasks set status = 'in_progress' where id = tests.uvar('tm')$$, 1);
select tests.throws('… não muda o título (atribuída por outro)', $$update public.work_tasks set title = 'Meu título' where id = tests.uvar('tm')$$, 'task_field_not_allowed', '42501');
select tests.throws('… não cancela', $$update public.work_tasks set status = 'canceled' where id = tests.uvar('tm')$$, 'task_field_not_allowed', '42501');
select tests.login('mgr');
select tests.rows_eq('o criador continua vendo tm depois da reatribuição', $$select 1 from public.work_tasks where id = tests.uvar('tm')$$, 1);
select tests.affects('… e ainda edita o título (criada por mim)', $$update public.work_tasks set title = 'Tarefa do manager (v3)' where id = tests.uvar('tm')$$, 1);
select tests.affects('… e cancela', $$update public.work_tasks set status = 'canceled' where id = tests.uvar('tm')$$, 1);
select tests.login('sa');
select tests.affects('super_admin cancela', $$update public.work_tasks set status = 'canceled' where id = tests.uvar('ta')$$, 1);
select tests.affects('super_admin conclui (completed_at)', $$update public.work_tasks set status = 'done' where id = tests.uvar('ta')$$, 1);
select tests.query_true('completed_at preenchido', $$select completed_at = now() from public.work_tasks where id = tests.uvar('ta')$$);

select tests.note('completed_at também na criação (§3.5: "Sempre: completed_at = now() ao entrar em done")');
select tests.login('emp');
select tests.new_id('td');
select tests.affects('employee cria a própria tarefa já concluída', $$insert into public.work_tasks (id, title, assignee_id, status) values (tests.uvar('td'), 'Feito fora do app', auth.uid(), 'done')$$, 1);
select tests.query_true('… completed_at = now() (sem o app enviar a coluna)', $$select completed_at = now() from public.work_tasks where id = tests.uvar('td')$$);
select tests.affects('… reabrir (criador)', $$update public.work_tasks set status = 'todo' where id = tests.uvar('td')$$, 1);
select tests.query_true('… completed_at volta a nulo', $$select completed_at is null from public.work_tasks where id = tests.uvar('td')$$);

select tests.note('histórico imutável e escrito só por triggers');
select tests.login('emp2');
-- created + 4 status do employee + 1 status depois do envelhecimento + reatribuição
-- + edição do super_admin + canceled + done = 10 (o UPDATE sem mudança não conta).
select tests.rows_eq('o novo responsável vê o histórico inteiro de ta (10 eventos)',
  $$select 1 from public.work_task_events where task_id = tests.uvar('ta')$$, 10);
select tests.denied('authenticated: INSERT em work_task_events', $$insert into public.work_task_events (task_id, action) values (tests.uvar('ta'), 'updated')$$);
select tests.denied('authenticated: UPDATE em work_task_events', $$update public.work_task_events set changes = '{}' where task_id = tests.uvar('ta')$$);
select tests.denied('authenticated: DELETE em work_task_events', $$delete from public.work_task_events where task_id = tests.uvar('ta')$$);
select tests.logout();
select tests.throws('postgres: UPDATE no histórico → audit_immutable 42501',
  $$update public.work_task_events set changes = '{}' where task_id = tests.uvar('ta')$$, 'audit_immutable', '42501');
select tests.throws('postgres: DELETE no histórico → audit_immutable 42501',
  $$delete from public.work_task_events where task_id = tests.uvar('ta')$$, 'audit_immutable', '42501');
select tests.throws('ação fora da lista → 23514',
  $$insert into public.work_task_events (task_id, action) values (tests.uvar('ta'), 'deleted')$$, null, '23514');
select tests.admin_true('seq do histórico estritamente crescente',
  $$select bool_and(ok) from (select coalesce(seq > lag(seq) over (order by seq), true) ok from public.work_task_events where task_id = tests.uvar('ta')) q$$);

select tests.done();
rollback;
