-- 13 — Correção manual (time_correct_shift, §3.3): cada código de validação e
-- a ordem entre eles, substituição da lista inteira de intervalos, auditoria
-- (antes/depois/autor/justificativa/data), regra de review_status, trava
-- depois da revisão, anuladas, sobreposição. Tudo como authenticated.
begin;

select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.create_user('mgr', 'manager');
select tests.create_user('sa', 'super_admin');

select tests.login('emp');
select tests.capture('a', $$select public.time_create_manual_shift(null, tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
    jsonb_build_array(tests.brk(tests.brt('2026-10-13 09:00'), tests.brt('2026-10-13 09:15'))),
    'Esqueci de bater nesse dia')::jsonb->>'id'$$);
select tests.capture('b', $$select public.time_create_manual_shift(null, tests.brt('2026-10-14 08:00'), tests.brt('2026-10-14 12:00'),
    '[]'::jsonb, 'Esqueci de bater nesse dia')::jsonb->>'id'$$);
select tests.step('jornada C pelo relógio: entrada', $$select public.time_clock_in()$$);
select tests.step('jornada C: intervalo', $$select public.time_start_break()$$);
select tests.step('jornada C: retorno', $$select public.time_end_break()$$);
select tests.capture('c_json', $$select public.time_clock_out()::text$$);
select tests.set_var('c', tests.jvar('c_json')->>'id');
select tests.capture('a_break', $$select id::text from public.time_breaks where shift_id = tests.uvar('a')$$);

-- Chamada válida de referência em A (as variações mudam um parâmetro por vez).
-- A: 2026-10-13 08:00–12:00, intervalo 09:00–09:15.

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('invalid_reason (10..1000 após trim)');
select tests.throws('justificativa nula → invalid_reason',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[]'::jsonb, null)$$,
  'invalid_reason', 'P0001');
select tests.throws('justificativa vazia → invalid_reason',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[]'::jsonb, '')$$,
  'invalid_reason', 'P0001');
select tests.throws('justificativa só com espaços → invalid_reason',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[]'::jsonb, '              ')$$,
  'invalid_reason', 'P0001');
select tests.throws('9 caracteres → invalid_reason',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[]'::jsonb, 'abcdefghi')$$,
  'invalid_reason', 'P0001');
select tests.throws('9 caracteres cercados de espaços (trim) → invalid_reason',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[]'::jsonb, '    abcdefghi    ')$$,
  'invalid_reason', 'P0001');
select tests.throws('1001 caracteres → invalid_reason',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[]'::jsonb, repeat('a', 1001))$$,
  'invalid_reason', 'P0001');
-- "Após trim" vale para qualquer espaço em branco, não só o ASCII: o app
-- (String.trim do Dart) descarta espaço não separável, espaço ideográfico,
-- BOM etc., e o servidor não pode aceitar uma justificativa que, para o app,
-- é vazia ou curta.
select tests.throws('justificativa só com espaços Unicode (NBSP, U+2003, U+3000, BOM) → invalid_reason',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[]'::jsonb,
      repeat(U&'\00A0', 4) || repeat(U&'\2003', 4) || repeat(U&'\3000', 4) || U&'\FEFF')$$,
  'invalid_reason', 'P0001');
select tests.throws('9 caracteres cercados de tab e quebras de linha → invalid_reason',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[]'::jsonb,
      E'\t\n\r\x0b\x0c' || 'abcdefghi' || E'\n\t')$$,
  'invalid_reason', 'P0001');
select tests.throws('9 caracteres cercados de espaços Unicode → invalid_reason',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[]'::jsonb,
      U&'\00A0\3000\2028' || 'abcdefghi' || U&'\202F\205F\0085')$$,
  'invalid_reason', 'P0001');
select tests.throws('ordem: justificativa ruim vem antes de cannot_reopen',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), null, '[]'::jsonb, 'curta')$$,
  'invalid_reason', 'P0001');
select tests.throws('ordem: justificativa ruim vem antes de invalid_range',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 12:00'), tests.brt('2026-10-13 08:00'), '[]'::jsonb, 'curta')$$,
  'invalid_reason', 'P0001');

select tests.note('cannot_reopen, invalid_range, future_timestamp');
select tests.throws('jornada encerrada com p_ended_at nulo → cannot_reopen',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), null, '[]'::jsonb, 'Justificativa válida')$$,
  'cannot_reopen', 'P0001');
select tests.throws('fim = início → invalid_range',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 08:00'), '[]'::jsonb, 'Justificativa válida')$$,
  'invalid_range', 'P0001');
select tests.throws('fim antes do início → invalid_range',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 12:00'), tests.brt('2026-10-13 08:00'), '[]'::jsonb, 'Justificativa válida')$$,
  'invalid_range', 'P0001');
select tests.throws('ordem: invalid_range vem antes de future_timestamp',
  $$select public.time_correct_shift(tests.uvar('a'), clock_timestamp() + interval '2 hours', clock_timestamp() + interval '1 hour', '[]'::jsonb, 'Justificativa válida')$$,
  'invalid_range', 'P0001');
select tests.throws('fim no futuro → future_timestamp',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), clock_timestamp() + interval '1 minute', '[]'::jsonb, 'Justificativa válida')$$,
  'future_timestamp', 'P0001');
-- "tolerância zero" (§3.3): 1 segundo à frente do relógio do servidor já é
-- futuro (o parâmetro é calculado antes da chamada, então fica > v_now).
select tests.throws('fim 1 segundo no futuro → future_timestamp (tolerância zero)',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), clock_timestamp() + interval '1 second', '[]'::jsonb, 'Justificativa válida')$$,
  'future_timestamp', 'P0001');
select tests.throws('intervalo terminando 1 segundo no futuro → future_timestamp (tolerância zero)',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), clock_timestamp() - interval '1 minute',
      jsonb_build_array(tests.brk(clock_timestamp() - interval '2 minutes', clock_timestamp() + interval '1 second')), 'Justificativa válida')$$,
  'future_timestamp', 'P0001');
select tests.throws('início e fim no futuro → future_timestamp',
  $$select public.time_correct_shift(tests.uvar('a'), clock_timestamp() + interval '1 hour', clock_timestamp() + interval '2 hours', '[]'::jsonb, 'Justificativa válida')$$,
  'future_timestamp', 'P0001');
select tests.throws('intervalo no futuro → future_timestamp',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), clock_timestamp() - interval '1 minute',
      jsonb_build_array(tests.brk(clock_timestamp() + interval '1 minute', clock_timestamp() + interval '2 minutes')), 'Justificativa válida')$$,
  'future_timestamp', 'P0001');
select tests.throws('ordem: future_timestamp vem antes do intervalo invertido',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), clock_timestamp() - interval '1 minute',
      jsonb_build_array(tests.brk(clock_timestamp() + interval '2 hours', clock_timestamp() + interval '1 hour')), 'Justificativa válida')$$,
  'future_timestamp', 'P0001');

select tests.note('intervalos: invalid_range, break_outside_shift, breaks_overlap, break_open_on_closed_shift');
select tests.throws('intervalo com fim = início → invalid_range',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 09:00'), tests.brt('2026-10-13 09:00'))), 'Justificativa válida')$$,
  'invalid_range', 'P0001');
select tests.throws('intervalo com fim antes do início → invalid_range',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 10:00'), tests.brt('2026-10-13 09:00'))), 'Justificativa válida')$$,
  'invalid_range', 'P0001');
select tests.throws('ordem: intervalo invertido E fora da jornada → invalid_range',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 07:00'), tests.brt('2026-10-13 06:00'))), 'Justificativa válida')$$,
  'invalid_range', 'P0001');
select tests.throws('intervalo começa antes da entrada → break_outside_shift',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 07:30'), tests.brt('2026-10-13 08:30'))), 'Justificativa válida')$$,
  'break_outside_shift', 'P0001');
select tests.throws('intervalo termina depois da saída → break_outside_shift',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 11:30'), tests.brt('2026-10-13 12:30'))), 'Justificativa válida')$$,
  'break_outside_shift', 'P0001');
select tests.throws('intervalo inteiro fora da jornada → break_outside_shift',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 13:00'), tests.brt('2026-10-13 13:30'))), 'Justificativa válida')$$,
  'break_outside_shift', 'P0001');
select tests.throws('ordem: fora da jornada vem antes de sobreposição',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 07:00'), tests.brt('2026-10-13 08:30')),
                        tests.brk(tests.brt('2026-10-13 08:15'), tests.brt('2026-10-13 09:00'))), 'Justificativa válida')$$,
  'break_outside_shift', 'P0001');
select tests.throws('intervalos sobrepostos → breaks_overlap',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 09:00'), tests.brt('2026-10-13 10:00')),
                        tests.brk(tests.brt('2026-10-13 09:30'), tests.brt('2026-10-13 10:30'))), 'Justificativa válida')$$,
  'breaks_overlap', 'P0001');
select tests.throws('intervalos repetidos → breaks_overlap',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 09:00'), tests.brt('2026-10-13 09:30')),
                        tests.brk(tests.brt('2026-10-13 09:00'), tests.brt('2026-10-13 09:30'))), 'Justificativa válida')$$,
  'breaks_overlap', 'P0001');
select tests.throws('intervalos fora de ordem (contrato: ordenados) → breaks_overlap',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 10:00'), tests.brt('2026-10-13 10:30')),
                        tests.brk(tests.brt('2026-10-13 09:00'), tests.brt('2026-10-13 09:30'))), 'Justificativa válida')$$,
  'breaks_overlap', 'P0001');
select tests.throws('jornada encerrada com intervalo aberto → break_open_on_closed_shift',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 09:00'), null)), 'Justificativa válida')$$,
  'break_open_on_closed_shift', 'P0001');

select tests.note('invalid_breaks (formato)');
select tests.throws('p_breaks objeto → invalid_breaks',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '{}'::jsonb, 'Justificativa válida')$$,
  'invalid_breaks', 'P0001');
select tests.throws('p_breaks string → invalid_breaks',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '"x"'::jsonb, 'Justificativa válida')$$,
  'invalid_breaks', 'P0001');
select tests.throws('elemento que não é objeto → invalid_breaks',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[1]'::jsonb, 'Justificativa válida')$$,
  'invalid_breaks', 'P0001');
select tests.throws('elemento sem started_at → invalid_breaks',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      jsonb_build_array(jsonb_build_object('ended_at', tests.brt('2026-10-13 09:00'))), 'Justificativa válida')$$,
  'invalid_breaks', 'P0001');
select tests.throws('started_at nulo → invalid_breaks',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      '[{"started_at": null, "ended_at": null}]'::jsonb, 'Justificativa válida')$$,
  'invalid_breaks', 'P0001');
select tests.throws('started_at que não é horário → invalid_breaks',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      '[{"started_at": "ontem de manhã", "ended_at": null}]'::jsonb, 'Justificativa válida')$$,
  'invalid_breaks', 'P0001');
select tests.throws('ended_at que não é horário → invalid_breaks',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'),
      '[{"started_at": "2026-10-13T12:00:00Z", "ended_at": "depois"}]'::jsonb, 'Justificativa válida')$$,
  'invalid_breaks', 'P0001');
-- §3.3: p_breaks é "array de {…}"; o app manda sempre uma lista ([] = sem
-- intervalos). Nulo não é lista: leitura conservadora (§0) = formato ruim, e
-- nunca "apagar todos os intervalos" por omissão.
select tests.throws('p_breaks nulo (SQL) → invalid_breaks (não apaga os intervalos)',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), null, 'Justificativa válida')$$,
  'invalid_breaks', 'P0001');
select tests.throws('p_breaks null em JSON → invalid_breaks',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), 'null'::jsonb, 'Justificativa válida')$$,
  'invalid_breaks', 'P0001');
select tests.throws('elemento null na lista → invalid_breaks',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[null]'::jsonb, 'Justificativa válida')$$,
  'invalid_breaks', 'P0001');
select tests.admin_rows('… e o intervalo de A continua lá',
  $$select 1 from public.time_breaks where shift_id = tests.uvar('a')$$, 1);

select tests.admin_query_is('nenhuma tentativa inválida alterou A',
  $$select (started_at = tests.brt('2026-10-13 08:00') and ended_at = tests.brt('2026-10-13 12:00'))::text
     from public.time_shifts where id = tests.uvar('a')$$, 'true');
select tests.admin_rows('nenhuma tentativa inválida gerou auditoria correct',
  $$select 1 from public.time_audit_events where subject_user_id = tests.uid('emp') and action = 'correct'$$, 0);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('correção válida pelo dono: substitui horários e a lista inteira de intervalos');
select tests.capture('a1', $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 07:30'), tests.brt('2026-10-13 12:30'),
    jsonb_build_array(tests.brk(tests.brt('2026-10-13 09:00'), tests.brt('2026-10-13 09:30')),
                      tests.brk(tests.brt('2026-10-13 10:00'), tests.brt('2026-10-13 10:10'))),
    'Cheguei mais cedo e saí mais tarde')::text$$);
select tests.eq('resposta: JSON da jornada + server_now', tests.keys(tests.jvar('a1')), tests.k_rpc());
select tests.query_true('resposta: novos horários',
  $$select (tests.jvar('a1')->>'started_at')::timestamptz = tests.brt('2026-10-13 07:30')
       and (tests.jvar('a1')->>'ended_at')::timestamptz = tests.brt('2026-10-13 12:30')$$);
select tests.is('resposta: dois intervalos', tests.jlen(tests.jvar('a1')->'time_breaks'), 2);
select tests.query_true('resposta: intervalos com os horários enviados, em ordem',
  $$select (tests.jvar('a1')->'time_breaks'->0->>'started_at')::timestamptz = tests.brt('2026-10-13 09:00')
       and (tests.jvar('a1')->'time_breaks'->0->>'ended_at')::timestamptz = tests.brt('2026-10-13 09:30')
       and (tests.jvar('a1')->'time_breaks'->1->>'started_at')::timestamptz = tests.brt('2026-10-13 10:00')
       and (tests.jvar('a1')->'time_breaks'->1->>'ended_at')::timestamptz = tests.brt('2026-10-13 10:10')$$);
select tests.admin_rows('o intervalo antigo foi removido (lista substituída)',
  $$select 1 from public.time_breaks where id = tests.uvar('a_break')$$, 0);
select tests.admin_rows('verdade: dois intervalos de A, do dono da jornada',
  $$select 1 from public.time_breaks where shift_id = tests.uvar('a') and user_id = tests.uid('emp')$$, 2);
select tests.eq('dono corrigindo → pending', tests.jvar('a1')->>'review_status', 'pending');
select tests.ok('pending: reviewed_at/by nulos',
  jsonb_typeof(tests.jvar('a1')->'reviewed_at') = 'null' and jsonb_typeof(tests.jvar('a1')->'reviewed_by') = 'null');
select tests.query_true('last_corrected_by = dono; last_corrected_at = instante da chamada',
  $$select (tests.jvar('a1')->>'last_corrected_by')::uuid = tests.uid('emp')
       and (tests.jvar('a1')->>'last_corrected_at')::timestamptz between now() and clock_timestamp()$$);
select tests.eq('work_date acompanha o novo início', tests.jvar('a1')->>'work_date', '2026-10-13');

select tests.note('auditoria da correção');
select tests.query_is('uma auditoria correct em A', $$select count(*)::text from public.time_audit_events where shift_id = tests.uvar('a') and action = 'correct'$$, '1');
select tests.query_true('autor, dono, justificativa e request_id',
  $$select actor_id = tests.uid('emp') and subject_user_id = tests.uid('emp')
       and reason = 'Cheguei mais cedo e saí mais tarde' and request_id is null
     from public.time_audit_events where shift_id = tests.uvar('a') and action = 'correct'$$);
select tests.query_true('before = valor anterior (08:00–12:00, um intervalo 09:00–09:15)',
  $$select (before->>'started_at')::timestamptz = tests.brt('2026-10-13 08:00')
       and (before->>'ended_at')::timestamptz = tests.brt('2026-10-13 12:00')
       and tests.jlen(before->'time_breaks') = 1
       and (before->'time_breaks'->0->>'started_at')::timestamptz = tests.brt('2026-10-13 09:00')
       and (before->'time_breaks'->0->>'ended_at')::timestamptz = tests.brt('2026-10-13 09:15')
       and before->>'review_status' = 'pending'
     from public.time_audit_events where shift_id = tests.uvar('a') and action = 'correct'$$);
select tests.query_true('after = valor novo (07:30–12:30, dois intervalos, last_corrected_by)',
  $$select (after->>'started_at')::timestamptz = tests.brt('2026-10-13 07:30')
       and (after->>'ended_at')::timestamptz = tests.brt('2026-10-13 12:30')
       and tests.jlen(after->'time_breaks') = 2
       and (after->>'last_corrected_by')::uuid = tests.uid('emp')
     from public.time_audit_events where shift_id = tests.uvar('a') and action = 'correct'$$);
select tests.query_true('before/after no formato §3.4, sem server_now',
  $$select tests.keys(before) = tests.k_shift() and tests.keys(after) = tests.k_shift()
     from public.time_audit_events where shift_id = tests.uvar('a') and action = 'correct'$$);
select tests.query_true('data da auditoria = instante da chamada; seq depois da create_manual',
  $$select c.created_at between now() and clock_timestamp() and c.seq > m.seq
     from public.time_audit_events c, public.time_audit_events m
    where c.shift_id = tests.uvar('a') and c.action = 'correct' and m.shift_id = tests.uvar('a') and m.action = 'create_manual'$$);

select tests.note('jornada do relógio: none → pending, intervalo removido');
select tests.capture('c1', $$select public.time_correct_shift(tests.uvar('c'),
    (tests.jvar('c_json')->>'started_at')::timestamptz - interval '1 hour', (tests.jvar('c_json')->>'ended_at')::timestamptz,
    '[]'::jsonb, 'O intervalo foi registrado por engano')::text$$);
select tests.eq('pending depois da correção', tests.jvar('c1')->>'review_status', 'pending');
select tests.eq('lista vazia remove os intervalos', (tests.jvar('c1')->'time_breaks')::text, '[]');
select tests.query_true('auditoria: before none com 1 intervalo → after pending sem intervalos',
  $$select before->>'review_status' = 'none' and after->>'review_status' = 'pending'
       and tests.jlen(before->'time_breaks') = 1 and tests.jlen(after->'time_breaks') = 0
     from public.time_audit_events where shift_id = tests.uvar('c') and action = 'correct'$$);
select tests.eq('source continua clock', tests.jvar('c1')->>'source', 'clock');

select tests.note('limites aceitos');
select tests.lives('justificativa com exatamente 10 caracteres após trim',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 07:30'), tests.brt('2026-10-13 12:30'), '[]'::jsonb, '   abcdefghij   ')$$);
select tests.lives('justificativa com 1000 caracteres',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 07:30'), tests.brt('2026-10-13 12:30'), '[]'::jsonb, repeat('b', 1000))$$);
-- Limites contam CARACTERES (como o app), não bytes: texto pt-BR acentuado.
select tests.lives('justificativa acentuada com exatamente 10 caracteres (13 bytes)',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 07:30'), tests.brt('2026-10-13 12:30'), '[]'::jsonb, 'Atenção já')$$);
select tests.lives('justificativa com 1000 caracteres acentuados (2000 bytes)',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 07:30'), tests.brt('2026-10-13 12:30'), '[]'::jsonb, repeat('ç', 1000))$$);
select tests.throws('1001 caracteres acentuados → invalid_reason',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 07:30'), tests.brt('2026-10-13 12:30'), '[]'::jsonb, repeat('ç', 1001))$$,
  'invalid_reason', 'P0001');
select tests.lives('espaço Unicode no meio da justificativa é conteúdo (não é aparado)',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 07:30'), tests.brt('2026-10-13 12:30'), '[]'::jsonb, U&'Esqueci\00A0o crachá')$$);
select tests.lives('intervalos encostados entre si e nas bordas da jornada',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 07:30'), tests.brt('2026-10-13 12:30'),
      jsonb_build_array(tests.brk(tests.brt('2026-10-13 07:30'), tests.brt('2026-10-13 08:00')),
                        tests.brk(tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 09:00')),
                        tests.brk(tests.brt('2026-10-13 12:00'), tests.brt('2026-10-13 12:30'))),
      'Ajuste fino dos intervalos')$$);
select tests.admin_rows('verdade: três intervalos depois do ajuste', $$select 1 from public.time_breaks where shift_id = tests.uvar('a')$$, 3);

select tests.note('sobreposição com outra jornada do dono');
select tests.throws('mover C para dentro de A → shift_overlap',
  $$select public.time_correct_shift(tests.uvar('c'), tests.brt('2026-10-13 10:00'), tests.brt('2026-10-13 11:00'), '[]'::jsonb, 'Data registrada errada')$$,
  'shift_overlap', 'P0001');
select tests.lives('encostar C no fim de A (12:30) é válido',
  $$select public.time_correct_shift(tests.uvar('c'), tests.brt('2026-10-13 12:30'), tests.brt('2026-10-13 13:00'), '[]'::jsonb, 'Data registrada errada')$$);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('jornada aberta: correção pelo dono');
select tests.login('emp2');
select tests.step('entrada', $$select public.time_clock_in()$$);
select tests.capture('o', $$select public.time_my_status()->'open_shift'->>'id'$$);
select tests.capture('o1', $$select public.time_correct_shift(tests.uvar('o'), now() - interval '3 hours', null, '[]'::jsonb,
    'Esqueci de registrar a entrada')::text$$);
select tests.eq('aberta continua aberta (p_ended_at nulo)', jsonb_typeof(tests.jvar('o1')->'ended_at'), 'null');
select tests.eq('aberta corrigida pelo dono → pending', tests.jvar('o1')->>'review_status', 'pending');
select tests.throws('aberta: dois intervalos abertos → breaks_overlap',
  $$select public.time_correct_shift(tests.uvar('o'), now() - interval '3 hours', null,
      jsonb_build_array(tests.brk(now() - interval '2 hours', null), tests.brk(now() - interval '1 hour', null)), 'Justificativa válida')$$,
  'breaks_overlap', 'P0001');
select tests.throws('aberta: intervalo aberto que não é o último → breaks_overlap',
  $$select public.time_correct_shift(tests.uvar('o'), now() - interval '3 hours', null,
      jsonb_build_array(tests.brk(now() - interval '2 hours', null), tests.brk(now() - interval '1 hour', now() - interval '30 minutes')), 'Justificativa válida')$$,
  'breaks_overlap', 'P0001');
select tests.throws('aberta: intervalo antes da entrada → break_outside_shift',
  $$select public.time_correct_shift(tests.uvar('o'), now() - interval '3 hours', null,
      jsonb_build_array(tests.brk(now() - interval '4 hours', now() - interval '210 minutes')), 'Justificativa válida')$$,
  'break_outside_shift', 'P0001');
select tests.throws('aberta: intervalo começando no futuro → future_timestamp',
  $$select public.time_correct_shift(tests.uvar('o'), now() - interval '3 hours', null,
      jsonb_build_array(tests.brk(clock_timestamp() + interval '1 minute', null)), 'Justificativa válida')$$,
  'future_timestamp', 'P0001');
select tests.throws('aberta: entrada no futuro → future_timestamp',
  $$select public.time_correct_shift(tests.uvar('o'), clock_timestamp() + interval '1 minute', null, '[]'::jsonb, 'Justificativa válida')$$,
  'future_timestamp', 'P0001');
select tests.capture('o2', $$select public.time_correct_shift(tests.uvar('o'), now() - interval '3 hours', null,
    jsonb_build_array(tests.brk(now() - interval '2 hours', now() - interval '1 hour'), tests.brk(now() - interval '30 minutes', null)),
    'Esqueci de registrar as pausas')::text$$);
select tests.is('aberta: um intervalo aberto como último é aceito', tests.jlen(tests.jvar('o2')->'time_breaks'), 2);
select tests.query_is('status: em intervalo',
  $$select jsonb_typeof(public.time_my_status()->'open_shift'->'time_breaks'->1->'ended_at')$$, 'null');
select tests.throws('em intervalo pela correção: novo intervalo → break_already_open',
  $$select public.time_start_break()$$, 'break_already_open', 'P0001');
select tests.capture('o3', $$select public.time_correct_shift(tests.uvar('o'), now() - interval '3 hours', now() - interval '10 minutes',
    jsonb_build_array(tests.brk(now() - interval '2 hours', now() - interval '1 hour')),
    'Esqueci de registrar a saída')::text$$);
select tests.query_true('dono encerra a jornada aberta pela correção (horário real de saída)',
  $$select (tests.jvar('o3')->>'ended_at')::timestamptz = now() - interval '10 minutes'$$);
select tests.query_is('… sem jornada aberta depois', $$select jsonb_typeof(public.time_my_status()->'open_shift')$$, 'null');
select tests.eq('… pending', tests.jvar('o3')->>'review_status', 'pending');

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('super_admin corrigindo: aberta → pending; encerrada → reviewed');
select tests.step('emp2: nova entrada', $$select public.time_clock_in()$$);
select tests.capture('o4', $$select public.time_my_status()->'open_shift'->>'id'$$);
select tests.login('sa');
select tests.capture('sa1', $$select public.time_correct_shift(tests.uvar('o4'), now() - interval '5 minutes', null,
    jsonb_build_array(tests.brk(now() - interval '4 minutes', now() - interval '3 minutes')), 'Ajuste pedido pela pessoa')::text$$);
select tests.eq('super_admin corrigindo jornada ABERTA → pending', tests.jvar('sa1')->>'review_status', 'pending');
select tests.ok('… reviewed_at/by nulos',
  jsonb_typeof(tests.jvar('sa1')->'reviewed_at') = 'null' and jsonb_typeof(tests.jvar('sa1')->'reviewed_by') = 'null');
select tests.query_true('… last_corrected_by = super_admin; jornada continua da pessoa',
  $$select (tests.jvar('sa1')->>'last_corrected_by')::uuid = tests.uid('sa') and (tests.jvar('sa1')->>'user_id')::uuid = tests.uid('emp2')$$);
select tests.query_true('… intervalo criado pelo super_admin pertence ao dono da jornada',
  $$select (tests.jvar('sa1')->'time_breaks'->0->>'user_id')::uuid = tests.uid('emp2')$$);
select tests.query_true('auditoria: autor super_admin, dono emp2',
  $$select actor_id = tests.uid('sa') and subject_user_id = tests.uid('emp2') and reason = 'Ajuste pedido pela pessoa'
     from public.time_audit_events where shift_id = tests.uvar('o4') and action = 'correct'$$);

select tests.capture('b1', $$select public.time_correct_shift(tests.uvar('b'), tests.brt('2026-10-14 08:00'), tests.brt('2026-10-14 13:00'),
    '[]'::jsonb, 'Conferido com a agenda do dia')::text$$);
select tests.eq('super_admin corrigindo jornada ENCERRADA → reviewed', tests.jvar('b1')->>'review_status', 'reviewed');
select tests.query_true('… reviewed_by = super_admin, reviewed_at = instante da chamada',
  $$select (tests.jvar('b1')->>'reviewed_by')::uuid = tests.uid('sa')
       and (tests.jvar('b1')->>'reviewed_at')::timestamptz between now() and clock_timestamp()$$);
select tests.throws('super_admin não reabre jornada encerrada → cannot_reopen',
  $$select public.time_correct_shift(tests.uvar('b'), tests.brt('2026-10-14 08:00'), null, '[]'::jsonb, 'Justificativa válida')$$,
  'cannot_reopen', 'P0001');

select tests.note('trava depois da revisão');
select tests.login('emp');
select tests.throws('dono corrigindo jornada revisada → shift_locked',
  $$select public.time_correct_shift(tests.uvar('b'), tests.brt('2026-10-14 08:00'), tests.brt('2026-10-14 12:00'), '[]'::jsonb, 'Quero mudar de novo')$$,
  'shift_locked', 'P0001');
select tests.throws('dono anulando jornada revisada → shift_locked',
  $$select public.time_void_shift(tests.uvar('b'), 'Quero anular esta jornada')$$, 'shift_locked', 'P0001');
select tests.admin_query_is('jornada revisada intacta', $$select ended_at = tests.brt('2026-10-14 13:00') from public.time_shifts where id = tests.uvar('b')$$, 'true');
select tests.login('sa');
select tests.capture('b2', $$select public.time_correct_shift(tests.uvar('b'), tests.brt('2026-10-14 08:00'), tests.brt('2026-10-14 12:30'),
    '[]'::jsonb, 'Segunda conferência do dia')::text$$);
select tests.eq('super_admin ainda corrige a revisada; continua reviewed', tests.jvar('b2')->>'review_status', 'reviewed');

select tests.note('manager corrige o próprio ponto como qualquer dono');
select tests.login('mgr');
select tests.capture('m', $$select public.time_create_manual_shift(null, tests.brt('2026-10-15 09:00'), tests.brt('2026-10-15 18:00'),
    '[]'::jsonb, 'Reunião externa o dia todo')::jsonb->>'id'$$);
select tests.capture('m1', $$select public.time_correct_shift(tests.uvar('m'), tests.brt('2026-10-15 09:00'), tests.brt('2026-10-15 17:00'),
    '[]'::jsonb, 'Saí uma hora mais cedo')::text$$);
select tests.eq('manager corrigindo o próprio → pending (não reviewed)', tests.jvar('m1')->>'review_status', 'pending');

select tests.note('anulada não se corrige');
select tests.login('emp');
select tests.step('dono anula A', $$select public.time_void_shift(tests.uvar('a'), 'Jornada lançada em duplicidade')$$);
select tests.throws('dono corrigindo anulada → shift_voided',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[]'::jsonb, 'Justificativa válida')$$,
  'shift_voided', 'P0001');
select tests.login('sa');
select tests.throws('super_admin corrigindo anulada → shift_voided',
  $$select public.time_correct_shift(tests.uvar('a'), tests.brt('2026-10-13 08:00'), tests.brt('2026-10-13 12:00'), '[]'::jsonb, 'Justificativa válida')$$,
  'shift_voided', 'P0001');

select tests.done();
rollback;
