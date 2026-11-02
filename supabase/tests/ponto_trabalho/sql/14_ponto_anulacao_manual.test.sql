-- 14 — Anulação (time_void_shift) e jornada manual (time_create_manual_shift),
-- §3.3: justificativa, anulada não volta, anular jornada aberta fecha
-- intervalo e jornada com UMA auditoria só, regra de review_status, quem pode
-- criar jornada para quem, validações da jornada manual. Como authenticated.
begin;

select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.create_user('emp3', 'employee');
select tests.create_user('mgr', 'manager');
select tests.create_user('sa', 'super_admin');
select tests.create_user('cli', 'client');
select tests.create_user('ghost', null);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('jornada manual pelo próprio dono');
select tests.login('emp');
select tests.capture('m1', $$select public.time_create_manual_shift(null, tests.brt('2026-10-16 08:00'), tests.brt('2026-10-16 12:00'),
    jsonb_build_array(tests.brk(tests.brt('2026-10-16 10:00'), tests.brt('2026-10-16 10:15'))),
    'Esqueci o celular em casa')::text$$);
select tests.set_var('s_m1', tests.jvar('m1')->>'id');
select tests.eq('resposta: JSON + server_now', tests.keys(tests.jvar('m1')), tests.k_rpc());
select tests.eq('source = manual', tests.jvar('m1')->>'source', 'manual');
select tests.query_true('p_user_id nulo ⇒ jornada do chamador', $$select (tests.jvar('m1')->>'user_id')::uuid = tests.uid('emp')$$);
select tests.eq('dono criando → pending', tests.jvar('m1')->>'review_status', 'pending');
select tests.is('com o intervalo informado', tests.jlen(tests.jvar('m1')->'time_breaks'), 1);
select tests.eq('work_date', tests.jvar('m1')->>'work_date', '2026-10-16');
select tests.query_true('auditoria create_manual: before nulo, after = jornada, justificativa, autor',
  $$select before is null and after->>'id' = tests.var('s_m1') and reason = 'Esqueci o celular em casa'
       and actor_id = tests.uid('emp') and subject_user_id = tests.uid('emp')
       and tests.keys(after) = tests.k_shift()
     from public.time_audit_events where shift_id = tests.uvar('s_m1') and action = 'create_manual'$$);
select tests.query_is('uma única auditoria na criação', $$select count(*)::text from public.time_audit_events where shift_id = tests.uvar('s_m1')$$, '1');
select tests.lives('p_user_id = o próprio chamador é aceito',
  $$select public.time_create_manual_shift(tests.uid('emp'), tests.brt('2026-10-17 08:00'), tests.brt('2026-10-17 09:00'), '[]'::jsonb, 'Esqueci o celular em casa')$$);

select tests.note('validações da jornada manual');
select tests.throws('p_ended_at obrigatório → invalid_range',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-18 08:00'), null, '[]'::jsonb, 'Justificativa válida')$$, 'invalid_range', 'P0001');
select tests.throws('justificativa curta → invalid_reason',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'), '[]'::jsonb, 'curta')$$, 'invalid_reason', 'P0001');
select tests.throws('justificativa nula → invalid_reason',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'), '[]'::jsonb, null)$$, 'invalid_reason', 'P0001');
select tests.throws('fim antes do início → invalid_range',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-18 12:00'), tests.brt('2026-10-18 08:00'), '[]'::jsonb, 'Justificativa válida')$$, 'invalid_range', 'P0001');
select tests.throws('fim no futuro → future_timestamp',
  $$select public.time_create_manual_shift(null, clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 minute', '[]'::jsonb, 'Justificativa válida')$$, 'future_timestamp', 'P0001');
select tests.throws('intervalo fora → break_outside_shift',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-18 07:00'), tests.brt('2026-10-18 07:30'))), 'Justificativa válida')$$, 'break_outside_shift', 'P0001');
select tests.throws('intervalo aberto em jornada encerrada → break_open_on_closed_shift',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-18 09:00'), null)), 'Justificativa válida')$$, 'break_open_on_closed_shift', 'P0001');
select tests.throws('intervalos sobrepostos → breaks_overlap',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-18 09:00'), tests.brt('2026-10-18 10:00')),
                        tests.brk(tests.brt('2026-10-18 09:59'), tests.brt('2026-10-18 10:30'))), 'Justificativa válida')$$, 'breaks_overlap', 'P0001');
select tests.throws('intervalo invertido → invalid_range',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-18 10:00'), tests.brt('2026-10-18 09:00'))), 'Justificativa válida')$$, 'invalid_range', 'P0001');
select tests.throws('p_breaks que não é lista → invalid_breaks',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'), '{"a": 1}'::jsonb, 'Justificativa válida')$$, 'invalid_breaks', 'P0001');
select tests.throws('p_breaks nulo → invalid_breaks (sem intervalos é [])',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'), null, 'Justificativa válida')$$, 'invalid_breaks', 'P0001');
select tests.throws('sobreposição com outra jornada do dono → shift_overlap',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-16 11:00'), tests.brt('2026-10-16 13:00'), '[]'::jsonb, 'Justificativa válida')$$, 'shift_overlap', 'P0001');
select tests.lives('encostada na outra jornada é válida',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-16 12:00'), tests.brt('2026-10-16 13:00'), '[]'::jsonb, 'Voltei depois do almoço')$$);
select tests.admin_rows('verdade: só as jornadas válidas foram criadas (3)',
  $$select 1 from public.time_shifts where user_id = tests.uid('emp')$$, 3);

select tests.note('quem pode criar jornada para quem');
select tests.throws('employee criando para outra pessoa → not_allowed',
  $$select public.time_create_manual_shift(tests.uid('emp2'), tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'), '[]'::jsonb, 'Justificativa válida')$$,
  'not_allowed', '42501');
select tests.login('mgr');
select tests.throws('manager criando para outra pessoa → not_allowed',
  $$select public.time_create_manual_shift(tests.uid('emp'), tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'), '[]'::jsonb, 'Justificativa válida')$$,
  'not_allowed', '42501');
select tests.admin_rows('verdade: nada criado para emp/emp2 por terceiros',
  $$select 1 from public.time_shifts where user_id in (tests.uid('emp'), tests.uid('emp2')) and work_date = '2026-10-18'$$, 0);
select tests.login('sa');
select tests.capture('sm', $$select public.time_create_manual_shift(tests.uid('emp2'), tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'),
    '[]'::jsonb, 'Lançado a pedido da pessoa')::text$$);
select tests.query_true('super_admin cria para pessoa interna: jornada dela', $$select (tests.jvar('sm')->>'user_id')::uuid = tests.uid('emp2')$$);
select tests.eq('super_admin + encerrada → reviewed', tests.jvar('sm')->>'review_status', 'reviewed');
select tests.query_true('… reviewed_by = super_admin', $$select (tests.jvar('sm')->>'reviewed_by')::uuid = tests.uid('sa')$$);
select tests.query_true('auditoria: autor super_admin, dono emp2, before nulo',
  $$select actor_id = tests.uid('sa') and subject_user_id = tests.uid('emp2') and before is null
     from public.time_audit_events where shift_id = (tests.jvar('sm')->>'id')::uuid and action = 'create_manual'$$);
select tests.throws('super_admin criando para client → not_allowed',
  $$select public.time_create_manual_shift(tests.uid('cli'), tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'), '[]'::jsonb, 'Justificativa válida')$$,
  'not_allowed', '42501');
select tests.throws('super_admin criando para usuário sem perfil → not_allowed',
  $$select public.time_create_manual_shift(tests.uid('ghost'), tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'), '[]'::jsonb, 'Justificativa válida')$$,
  'not_allowed', '42501');
select tests.throws('super_admin criando para uuid inexistente → not_allowed',
  $$select public.time_create_manual_shift(gen_random_uuid(), tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'), '[]'::jsonb, 'Justificativa válida')$$,
  'not_allowed', '42501');
select tests.capture('ss', $$select public.time_create_manual_shift(null, tests.brt('2026-10-18 08:00'), tests.brt('2026-10-18 12:00'),
    '[]'::jsonb, 'Lançando o meu próprio dia')::text$$);
select tests.eq('super_admin para si mesmo → reviewed', tests.jvar('ss')->>'review_status', 'reviewed');

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('anulação pelo dono de jornada encerrada');
select tests.login('emp');
select tests.throws('justificativa curta → invalid_reason',
  $$select public.time_void_shift(tests.uvar('s_m1'), 'curta')$$, 'invalid_reason', 'P0001');
select tests.throws('justificativa nula → invalid_reason',
  $$select public.time_void_shift(tests.uvar('s_m1'), null)$$, 'invalid_reason', 'P0001');
select tests.throws('justificativa de 9 caracteres após trim → invalid_reason',
  $$select public.time_void_shift(tests.uvar('s_m1'), '   abcdefghi   ')$$, 'invalid_reason', 'P0001');
select tests.throws('justificativa só com espaços Unicode (NBSP, U+3000) → invalid_reason',
  $$select public.time_void_shift(tests.uvar('s_m1'), repeat(U&'\00A0', 6) || repeat(U&'\3000', 6))$$, 'invalid_reason', 'P0001');
select tests.throws('jornada manual: justificativa só com espaços Unicode → invalid_reason',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-26 08:00'), tests.brt('2026-10-26 12:00'), '[]'::jsonb, repeat(U&'\2007', 12))$$,
  'invalid_reason', 'P0001');
-- §3.3 diz só "Justificativa ≥ 10" na anulação, mas a auditoria limita reason a
-- 1000 (time_audit_events.reason). Leitura conservadora: 1001 caracteres são
-- rejeitados (o código exato não é fixado; lacuna no relatório). O throws
-- desfaz a tentativa de qualquer jeito, então a próxima anulação parte do zero.
select tests.throws('justificativa com 1001 caracteres → rejeitada',
  $$select public.time_void_shift(tests.uvar('s_m1'), repeat('a', 1001))$$);
select tests.capture('v1', $$select public.time_void_shift(tests.uvar('s_m1'), 'Lancei no dia errado')::text$$);
select tests.eq('resposta: JSON + server_now', tests.keys(tests.jvar('v1')), tests.k_rpc());
select tests.query_true('voided_at/by/reason gravados',
  $$select (tests.jvar('v1')->>'voided_at')::timestamptz between now() and clock_timestamp()
       and (tests.jvar('v1')->>'voided_by')::uuid = tests.uid('emp')
       and tests.jvar('v1')->>'void_reason' = 'Lancei no dia errado'$$);
select tests.query_true('horários preservados',
  $$select (tests.jvar('v1')->>'started_at')::timestamptz = tests.brt('2026-10-16 08:00')
       and (tests.jvar('v1')->>'ended_at')::timestamptz = tests.brt('2026-10-16 12:00')$$);
select tests.eq('dono anulando → pending', tests.jvar('v1')->>'review_status', 'pending');
select tests.query_true('uma auditoria void com before/after/justificativa',
  $$select count(*) = 1 and bool_and(jsonb_typeof(before->'voided_at') = 'null' and jsonb_typeof(after->'voided_at') = 'string'
                                      and reason = 'Lancei no dia errado' and actor_id = tests.uid('emp'))
     from public.time_audit_events where shift_id = tests.uvar('s_m1') and action = 'void'$$);
select tests.throws('anular de novo → shift_voided',
  $$select public.time_void_shift(tests.uvar('s_m1'), 'Lancei no dia errado')$$, 'shift_voided', 'P0001');
select tests.capture('re', $$select public.time_create_manual_shift(null, tests.brt('2026-10-16 08:00'), tests.brt('2026-10-16 12:00'),
    '[]'::jsonb, 'Recriando a jornada certa')::jsonb->>'id'$$);
select tests.ok('anulada não bloqueia uma jornada nova no mesmo horário', tests.var('re') is not null);

select tests.note('anulação de jornada aberta em intervalo: fecha tudo, UMA auditoria');
select tests.login('emp3');
select tests.step('entrada', $$select public.time_clock_in()$$);
select tests.step('intervalo', $$select public.time_start_break()$$);
select tests.capture('o', $$select public.time_my_status()->'open_shift'->>'id'$$);
select tests.capture('vo', $$select public.time_void_shift(tests.uvar('o'), 'Bati o ponto sem querer')::text$$);
select tests.eq('jornada anulada fica encerrada', jsonb_typeof(tests.jvar('vo')->'ended_at'), 'string');
select tests.eq('… anulada', jsonb_typeof(tests.jvar('vo')->'voided_at'), 'string');
select tests.query_true('intervalo aberto fechado dentro da jornada',
  $$select bool_and(jsonb_typeof(b->'ended_at') = 'string'
                    and (b->>'ended_at')::timestamptz <= (tests.jvar('vo')->>'ended_at')::timestamptz)
     from jsonb_array_elements(tests.jvar('vo')->'time_breaks') b$$);
-- §3.3: "Se aberta: fecha intervalo e jornada em v_now antes" — o mesmo
-- instante da anulação, não um horário qualquer dentro da jornada.
select tests.query_true('intervalo e jornada fechados no MESMO instante da anulação (v_now)',
  $$select (tests.jvar('vo')->>'ended_at')::timestamptz = (tests.jvar('vo')->>'voided_at')::timestamptz
       and count(*) = 1
       and bool_and((b->>'ended_at')::timestamptz = (tests.jvar('vo')->>'voided_at')::timestamptz)
     from jsonb_array_elements(tests.jvar('vo')->'time_breaks') b$$);
select tests.query_true('auditoria void: before = aberta em intervalo (como estava); after = encerrada e anulada; justificativa',
  $$select count(*) = 1
       and bool_and(before->>'ended_at' is null and jsonb_array_length(before->'time_breaks') = 1
                    and before->'time_breaks'->0->>'ended_at' is null and before->>'voided_at' is null
                    and after->>'ended_at' is not null and after->>'voided_at' is not null
                    and after->'time_breaks'->0->>'ended_at' is not null
                    and reason = 'Bati o ponto sem querer' and actor_id = auth.uid())
     from public.time_audit_events where shift_id = tests.uvar('o') and action = 'void'$$);
select tests.query_is('auditoria: clock_in, break_start, void (sem break_end/clock_out)',
  $$select string_agg(action, ',' order by seq) from public.time_audit_events where shift_id = tests.uvar('o')$$,
  'clock_in,break_start,void');
select tests.query_is('fora da jornada depois de anular', $$select jsonb_typeof(public.time_my_status()->'open_shift')$$, 'null');
select tests.eq('dono anulando aberta → pending', tests.jvar('vo')->>'review_status', 'pending');
select tests.lives('nova entrada depois da anulação', $$select public.time_clock_in()$$);

select tests.note('anulação pelo super_admin');
select tests.login('sa');
select tests.capture('emp_open', $$select id::text from public.time_shifts where user_id = tests.uid('emp3') and ended_at is null$$);
select tests.capture('vsa', $$select public.time_void_shift(tests.uvar('emp_open'), 'Entrada registrada por engano')::text$$);
select tests.eq('super_admin anulando aberta de outra pessoa → encerrada', jsonb_typeof(tests.jvar('vsa')->'ended_at'), 'string');
select tests.eq('… e reviewed (super_admin + encerrada)', tests.jvar('vsa')->>'review_status', 'reviewed');
select tests.query_true('… voided_by e reviewed_by = super_admin',
  $$select (tests.jvar('vsa')->>'voided_by')::uuid = tests.uid('sa') and (tests.jvar('vsa')->>'reviewed_by')::uuid = tests.uid('sa')$$);
select tests.query_true('… auditoria void com autor super_admin e dono emp3',
  $$select actor_id = tests.uid('sa') and subject_user_id = tests.uid('emp3')
     from public.time_audit_events where shift_id = tests.uvar('emp_open') and action = 'void'$$);
select tests.login('emp2');
select tests.throws('dono não anula jornada revisada (criada pelo super_admin) → shift_locked',
  $$select public.time_void_shift((tests.jvar('sm')->>'id')::uuid, 'Quero anular esta jornada')$$, 'shift_locked', 'P0001');
select tests.admin_query_is('… continua sem anulação', $$select (voided_at is null)::text from public.time_shifts where id = (tests.jvar('sm')->>'id')::uuid$$, 'true');
select tests.login('sa');
select tests.capture('vsm', $$select public.time_void_shift((tests.jvar('sm')->>'id')::uuid, 'Lançada em duplicidade')::text$$);
select tests.ok('super_admin anula jornada revisada; continua reviewed',
  jsonb_typeof(tests.jvar('vsm')->'voided_at') = 'string' and tests.jvar('vsm')->>'review_status' = 'reviewed');

select tests.done();
rollback;
