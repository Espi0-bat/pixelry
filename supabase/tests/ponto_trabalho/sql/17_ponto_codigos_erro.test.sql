-- 17 — Tabela de códigos de erro (§3.7) de ponta a ponta: para cada código, a
-- message exata, o SQLSTATE da tabela e o detail com a frase pt-BR da tabela
-- (§3.3: raise exception '<código>' using errcode = …, detail = '<frase>').
-- Cada código é provocado pelo caminho real (RPC como authenticated; triggers
-- de integridade como postgres, como o contrato pede em §5).
-- audit_immutable: a tabela diz "(interno) Você não tem permissão para esta
-- ação."; o "(interno)" marca que o app nunca deveria vê-lo, então o detail é
-- aceito com ou sem esse prefixo.
begin;

select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.create_user('mgr', 'manager');
select tests.create_user('sa', 'super_admin');
select tests.create_user('cli', 'client');

select tests.note('sessão e permissão');
select tests.login_without_sub();
select tests.throws_detail('not_authenticated: 42501 + frase de §3.7',
  $$select public.time_clock_in()$$, 'not_authenticated', '42501', 'Sua sessão expirou. Entre novamente.');
select tests.login('cli');
select tests.throws_detail('not_allowed (client batendo ponto): 42501 + frase de §3.7',
  $$select public.time_clock_in()$$, 'not_allowed', '42501', 'Você não tem permissão para esta ação.');
select tests.login('mgr');
select tests.throws_detail('not_allowed (manager revisando): 42501 + frase de §3.7',
  $$select public.time_review_shifts('[]'::jsonb)$$, 'not_allowed', '42501', 'Você não tem permissão para esta ação.');
select tests.throws_detail('not_allowed (manager lançando jornada de outra pessoa): 42501 + frase de §3.7',
  $$select public.time_create_manual_shift(tests.uid('emp'), tests.brt('2026-10-05 08:00'), tests.brt('2026-10-05 12:00'), '[]'::jsonb, 'Esqueceu de bater o ponto')$$,
  'not_allowed', '42501', 'Você não tem permissão para esta ação.');

select tests.note('batidas');
select tests.login('emp');
select tests.throws_detail('no_open_shift: P0001 + frase de §3.7',
  $$select public.time_start_break()$$, 'no_open_shift', 'P0001', 'Não há jornada aberta. Registre a entrada primeiro.');
select tests.step('entrada', $$select public.time_clock_in()$$);
select tests.throws_detail('shift_already_open: P0001 + frase de §3.7',
  $$select public.time_clock_in()$$, 'shift_already_open', 'P0001', 'Você já tem uma jornada aberta.');
select tests.throws_detail('no_open_break: P0001 + frase de §3.7',
  $$select public.time_end_break()$$, 'no_open_break', 'P0001', 'Não há intervalo aberto.');
select tests.step('intervalo', $$select public.time_start_break()$$);
select tests.throws_detail('break_already_open: P0001 + frase de §3.7',
  $$select public.time_start_break()$$, 'break_already_open', 'P0001', 'Você já está em intervalo.');
select tests.throws_detail('break_open: P0001 + frase de §3.7',
  $$select public.time_clock_out()$$, 'break_open', 'P0001', 'Encerre o intervalo antes de registrar a saída.');
select tests.step('saída fechando o intervalo', $$select public.time_clock_out(null, true)$$);
select tests.new_id('rq');
select tests.step('entrada com request_id', $$select public.time_clock_in(tests.uvar('rq'))$$);
select tests.throws_detail('request_id_conflict: P0001 + frase de §3.7',
  $$select public.time_start_break(tests.uvar('rq'))$$, 'request_id_conflict', 'P0001',
  'Esta ação já foi enviada com outro pedido. Atualize a tela.');
select tests.step('saída', $$select public.time_clock_out()$$);

select tests.note('correção e jornada manual');
select tests.capture('a', $$select public.time_create_manual_shift(null, tests.brt('2026-10-05 08:00'), tests.brt('2026-10-05 12:00'),
  jsonb_build_array(tests.brk(tests.brt('2026-10-05 10:00'), tests.brt('2026-10-05 10:15'))), 'Esqueci de bater o ponto')::jsonb->>'id'$$);
select tests.throws_detail('invalid_reason: P0001 + frase de §3.7',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-05 08:00'), tests.brt('2026-10-05 12:00'), '[]'::jsonb, 'curta')$$,
  'invalid_reason', 'P0001', 'Escreva uma justificativa com pelo menos 10 caracteres.');
select tests.throws_detail('cannot_reopen: P0001 + frase de §3.7',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-05 08:00'), null, '[]'::jsonb, 'Reabrir a jornada encerrada')$$,
  'cannot_reopen', 'P0001', 'Uma jornada encerrada não pode ser reaberta.');
select tests.throws_detail('invalid_range: P0001 + frase de §3.7',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-05 12:00'), tests.brt('2026-10-05 08:00'), '[]'::jsonb, 'Inverti os horários')$$,
  'invalid_range', 'P0001', 'O horário de saída precisa ser depois da entrada.');
select tests.throws_detail('future_timestamp: P0001 + frase de §3.7',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-05 08:00'), now() + interval '1 day', '[]'::jsonb, 'Saída no futuro')$$,
  'future_timestamp', 'P0001', 'Não é possível registrar horários no futuro.');
select tests.throws_detail('break_outside_shift (RPC): P0001 + frase de §3.7',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-05 08:00'), tests.brt('2026-10-05 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-05 07:00'), tests.brt('2026-10-05 07:30'))), 'Intervalo antes da entrada')$$,
  'break_outside_shift', 'P0001', 'Os intervalos precisam ficar dentro da jornada.');
select tests.throws_detail('breaks_overlap: P0001 + frase de §3.7',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-05 08:00'), tests.brt('2026-10-05 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-05 09:00'), tests.brt('2026-10-05 10:00')),
                        tests.brk(tests.brt('2026-10-05 09:30'), tests.brt('2026-10-05 10:30'))), 'Intervalos sobrepostos')$$,
  'breaks_overlap', 'P0001', 'Os intervalos não podem se sobrepor.');
select tests.throws_detail('break_open_on_closed_shift (RPC): P0001 + frase de §3.7',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-05 08:00'), tests.brt('2026-10-05 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-05 09:00'), null)), 'Intervalo sem fim')$$,
  'break_open_on_closed_shift', 'P0001', 'Informe o fim de todos os intervalos de uma jornada encerrada.');
select tests.throws_detail('invalid_breaks: P0001 + frase de §3.7',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-05 08:00'), tests.brt('2026-10-05 12:00'), '{}'::jsonb, 'Lista quebrada')$$,
  'invalid_breaks', 'P0001', 'Lista de intervalos inválida.');
select tests.throws_detail('shift_overlap: P0001 + frase de §3.7',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-05 11:00'), tests.brt('2026-10-05 13:00'), '[]'::jsonb, 'Lancei a tarde também')$$,
  'shift_overlap', 'P0001', 'Esse horário se sobrepõe a outra jornada sua.');
select tests.capture('c', $$select public.time_create_manual_shift(null, tests.brt('2026-10-06 08:00'), tests.brt('2026-10-06 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')::jsonb->>'id'$$);
select tests.step('anula c', $$select public.time_void_shift(tests.uvar('c'), 'Lancei no dia errado')$$);
select tests.throws_detail('shift_voided: P0001 + frase de §3.7',
  $$select public.time_correct_shift(tests.uvar('c'), tests.brt('2026-10-06 08:00'), tests.brt('2026-10-06 11:00'), '[]'::jsonb, 'Corrigir a anulada')$$,
  'shift_voided', 'P0001', 'Esta jornada foi anulada.');
select tests.login('emp2');
select tests.throws_detail('shift_not_found: P0001 + frase de §3.7',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-05 08:00'), tests.brt('2026-10-05 12:00'), '[]'::jsonb, 'Mexer no ponto alheio')$$,
  'shift_not_found', 'P0001', 'Jornada não encontrada.');

select tests.note('revisão');
select tests.login('emp');
select tests.step('jornada aberta', $$select public.time_clock_in()$$);
select tests.capture('o', $$select public.time_my_status()->'open_shift'->>'id'$$);
select tests.login('sa');
select tests.throws_detail('shift_open: P0001 + frase de §3.7',
  $$select public.time_review_shifts((select jsonb_build_array(jsonb_build_object('id', s.id, 'updated_at', s.updated_at))
      from public.time_shifts s where s.id = tests.uvar('o')))$$,
  'shift_open', 'P0001', 'Não é possível revisar uma jornada em aberto.');
select tests.throws_detail('shift_changed: P0001 + frase de §3.7',
  $$select public.time_review_shifts(jsonb_build_array(jsonb_build_object('id', tests.uvar('a'), 'updated_at', '2000-01-01T00:00:00Z')))$$,
  'shift_changed', 'P0001', 'Esta jornada mudou depois que você abriu a tela. Atualize e revise de novo.');
select tests.query_is('revisa a', $$select public.time_review_shifts((select jsonb_build_array(jsonb_build_object('id', s.id, 'updated_at', s.updated_at))
      from public.time_shifts s where s.id = tests.uvar('a')))::text$$, '1');
select tests.login('emp');
select tests.throws_detail('shift_locked: P0001 + frase de §3.7',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-05 08:00'), tests.brt('2026-10-05 11:00'), '[]'::jsonb, 'Corrigir depois da revisão')$$,
  'shift_locked', 'P0001', 'Esta jornada já foi revisada pelo administrador. Peça a correção a ele.');

select tests.note('tarefas (triggers, como o usuário final)');
select tests.login('sa');
select tests.new_id('t');
select tests.step('super_admin cria tarefa para emp', $$insert into public.work_tasks (id, title, assignee_id) values (tests.uvar('t'), 'Relatório', tests.uid('emp'))$$);
select tests.throws_detail('invalid_assignee: 23514 + frase de §3.7',
  $$insert into public.work_tasks (id, title, assignee_id) values (gen_random_uuid(), 'Para cliente', tests.uid('cli'))$$,
  'invalid_assignee', '23514', 'Responsável inválido.');
select tests.login('emp');
select tests.throws_detail('task_field_not_allowed: 42501 + frase de §3.7',
  $$update public.work_tasks set title = 'Outro título' where id = tests.uvar('t')$$,
  'task_field_not_allowed', '42501', 'Você não pode alterar este campo desta tarefa.');

select tests.note('triggers de integridade e auditoria (como postgres)');
select tests.logout();
select tests.throws_detail('break_outside_shift (trigger): 23514 + frase de §3.7',
  $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at)
    values (tests.uvar('a'), tests.uid('emp'), tests.brt('2026-10-05 07:00'), tests.brt('2026-10-05 07:30'))$$,
  'break_outside_shift', '23514', 'Os intervalos precisam ficar dentro da jornada.');
select tests.throws_detail('break_open_on_closed_shift (trigger): 23514 + frase de §3.7',
  $$insert into public.time_breaks (shift_id, user_id, started_at) values (tests.uvar('a'), tests.uid('emp'), tests.brt('2026-10-05 11:00'))$$,
  'break_open_on_closed_shift', '23514', 'Informe o fim de todos os intervalos de uma jornada encerrada.');
select tests.throws_detail('audit_immutable (time_audit_events): 42501 + frase de §3.7',
  $$update public.time_audit_events set reason = 'adulterada' where shift_id = tests.uvar('a')$$,
  'audit_immutable', '42501', '%Você não tem permissão para esta ação.');
select tests.throws_detail('audit_immutable (work_task_events): 42501 + frase de §3.7',
  $$delete from public.work_task_events where task_id = tests.uvar('t')$$,
  'audit_immutable', '42501', '%Você não tem permissão para esta ação.');

select tests.done();
rollback;
