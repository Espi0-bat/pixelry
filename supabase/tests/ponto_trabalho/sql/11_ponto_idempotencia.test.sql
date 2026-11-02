-- 11 — Idempotência por p_request_id (§3.3 passo 6): a mesma ação repetida
-- devolve a mesma jornada sem efeito novo; outra ação com o mesmo id →
-- request_id_conflict; exatamente UMA auditoria leva o request_id; o break_end
-- implícito da saída grava request_id nulo. O id é único POR AUTOR.
begin;

select tests.create_user('emp', 'employee');
select tests.create_user('mgr', 'manager');
select tests.new_id('r1');
select tests.new_id('r2');
select tests.new_id('r3');
select tests.new_id('r4');
select tests.new_id('r5');
select tests.new_id('r6');
select tests.new_id('r7');
select tests.new_id('r8');
select tests.new_id('r9');

select tests.login('emp');

select tests.note('entrada repetida');
select tests.capture('a1', $$select public.time_clock_in(tests.uvar('r1'), 'primeira')::text$$);
select tests.capture('a2', $$select public.time_clock_in(tests.uvar('r1'), 'repetida')::text$$);
select tests.ok('repetição da entrada devolve a MESMA jornada',
  tests.jvar('a1')->>'id' is not null and tests.jvar('a2')->>'id' = tests.jvar('a1')->>'id');
select tests.eq('repetição também traz server_now', tests.keys(tests.jvar('a2')), tests.k_rpc());
select tests.eq('repetição não aplica a nota nova', tests.jvar('a2')->>'note', 'primeira');
select tests.set_var('s1', tests.jvar('a1')->>'id');
select tests.admin_rows('verdade: uma jornada só', $$select 1 from public.time_shifts where user_id = tests.uid('emp')$$, 1);
select tests.admin_rows('verdade: uma auditoria com o request_id',
  $$select 1 from public.time_audit_events where request_id = tests.uvar('r1')$$, 1);
select tests.admin_rows('verdade: um clock_in na auditoria',
  $$select 1 from public.time_audit_events where subject_user_id = tests.uid('emp') and action = 'clock_in'$$, 1);
select tests.throws('entrada com OUTRO request_id segue a regra normal → shift_already_open',
  $$select public.time_clock_in(gen_random_uuid())$$, 'shift_already_open', 'P0001');
select tests.throws('intervalo com o request_id da entrada → request_id_conflict',
  $$select public.time_start_break(tests.uvar('r1'))$$, 'request_id_conflict', 'P0001');
select tests.throws('saída com o request_id da entrada → request_id_conflict',
  $$select public.time_clock_out(tests.uvar('r1'))$$, 'request_id_conflict', 'P0001');
select tests.throws('retorno com o request_id da entrada → request_id_conflict',
  $$select public.time_end_break(tests.uvar('r1'))$$, 'request_id_conflict', 'P0001');
select tests.admin_rows('conflito não cria intervalo', $$select 1 from public.time_breaks where shift_id = tests.uvar('s1')$$, 0);

select tests.note('intervalo e retorno repetidos');
select tests.capture('b1', $$select public.time_start_break(tests.uvar('r2'))::text$$);
select tests.capture('b2', $$select public.time_start_break(tests.uvar('r2'))::text$$);
select tests.ok('repetição do intervalo devolve a mesma jornada',
  tests.jvar('b1')->>'id' = tests.var('s1') and tests.jvar('b2')->>'id' = tests.var('s1'));
select tests.is('repetição do intervalo não abre outro', tests.jlen(tests.jvar('b2')->'time_breaks'), 1);
select tests.admin_rows('verdade: um intervalo aberto', $$select 1 from public.time_breaks where shift_id = tests.uvar('s1') and ended_at is null$$, 1);
select tests.admin_rows('verdade: um break_start', $$select 1 from public.time_audit_events where shift_id = tests.uvar('s1') and action = 'break_start'$$, 1);
select tests.capture('e1', $$select public.time_end_break(tests.uvar('r3'))::text$$);
select tests.capture('e2', $$select public.time_end_break(tests.uvar('r3'))::text$$);
select tests.eq('repetição do retorno devolve o mesmo fim de intervalo',
  tests.jvar('e2')->'time_breaks'->0->>'ended_at', tests.jvar('e1')->'time_breaks'->0->>'ended_at');
select tests.admin_rows('verdade: um break_end', $$select 1 from public.time_audit_events where shift_id = tests.uvar('s1') and action = 'break_end'$$, 1);
select tests.throws('intervalo com o request_id do retorno → request_id_conflict',
  $$select public.time_start_break(tests.uvar('r3'))$$, 'request_id_conflict', 'P0001');

select tests.note('saída com intervalo aberto, fechando-o, e repetição');
select tests.lives('novo intervalo', $$select public.time_start_break(tests.uvar('r4'))$$);
select tests.capture('o1', $$select public.time_clock_out(tests.uvar('r5'), true)::text$$);
select tests.eq('saída fechando o intervalo encerra a jornada', jsonb_typeof(tests.jvar('o1')->'ended_at'), 'string');
select tests.query_true('todos os intervalos fechados',
  $$select bool_and(jsonb_typeof(b->'ended_at') = 'string') from jsonb_array_elements(tests.jvar('o1')->'time_breaks') b$$);
select tests.query_true('o intervalo aberto foi fechado no mesmo instante da saída (v_now)',
  $$select (tests.jvar('o1')->'time_breaks'->1->>'ended_at')::timestamptz = (tests.jvar('o1')->>'ended_at')::timestamptz$$);
select tests.capture('o2', $$select public.time_clock_out(tests.uvar('r5'), true)::text$$);
select tests.ok('repetição da saída devolve a mesma jornada encerrada',
  tests.jvar('o2')->>'id' = tests.var('s1') and tests.jvar('o2')->>'ended_at' = tests.jvar('o1')->>'ended_at');
select tests.capture('o3', $$select public.time_clock_out(tests.uvar('r5'), false)::text$$);
select tests.eq('repetição com outros parâmetros também devolve a jornada (sem erro)', tests.jvar('o3')->>'id', tests.var('s1'));
select tests.admin_rows('verdade: um clock_out', $$select 1 from public.time_audit_events where shift_id = tests.uvar('s1') and action = 'clock_out'$$, 1);
select tests.admin_rows('verdade: uma linha com o request_id da saída',
  $$select 1 from public.time_audit_events where request_id = tests.uvar('r5')$$, 1);
select tests.admin_query_is('verdade: a linha do request_id da saída é a clock_out',
  $$select action from public.time_audit_events where request_id = tests.uvar('r5')$$, 'clock_out');
select tests.admin_rows('verdade: break_end implícito gravado com request_id nulo',
  $$select 1 from public.time_audit_events where shift_id = tests.uvar('s1') and action = 'break_end' and request_id is null$$, 1);
select tests.admin_query_is('verdade: ordem break_start, break_end(implícito), clock_out no fim',
  $$select string_agg(action, ',' order by seq) from (
      select action, seq from public.time_audit_events where shift_id = tests.uvar('s1') order by seq desc limit 3) q$$,
  'break_start,break_end,clock_out');
select tests.admin_rows('verdade: total de auditorias da jornada = 6',
  $$select 1 from public.time_audit_events where shift_id = tests.uvar('s1')$$, 6);

select tests.note('repetir a entrada depois da saída não cria jornada nova');
select tests.capture('a3', $$select public.time_clock_in(tests.uvar('r1'))::text$$);
select tests.eq('entrada repetida depois da saída devolve a jornada original', tests.jvar('a3')->>'id', tests.var('s1'));
select tests.eq('… já encerrada', jsonb_typeof(tests.jvar('a3')->'ended_at'), 'string');
select tests.admin_rows('verdade: continua uma jornada', $$select 1 from public.time_shifts where user_id = tests.uid('emp')$$, 1);

select tests.note('o request_id é único por autor');
select tests.login('mgr');
select tests.capture('m1', $$select public.time_clock_in(tests.uvar('r1'))::text$$);
select tests.ok('outra pessoa usa o mesmo request_id e ganha a PRÓPRIA jornada',
  tests.jvar('m1')->>'id' is not null and tests.jvar('m1')->>'id' <> tests.var('s1'));
select tests.query_true('… com user_id do manager', $$select (tests.jvar('m1')->>'user_id')::uuid = tests.uid('mgr')$$);
select tests.lives('manager: saída', $$select public.time_clock_out()$$);

select tests.note('correção, anulação e jornada manual repetidas');
select tests.login('emp');
select tests.capture('c1', $$select public.time_correct_shift(tests.uvar('s1'),
    (tests.jvar('a1')->>'started_at')::timestamptz - interval '1 hour',
    (tests.jvar('o1')->>'ended_at')::timestamptz, '[]'::jsonb,
    'Entrada esquecida no ônibus', tests.uvar('r6'))::text$$);
select tests.query_true('correção aplicada',
  $$select (tests.jvar('c1')->>'started_at')::timestamptz = (tests.jvar('a1')->>'started_at')::timestamptz - interval '1 hour'$$);
select tests.capture('c2', $$select public.time_correct_shift(tests.uvar('s1'),
    (tests.jvar('a1')->>'started_at')::timestamptz - interval '2 hours',
    (tests.jvar('o1')->>'ended_at')::timestamptz, '[]'::jsonb,
    'Outra justificativa qualquer', tests.uvar('r6'))::text$$);
select tests.eq('repetição da correção devolve o estado atual sem reaplicar', tests.jvar('c2')->>'started_at', tests.jvar('c1')->>'started_at');
select tests.eq('… com server_now', tests.keys(tests.jvar('c2')), tests.k_rpc());
select tests.admin_rows('verdade: uma auditoria correct', $$select 1 from public.time_audit_events where shift_id = tests.uvar('s1') and action = 'correct'$$, 1);
select tests.throws('anular com o request_id da correção → request_id_conflict',
  $$select public.time_void_shift(tests.uvar('s1'), 'Jornada duplicada por engano', tests.uvar('r6'))$$, 'request_id_conflict', 'P0001');
select tests.capture('v1', $$select public.time_void_shift(tests.uvar('s1'), 'Jornada duplicada por engano', tests.uvar('r7'))::text$$);
select tests.eq('anulação aplicada', jsonb_typeof(tests.jvar('v1')->'voided_at'), 'string');
select tests.capture('v2', $$select public.time_void_shift(tests.uvar('s1'), 'Jornada duplicada por engano', tests.uvar('r7'))::text$$);
select tests.eq('repetição da anulação devolve a jornada (sem shift_voided)', tests.jvar('v2')->>'voided_at', tests.jvar('v1')->>'voided_at');
select tests.admin_rows('verdade: uma auditoria void', $$select 1 from public.time_audit_events where shift_id = tests.uvar('s1') and action = 'void'$$, 1);
select tests.throws('anular de novo com outro request_id → shift_voided',
  $$select public.time_void_shift(tests.uvar('s1'), 'Jornada duplicada por engano', tests.uvar('r9'))$$, 'shift_voided', 'P0001');

select tests.capture('n1', $$select public.time_create_manual_shift(null, tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 12:00'),
    '[]'::jsonb, 'Esqueci de bater o ponto', tests.uvar('r8'))::text$$);
select tests.capture('n2', $$select public.time_create_manual_shift(null, tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 12:00'),
    '[]'::jsonb, 'Esqueci de bater o ponto', tests.uvar('r8'))::text$$);
select tests.ok('repetição da jornada manual devolve a mesma jornada',
  tests.jvar('n1')->>'id' is not null and tests.jvar('n2')->>'id' = tests.jvar('n1')->>'id');
select tests.admin_rows('verdade: uma jornada manual criada',
  $$select 1 from public.time_shifts where user_id = tests.uid('emp') and source = 'manual'$$, 1);
select tests.admin_rows('verdade: uma auditoria create_manual',
  $$select 1 from public.time_audit_events where subject_user_id = tests.uid('emp') and action = 'create_manual'$$, 1);
select tests.throws('entrada com o request_id da jornada manual → request_id_conflict',
  $$select public.time_clock_in(tests.uvar('r8'))$$, 'request_id_conflict', 'P0001');

-- §3.3 passo 6: com o request_id já registrado (mesma ação) a RPC NÃO reaplica
-- nada. O contrato não fixa a resposta quando o mesmo request_id volta apontando
-- para OUTRA jornada: o pseudo-código devolveria a jornada da chamada anterior;
-- a leitura conservadora (§0: rejeitar entrada inválida) responderia
-- request_id_conflict. Os dois são aceitos (lacuna registrada no relatório); o
-- que se exige é que a OUTRA jornada fique intacta e que não nasça auditoria.
select tests.note('request_id já usado em s1 não altera OUTRA jornada (n1)');
select tests.set_var('n1_id', tests.jvar('n1')->>'id');
select tests.attempt('rr_correct', $$select public.time_correct_shift(tests.uvar('n1_id'), tests.brt('2026-10-02 07:00'), tests.brt('2026-10-02 12:00'),
    '[]'::jsonb, 'Ajuste com id reaproveitado', tests.uvar('r6'))$$);
select tests.ok('correção de n1 com o request_id da correção de s1: request_id_conflict (P0001) ou repetição sem efeito',
  tests.var('rr_correct') in ('ok', 'P0001'), 'obtido ' || coalesce(tests.var('rr_correct'), 'NULL'));
select tests.attempt('rr_void', $$select public.time_void_shift(tests.uvar('n1_id'), 'Anular com id reaproveitado', tests.uvar('r7'))$$);
select tests.ok('anulação de n1 com o request_id da anulação de s1: request_id_conflict (P0001) ou repetição sem efeito',
  tests.var('rr_void') in ('ok', 'P0001'), 'obtido ' || coalesce(tests.var('rr_void'), 'NULL'));
select tests.admin_query_is('verdade: n1 intacta (horário, sem correção, sem anulação)',
  $$select (started_at = tests.brt('2026-10-02 08:00') and last_corrected_at is null and voided_at is null)::text
     from public.time_shifts where id = tests.uvar('n1_id')$$, 'true');
select tests.admin_rows('verdade: nenhuma auditoria em n1 além da create_manual',
  $$select 1 from public.time_audit_events where shift_id = tests.uvar('n1_id')$$, 1);
select tests.admin_rows('verdade: continua uma linha com cada request_id (r6, r7)',
  $$select 1 from public.time_audit_events where request_id in (tests.uvar('r6'), tests.uvar('r7'))$$, 2);

select tests.done();
rollback;
