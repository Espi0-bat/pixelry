-- new_roles/02 — Tarefas com os papéis novos (§2, §3.5). Aceitos pelo schema
-- integrado; roda sempre. partner/sales_trial/employee_dev: como manager/employee
-- (criam só para si). sdr: não cria; vê só as tarefas ATRIBUÍDAS a ele; muda
-- só o status, nunca para canceled; registra o que fez e entrega nelas.
begin;

select tests.create_user('sa', 'super_admin');
select tests.create_user('partner', 'partner');
select tests.create_user('trial', 'sales_trial');
select tests.create_user('dev', 'employee_dev');
select tests.create_user('sdr', 'sdr');
select tests.create_user('emp', 'employee');
select tests.new_id('tp');
select tests.new_id('tt');
select tests.new_id('td');
select tests.new_id('ts');
select tests.new_id('tsc');
select tests.new_id('tso');
select tests.new_id('tpa');

select tests.note('partner, sales_trial e employee_dev criam só para si');
select tests.login('partner');
select tests.affects('partner: para si', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('tp'), 'Tarefa do sócio', auth.uid())$$, 1);
select tests.rls_denied('partner: para outra pessoa → RLS', $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', tests.uid('emp'))$$);
select tests.rls_denied('partner: sem responsável → RLS', $$insert into public.work_tasks (id, title) values (gen_random_uuid(), 'x')$$);
select tests.login('trial');
select tests.affects('sales_trial: para si', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('tt'), 'Prospecção', auth.uid())$$, 1);
select tests.rls_denied('sales_trial: para outra pessoa → RLS', $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', tests.uid('emp'))$$);
select tests.login('dev');
select tests.affects('employee_dev: para si', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('td'), 'Corrigir bug', auth.uid())$$, 1);
select tests.rls_denied('employee_dev: para outra pessoa → RLS', $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', tests.uid('sdr'))$$);
select tests.affects('employee_dev cancela a própria (criador)', $$update public.work_tasks set status = 'canceled' where id = tests.uvar('td')$$, 1);

select tests.note('sdr não cria tarefa');
select tests.login('sdr');
select tests.rls_denied('sdr: para si → RLS', $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'x', auth.uid())$$);
select tests.rls_denied('sdr: sem responsável → RLS', $$insert into public.work_tasks (id, title) values (gen_random_uuid(), 'x')$$);

select tests.note('super_admin atribui aos papéis novos');
select tests.login('sa');
select tests.affects('super_admin → sdr', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('ts'), 'Ligar para 20 leads', tests.uid('sdr'))$$, 1);
select tests.affects('super_admin → partner (interno)', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('tpa'), 'Reunião', tests.uid('partner'))$$, 1);
select tests.logout();
-- Estados que a API não produz, criados pelo dono do banco para testar a regra
-- "sdr → só status" e "sdr vê só as atribuídas" (ex.: alguém que criou tarefas
-- e depois virou sdr).
select tests.step('tarefa criada pelo sdr e atribuída a ele (postgres)',
  $$insert into public.work_tasks (id, title, assignee_id, created_by) values (tests.uvar('tsc'), 'Criada antes de virar sdr', tests.uid('sdr'), tests.uid('sdr'))$$);
select tests.step('tarefa criada pelo sdr e atribuída a outra pessoa (postgres)',
  $$insert into public.work_tasks (id, title, assignee_id, created_by) values (tests.uvar('tso'), 'Criada pelo sdr para emp', tests.uid('emp'), tests.uid('sdr'))$$);
select tests.login('emp');
select tests.step('emp (responsável) entrega na tso',
  $$insert into public.work_deliverables (id, task_id, title) values (gen_random_uuid(), tests.uvar('tso'), 'Entrega da emp')$$);

select tests.note('sdr: vê só as atribuídas; só status; nunca canceled');
select tests.login('sdr');
select tests.rows_eq('sdr vê as 2 atribuídas a ele', $$select 1 from public.work_tasks where assignee_id = auth.uid()$$, 2);
select tests.rows_eq('sdr NÃO vê a que criou para outra pessoa (contrato §2: "atribuídas a mim")',
  $$select 1 from public.work_tasks where id = tests.uvar('tso')$$, 0);
select tests.affects('sdr muda o status', $$update public.work_tasks set status = 'in_progress' where id = tests.uvar('ts')$$, 1);
select tests.throws('sdr cancelando → task_field_not_allowed', $$update public.work_tasks set status = 'canceled' where id = tests.uvar('ts')$$, 'task_field_not_allowed', '42501');
select tests.throws('sdr mudando título → task_field_not_allowed', $$update public.work_tasks set title = 'Outro' where id = tests.uvar('ts')$$, 'task_field_not_allowed', '42501');
select tests.throws('sdr criador: título também não → task_field_not_allowed', $$update public.work_tasks set title = 'Outro' where id = tests.uvar('tsc')$$, 'task_field_not_allowed', '42501');
select tests.throws('sdr criador: prioridade → task_field_not_allowed', $$update public.work_tasks set priority = 'urgent' where id = tests.uvar('tsc')$$, 'task_field_not_allowed', '42501');
select tests.throws('sdr criador: cancelar → task_field_not_allowed', $$update public.work_tasks set status = 'canceled' where id = tests.uvar('tsc')$$, 'task_field_not_allowed', '42501');
select tests.affects('sdr criador: status (não canceled) ok', $$update public.work_tasks set status = 'done' where id = tests.uvar('tsc')$$, 1);
select tests.affects('sdr registra o que fez na tarefa atribuída', $$insert into public.work_logs (id, task_id, summary, minutes_spent) values (gen_random_uuid(), tests.uvar('ts'), 'Liguei para 12 leads', 90)$$, 1);
select tests.affects('sdr entrega na tarefa atribuída', $$insert into public.work_deliverables (id, task_id, title, url) values (gen_random_uuid(), tests.uvar('ts'), 'Planilha', 'https://exemplo.com/planilha')$$, 1);
select tests.rls_denied('sdr não registra em tarefa que não é dele', $$insert into public.work_logs (id, task_id, summary) values (gen_random_uuid(), tests.uvar('tp'), 'Tentativa')$$);
select tests.rows_eq('sdr vê os próprios registros', $$select 1 from public.work_logs$$, 1);
select tests.rows_eq('ponto_people do sdr: ele e o super_admin (criador de ts)',
  $$select 1 from public.ponto_people() where id in (tests.uid('sdr'), tests.uid('sa'))$$, 2);
-- "atribuídas a mim" (§2) vale para tudo que pendura na tarefa: histórico,
-- registros e entregas de uma tarefa que o sdr criou para outra pessoa (estado
-- que só existe se o perfil virou sdr depois) também ficam fora do alcance.
select tests.rows_eq('sdr vê o histórico da tarefa atribuída (ts: created, status, log_added, deliverable_added)',
  $$select 1 from public.work_task_events where task_id = tests.uvar('ts')$$, 4);
select tests.rows_eq('sdr NÃO vê o histórico da tso (criada por ele para outra pessoa)',
  $$select 1 from public.work_task_events where task_id = tests.uvar('tso')$$, 0);
select tests.rows_eq('sdr NÃO vê as entregas da tso',
  $$select 1 from public.work_deliverables where task_id = tests.uvar('tso')$$, 0);
select tests.rls_denied('sdr não registra na tso → RLS 42501',
  $$insert into public.work_logs (id, task_id, summary) values (gen_random_uuid(), tests.uvar('tso'), 'Tentativa')$$);
select tests.rls_denied('sdr não entrega na tso → RLS 42501',
  $$insert into public.work_deliverables (id, task_id, title) values (gen_random_uuid(), tests.uvar('tso'), 'Tentativa')$$);
select tests.affects('sdr: UPDATE na tso afeta 0 linhas', $$update public.work_tasks set status = 'done' where id = tests.uvar('tso')$$, 0);
select tests.rows_eq('ponto_people do sdr não inclui a responsável da tso',
  $$select 1 from public.ponto_people() where id = tests.uid('emp')$$, 0);

select tests.note('visibilidade dos outros papéis novos');
select tests.login('partner');
select tests.rows_eq('partner: a própria + a atribuída pelo super_admin', $$select 1 from public.work_tasks$$, 2);
select tests.rows_eq('partner não vê a do sdr', $$select 1 from public.work_tasks where id = tests.uvar('ts')$$, 0);
select tests.affects('partner responsável (não criador): muda o status', $$update public.work_tasks set status = 'in_progress' where id = tests.uvar('tpa')$$, 1);
select tests.throws('partner responsável (não criador): título → task_field_not_allowed',
  $$update public.work_tasks set title = 'Outra reunião' where id = tests.uvar('tpa')$$, 'task_field_not_allowed', '42501');
select tests.throws('partner responsável (não criador): cancelar → task_field_not_allowed',
  $$update public.work_tasks set status = 'canceled' where id = tests.uvar('tpa')$$, 'task_field_not_allowed', '42501');
select tests.throws('partner não reatribui nem a própria tarefa → task_field_not_allowed',
  $$update public.work_tasks set assignee_id = tests.uid('emp') where id = tests.uvar('tp')$$, 'task_field_not_allowed', '42501');
select tests.affects('partner criador: título e cancelamento da própria', $$update public.work_tasks set title = 'Tarefa do sócio (v2)', status = 'canceled' where id = tests.uvar('tp')$$, 1);
select tests.login('trial');
select tests.rows_eq('sales_trial: só a própria', $$select 1 from public.work_tasks$$, 1);

select tests.done();
rollback;
