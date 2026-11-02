-- 10 — Sequência da jornada (§3.3): entrada → intervalo → retorno → saída,
-- estado atual (time_my_status), cada código de erro de batida, formato do
-- JSON (§3.4) e a auditoria de cada batida. Tudo como authenticated.
begin;

select tests.create_user('emp', 'employee');
select tests.create_user('mgr', 'manager');
select tests.create_user('sa', 'super_admin');

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('fora da jornada');
select tests.login('emp');
select tests.capture('st0', $$select public.time_my_status()::text$$);
select tests.eq('time_my_status: chaves exatas {open_shift, server_now}', tests.keys(tests.jvar('st0')), 'open_shift,server_now');
select tests.eq('time_my_status: open_shift = null fora da jornada', jsonb_typeof(tests.jvar('st0')->'open_shift'), 'null');
select tests.query_true('time_my_status: server_now é o relógio do servidor',
  $$select (tests.jvar('st0')->>'server_now')::timestamptz between now() and clock_timestamp()$$);
select tests.throws('saída sem entrada → no_open_shift', $$select public.time_clock_out()$$, 'no_open_shift', 'P0001');
select tests.throws('saída sem entrada, fechando intervalo → no_open_shift',
  $$select public.time_clock_out(null, true)$$, 'no_open_shift', 'P0001');
select tests.throws('intervalo sem entrada → no_open_shift', $$select public.time_start_break()$$, 'no_open_shift', 'P0001');
select tests.throws('retorno sem entrada → no_open_shift', $$select public.time_end_break()$$, 'no_open_shift', 'P0001');
select tests.admin_rows('nenhuma jornada criada pelas batidas inválidas',
  $$select 1 from public.time_shifts where user_id = tests.uid('emp')$$, 0);
select tests.admin_rows('nenhuma auditoria criada pelas batidas inválidas',
  $$select 1 from public.time_audit_events where subject_user_id = tests.uid('emp')$$, 0);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('entrada');
select tests.capture('r_in', $$select public.time_clock_in(null, 'Começando pelos e-mails')::text$$);
select tests.set_var('s1', tests.jvar('r_in')->>'id');
select tests.eq('entrada: JSON com as chaves de §3.4 + server_now', tests.keys(tests.jvar('r_in')), tests.k_rpc());
select tests.is('entrada: user_id = chamador', tests.uvar('s1') is not null and (tests.jvar('r_in')->>'user_id')::uuid = tests.uid('emp'), true);
select tests.eq('entrada: source = clock', tests.jvar('r_in')->>'source', 'clock');
select tests.eq('entrada: note gravada', tests.jvar('r_in')->>'note', 'Começando pelos e-mails');
select tests.eq('entrada: ended_at = null', jsonb_typeof(tests.jvar('r_in')->'ended_at'), 'null');
select tests.eq('entrada: review_status = none', tests.jvar('r_in')->>'review_status', 'none');
select tests.eq('entrada: time_breaks = []', (tests.jvar('r_in')->'time_breaks')::text, '[]');
select tests.ok('entrada: sem revisão, correção nem anulação',
  jsonb_typeof(tests.jvar('r_in')->'reviewed_at') = 'null' and jsonb_typeof(tests.jvar('r_in')->'reviewed_by') = 'null'
  and jsonb_typeof(tests.jvar('r_in')->'last_corrected_at') = 'null' and jsonb_typeof(tests.jvar('r_in')->'voided_at') = 'null'
  and jsonb_typeof(tests.jvar('r_in')->'void_reason') = 'null');
select tests.query_true('entrada: started_at = clock_timestamp() da chamada (depois do now() da transação)',
  $$select (tests.jvar('r_in')->>'started_at')::timestamptz > now()
       and (tests.jvar('r_in')->>'started_at')::timestamptz <= clock_timestamp()$$);
select tests.query_true('entrada: started_at <= server_now',
  $$select (tests.jvar('r_in')->>'started_at')::timestamptz <= (tests.jvar('r_in')->>'server_now')::timestamptz$$);
select tests.query_true('entrada: work_date "YYYY-MM-DD" = data de Brasília do início',
  $$select tests.jvar('r_in')->>'work_date' ~ '^\d{4}-\d{2}-\d{2}$'
       and (tests.jvar('r_in')->>'work_date')::date
           = ((tests.jvar('r_in')->>'started_at')::timestamptz at time zone 'America/Sao_Paulo')::date$$);
select tests.admin_rows('verdade: uma jornada aberta para o employee',
  $$select 1 from public.time_shifts where user_id = tests.uid('emp') and ended_at is null and voided_at is null$$, 1);

select tests.throws('segunda entrada → shift_already_open', $$select public.time_clock_in()$$, 'shift_already_open', 'P0001');
select tests.throws('segunda entrada com nota → shift_already_open',
  $$select public.time_clock_in(null, 'de novo')$$, 'shift_already_open', 'P0001');
select tests.throws('retorno sem intervalo → no_open_break', $$select public.time_end_break()$$, 'no_open_break', 'P0001');
select tests.admin_rows('verdade: continua uma jornada só',
  $$select 1 from public.time_shifts where user_id = tests.uid('emp')$$, 1);

select tests.capture('st1', $$select public.time_my_status()::text$$);
select tests.eq('status em jornada: open_shift.id = jornada aberta', tests.jvar('st1')->'open_shift'->>'id', tests.var('s1'));
select tests.eq('status em jornada: open_shift com as chaves de §3.4',
  tests.keys((tests.jvar('st1')->'open_shift') - 'server_now'), tests.k_shift());
select tests.eq('status em jornada: sem intervalos', (tests.jvar('st1')->'open_shift'->'time_breaks')::text, '[]');

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('intervalo e retorno');
select tests.capture('r_b1', $$select public.time_start_break()::text$$);
select tests.eq('início de intervalo devolve a mesma jornada', tests.jvar('r_b1')->>'id', tests.var('s1'));
select tests.eq('início de intervalo: JSON com server_now', tests.keys(tests.jvar('r_b1')), tests.k_rpc());
select tests.is('início de intervalo: um intervalo', tests.jlen(tests.jvar('r_b1')->'time_breaks'), 1);
select tests.eq('intervalo: chaves de §3.4', tests.keys(tests.jvar('r_b1')->'time_breaks'->0), tests.k_break());
select tests.eq('intervalo: aberto (ended_at null)', jsonb_typeof(tests.jvar('r_b1')->'time_breaks'->0->'ended_at'), 'null');
select tests.eq('intervalo: shift_id = jornada', tests.jvar('r_b1')->'time_breaks'->0->>'shift_id', tests.var('s1'));
select tests.query_true('intervalo: user_id = dono da jornada',
  $$select (tests.jvar('r_b1')->'time_breaks'->0->>'user_id')::uuid = tests.uid('emp')$$);
select tests.query_true('intervalo: começa depois da entrada',
  $$select (tests.jvar('r_b1')->'time_breaks'->0->>'started_at')::timestamptz > (tests.jvar('r_in')->>'started_at')::timestamptz$$);
select tests.eq('jornada continua aberta durante o intervalo', jsonb_typeof(tests.jvar('r_b1')->'ended_at'), 'null');

select tests.throws('segundo intervalo aberto → break_already_open', $$select public.time_start_break()$$, 'break_already_open', 'P0001');
select tests.throws('entrada durante o intervalo → shift_already_open', $$select public.time_clock_in()$$, 'shift_already_open', 'P0001');
select tests.throws('saída com intervalo aberto (sem fechar) → break_open', $$select public.time_clock_out()$$, 'break_open', 'P0001');
select tests.throws('saída com intervalo aberto, p_close_open_break = false → break_open',
  $$select public.time_clock_out(null, false)$$, 'break_open', 'P0001');
select tests.admin_rows('verdade: um intervalo aberto só',
  $$select 1 from public.time_breaks where shift_id = tests.uvar('s1') and ended_at is null$$, 1);

select tests.capture('st2', $$select public.time_my_status()::text$$);
select tests.eq('status em intervalo: último intervalo aberto',
  jsonb_typeof(tests.jvar('st2')->'open_shift'->'time_breaks'->0->'ended_at'), 'null');

select tests.capture('r_e1', $$select public.time_end_break()::text$$);
select tests.eq('retorno devolve a mesma jornada', tests.jvar('r_e1')->>'id', tests.var('s1'));
select tests.query_true('retorno: intervalo fechado depois do início',
  $$select (tests.jvar('r_e1')->'time_breaks'->0->>'ended_at')::timestamptz
         > (tests.jvar('r_e1')->'time_breaks'->0->>'started_at')::timestamptz$$);
select tests.throws('segundo retorno → no_open_break', $$select public.time_end_break()$$, 'no_open_break', 'P0001');

select tests.lives('segundo intervalo', $$select public.time_start_break()$$);
select tests.capture('r_e2', $$select public.time_end_break()::text$$);
select tests.is('dois intervalos na jornada', tests.jlen(tests.jvar('r_e2')->'time_breaks'), 2);
select tests.query_true('intervalos em ordem de started_at',
  $$select (tests.jvar('r_e2')->'time_breaks'->0->>'started_at')::timestamptz
         < (tests.jvar('r_e2')->'time_breaks'->1->>'started_at')::timestamptz$$);
select tests.query_true('intervalos não se sobrepõem',
  $$select (tests.jvar('r_e2')->'time_breaks'->0->>'ended_at')::timestamptz
        <= (tests.jvar('r_e2')->'time_breaks'->1->>'started_at')::timestamptz$$);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('saída');
select tests.capture('r_out', $$select public.time_clock_out(null, false, 'Fim do dia')::text$$);
select tests.eq('saída devolve a mesma jornada', tests.jvar('r_out')->>'id', tests.var('s1'));
select tests.eq('saída: JSON com server_now', tests.keys(tests.jvar('r_out')), tests.k_rpc());
select tests.query_true('saída: ended_at depois do fim do último intervalo',
  $$select (tests.jvar('r_out')->>'ended_at')::timestamptz > (tests.jvar('r_out')->'time_breaks'->1->>'ended_at')::timestamptz$$);
select tests.query_true('saída: ended_at <= server_now',
  $$select (tests.jvar('r_out')->>'ended_at')::timestamptz <= (tests.jvar('r_out')->>'server_now')::timestamptz$$);
select tests.eq('saída: review_status continua none', tests.jvar('r_out')->>'review_status', 'none');
select tests.capture('st3', $$select public.time_my_status()::text$$);
select tests.eq('depois da saída: open_shift = null', jsonb_typeof(tests.jvar('st3')->'open_shift'), 'null');
select tests.throws('intervalo depois da saída → no_open_shift', $$select public.time_start_break()$$, 'no_open_shift', 'P0001');
select tests.throws('retorno depois da saída → no_open_shift', $$select public.time_end_break()$$, 'no_open_shift', 'P0001');
select tests.throws('segunda saída → no_open_shift', $$select public.time_clock_out()$$, 'no_open_shift', 'P0001');
select tests.throws('segunda saída fechando intervalo → no_open_shift', $$select public.time_clock_out(null, true)$$, 'no_open_shift', 'P0001');

select tests.note('nova entrada depois da saída');
select tests.capture('r_in2', $$select public.time_clock_in()::text$$);
select tests.set_var('s2', tests.jvar('r_in2')->>'id');
select tests.ok('nova entrada cria outra jornada', tests.var('s2') is not null and tests.var('s2') <> tests.var('s1'));
select tests.query_true('nova jornada começa depois da saída anterior',
  $$select (tests.jvar('r_in2')->>'started_at')::timestamptz >= (tests.jvar('r_out')->>'ended_at')::timestamptz$$);
select tests.admin_rows('verdade: duas jornadas, uma aberta',
  $$select 1 from public.time_shifts where user_id = tests.uid('emp')$$, 2);
select tests.admin_rows('verdade: a primeira continua encerrada com dois intervalos fechados',
  $$select 1 from public.time_breaks b join public.time_shifts s on s.id = b.shift_id
     where s.id = tests.uvar('s1') and s.ended_at is not null and b.ended_at is not null$$, 2);
select tests.lives('saída da segunda jornada', $$select public.time_clock_out()$$);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('auditoria de cada batida (lida pelo próprio dono, com RLS)');
select tests.query_is('ações da 1ª jornada na ordem de seq',
  $$select string_agg(action, ',' order by seq) from public.time_audit_events where shift_id = tests.uvar('s1')$$,
  'clock_in,break_start,break_end,break_start,break_end,clock_out');
select tests.query_true('autor e dono = o employee em todas as batidas',
  $$select bool_and(actor_id = tests.uid('emp') and subject_user_id = tests.uid('emp'))
     from public.time_audit_events where shift_id = tests.uvar('s1')$$);
select tests.query_true('batidas sem justificativa e sem request_id',
  $$select bool_and(reason is null and request_id is null) from public.time_audit_events where shift_id = tests.uvar('s1')$$);
select tests.query_true('clock_in: before nulo, after = jornada aberta',
  $$select before is null and after->>'id' = tests.var('s1') and jsonb_typeof(after->'ended_at') = 'null'
     from public.time_audit_events where shift_id = tests.uvar('s1') and action = 'clock_in'$$);
select tests.query_true('break_start: before sem intervalos, after com um aberto',
  $$select tests.jlen(before->'time_breaks') = 0 and tests.jlen(after->'time_breaks') = 1
       and jsonb_typeof(after->'time_breaks'->0->'ended_at') = 'null'
     from public.time_audit_events where shift_id = tests.uvar('s1') and action = 'break_start'
     order by seq limit 1$$);
select tests.query_true('clock_out: before aberto, after encerrado com dois intervalos',
  $$select jsonb_typeof(before->'ended_at') = 'null' and jsonb_typeof(after->'ended_at') = 'string'
       and tests.jlen(after->'time_breaks') = 2
     from public.time_audit_events where shift_id = tests.uvar('s1') and action = 'clock_out'$$);
select tests.query_true('before/after têm o formato de §3.4 sem server_now',
  $$select bool_and(tests.keys(after) = tests.k_shift() and (before is null or tests.keys(before) = tests.k_shift()))
     from public.time_audit_events where shift_id = tests.uvar('s1')$$);
select tests.query_true('created_at = clock_timestamp() (crescente com seq, depois do now() da transação)',
  $$select bool_and(created_at > now()) and count(*) = 6
          and bool_and(ok) from (
     select created_at, coalesce(created_at >= lag(created_at) over (order by seq), true) as ok
       from public.time_audit_events where shift_id = tests.uvar('s1')) q$$);
select tests.query_true('seq estritamente crescente',
  $$select bool_and(ok) from (
     select coalesce(seq > lag(seq) over (order by seq), true) as ok
       from public.time_audit_events where shift_id = tests.uvar('s1')) q$$);
select tests.query_true('id da auditoria é uuid gerado',
  $$select bool_and(id is not null) from public.time_audit_events where shift_id = tests.uvar('s1')$$);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('nota da entrada');
select tests.login('mgr');
select tests.throws('nota com 501 caracteres é rejeitada', $$select public.time_clock_in(null, repeat('x', 501))$$);
select tests.admin_rows('nota inválida não cria jornada',
  $$select 1 from public.time_shifts where user_id = tests.uid('mgr')$$, 0);
select tests.capture('r_m', $$select public.time_clock_in(null, repeat('x', 500))::text$$);
select tests.is('nota com 500 caracteres aceita', char_length(tests.jvar('r_m')->>'note'), 500);

select tests.note('manager e super_admin batem o próprio ponto normalmente');
select tests.lives('manager: intervalo', $$select public.time_start_break()$$);
select tests.lives('manager: retorno', $$select public.time_end_break()$$);
select tests.lives('manager: saída', $$select public.time_clock_out()$$);
select tests.login('sa');
select tests.lives('super_admin: entrada', $$select public.time_clock_in()$$);
select tests.capture('st_sa', $$select public.time_my_status()::text$$);
select tests.query_true('super_admin: status mostra a PRÓPRIA jornada',
  $$select (tests.jvar('st_sa')->'open_shift'->>'user_id')::uuid = tests.uid('sa')$$);
select tests.lives('super_admin: saída', $$select public.time_clock_out()$$);
select tests.admin_rows('verdade: manager e super_admin com uma jornada encerrada cada',
  $$select 1 from public.time_shifts where user_id in (tests.uid('mgr'), tests.uid('sa')) and ended_at is not null$$, 2);

select tests.done();
rollback;
