-- 12 — Cálculo de horas, intervalos e jornadas que atravessam a meia-noite
-- (§3.2): work_date gerado em America/Sao_Paulo (independe do fuso da sessão,
-- que o runner deixa em Pacific/Kiritimati de propósito) e a view
-- time_shift_totals (security_invoker, colunas estáveis, abertos medidos até
-- now()). Jornadas no passado são criadas pela RPC de jornada manual, como
-- authenticated.
begin;

select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.create_user('emp3', 'employee');

select tests.note('formato da view');
select tests.query_is('colunas da view na ordem do contrato',
  $$select string_agg(column_name::text, ',' order by ordinal_position) from information_schema.columns
     where table_schema = 'public' and table_name = 'time_shift_totals'$$,
  'shift_id,user_id,work_date,started_at,ended_at,is_open,on_break,crosses_midnight,break_seconds,worked_seconds,review_status,is_voided');
select tests.query_true('view com security_invoker = true',
  $$select 'security_invoker=true' = any (reloptions) from pg_class where oid = 'public.time_shift_totals'::regclass$$);
select tests.query_true('work_date é coluna gerada armazenada em America/Sao_Paulo',
  $$select a.attgenerated = 's' and pg_get_expr(d.adbin, d.adrelid) like '%America/Sao_Paulo%'
     from pg_attribute a join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
    where a.attrelid = 'public.time_shifts'::regclass and a.attname = 'work_date'$$);

select tests.login('emp');

select tests.note('22:00 → 02:00 em Brasília com intervalo atravessando a meia-noite');
select tests.capture('j1', $$select public.time_create_manual_shift(null,
    tests.brt('2026-10-05 22:00'), tests.brt('2026-10-06 02:00'),
    jsonb_build_array(tests.brk(tests.brt('2026-10-05 23:30'), tests.brt('2026-10-06 00:15'))),
    'Plantão de virada esquecido')::text$$);
select tests.set_var('s_j1', tests.jvar('j1')->>'id');
select tests.eq('work_date = dia em que começou (Brasília)', tests.jvar('j1')->>'work_date', '2026-10-05');
select tests.query_is('view: crosses_midnight', $$select crosses_midnight::text from public.time_shift_totals where shift_id = tests.uvar('s_j1')$$, 'true');
select tests.query_is('view: break_seconds = 45 min', $$select (break_seconds::numeric = 2700)::text from public.time_shift_totals where shift_id = tests.uvar('s_j1')$$, 'true');
select tests.query_is('view: worked_seconds = 4h − 45min = 11700', $$select (worked_seconds::numeric = 11700)::text from public.time_shift_totals where shift_id = tests.uvar('s_j1')$$, 'true');
select tests.query_is('view: is_open = false', $$select is_open::text from public.time_shift_totals where shift_id = tests.uvar('s_j1')$$, 'false');
select tests.query_is('view: on_break = false', $$select on_break::text from public.time_shift_totals where shift_id = tests.uvar('s_j1')$$, 'false');
select tests.query_is('view: is_voided = false', $$select is_voided::text from public.time_shift_totals where shift_id = tests.uvar('s_j1')$$, 'false');
select tests.query_is('view: work_date', $$select work_date::text from public.time_shift_totals where shift_id = tests.uvar('s_j1')$$, '2026-10-05');
select tests.query_is('view: review_status (manual do dono → pending)', $$select review_status from public.time_shift_totals where shift_id = tests.uvar('s_j1')$$, 'pending');
select tests.query_true('view: user_id, started_at e ended_at da jornada',
  $$select user_id = tests.uid('emp') and started_at = tests.brt('2026-10-05 22:00') and ended_at = tests.brt('2026-10-06 02:00')
     from public.time_shift_totals where shift_id = tests.uvar('s_j1')$$);

select tests.note('jornada que começa depois da meia-noite');
select tests.capture('j2', $$select public.time_create_manual_shift(null,
    tests.brt('2026-10-07 00:30'), tests.brt('2026-10-07 03:00'), '[]'::jsonb, 'Madrugada de entrega')::text$$);
select tests.eq('00:30 em Brasília → work_date do mesmo dia', tests.jvar('j2')->>'work_date', '2026-10-07');
select tests.query_is('… não atravessa a meia-noite',
  $$select crosses_midnight::text from public.time_shift_totals where shift_id = (tests.jvar('j2')->>'id')::uuid$$, 'false');
select tests.query_is('… worked_seconds = 2h30', $$select (worked_seconds::numeric = 9000)::text from public.time_shift_totals where shift_id = (tests.jvar('j2')->>'id')::uuid$$, 'true');

select tests.note('armadilha do UTC: 21:30 → 23:00 em Brasília é o dia seguinte em UTC');
select tests.capture('j3', $$select public.time_create_manual_shift(null,
    tests.brt('2026-10-11 21:30'), tests.brt('2026-10-11 23:00'), '[]'::jsonb, 'Revisão noturna do material')::text$$);
select tests.eq('work_date = data de Brasília (não a de UTC)', tests.jvar('j3')->>'work_date', '2026-10-11');
select tests.query_is('… não atravessa a meia-noite de Brasília',
  $$select crosses_midnight::text from public.time_shift_totals where shift_id = (tests.jvar('j3')->>'id')::uuid$$, 'false');

select tests.note('termina exatamente à meia-noite');
select tests.capture('j4', $$select public.time_create_manual_shift(null,
    tests.brt('2026-10-09 20:00'), tests.brt('2026-10-10 00:00'), '[]'::jsonb, 'Fechamento do mês')::text$$);
select tests.query_is('fórmula do contrato: data do fim (00:00 do dia seguinte) > work_date → true',
  $$select crosses_midnight::text from public.time_shift_totals where shift_id = (tests.jvar('j4')->>'id')::uuid$$, 'true');
select tests.eq('… work_date continua o dia do início', tests.jvar('j4')->>'work_date', '2026-10-09');

select tests.note('vários intervalos, encostados entre si e nas bordas');
select tests.capture('j5', $$select public.time_create_manual_shift(null,
    tests.brt('2026-10-12 08:00'), tests.brt('2026-10-12 17:00'),
    jsonb_build_array(
      tests.brk(tests.brt('2026-10-12 08:00'), tests.brt('2026-10-12 08:10')),
      tests.brk(tests.brt('2026-10-12 12:00'), tests.brt('2026-10-12 12:30')),
      tests.brk(tests.brt('2026-10-12 12:30'), tests.brt('2026-10-12 13:00')),
      tests.brk(tests.brt('2026-10-12 16:50'), tests.brt('2026-10-12 17:00'))),
    'Dia inteiro sem bater')::text$$);
select tests.is('intervalos que se tocam e tocam as bordas são aceitos', tests.jlen(tests.jvar('j5')->'time_breaks'), 4);
select tests.query_true('time_breaks em ordem de started_at',
  $$select bool_and(ok) from (select coalesce((b->>'started_at')::timestamptz > lag((b->>'started_at')::timestamptz) over (order by n), true) ok
     from jsonb_array_elements(tests.jvar('j5')->'time_breaks') with ordinality as e(b, n)) q$$);
select tests.query_is('break_seconds = 10+30+30+10 min = 4800',
  $$select (break_seconds::numeric = 4800)::text from public.time_shift_totals where shift_id = (tests.jvar('j5')->>'id')::uuid$$, 'true');
select tests.query_is('worked_seconds = 9h − 80min = 27600',
  $$select (worked_seconds::numeric = 27600)::text from public.time_shift_totals where shift_id = (tests.jvar('j5')->>'id')::uuid$$, 'true');

select tests.note('jornada aberta desde ontem 22:30 (medida até now())');
select tests.login('emp2');
select tests.lives('entrada', $$select public.time_clock_in()$$);
select tests.capture('o1', $$select (public.time_my_status()->'open_shift'->>'id')$$);
select tests.lives('dono corrige a entrada para ontem 22:30, com intervalo 23:00–23:30',
  $$select public.time_correct_shift(tests.uvar('o1'), tests.midnight_brt() - interval '90 minutes', null,
      jsonb_build_array(tests.brk(tests.midnight_brt() - interval '60 minutes', tests.midnight_brt() - interval '30 minutes')),
      'Entrada real foi ontem à noite')$$);
select tests.query_is('work_date = ontem (Brasília)',
  $$select work_date::text from public.time_shift_totals where shift_id = tests.uvar('o1')$$, (tests.today_brt() - 1)::text);
select tests.query_is('aberta: is_open', $$select is_open::text from public.time_shift_totals where shift_id = tests.uvar('o1')$$, 'true');
select tests.query_is('aberta desde ontem: crosses_midnight', $$select crosses_midnight::text from public.time_shift_totals where shift_id = tests.uvar('o1')$$, 'true');
select tests.query_is('aberta: ended_at nulo na view', $$select (ended_at is null)::text from public.time_shift_totals where shift_id = tests.uvar('o1')$$, 'true');
select tests.query_is('aberta: break_seconds = 1800', $$select (break_seconds::numeric = 1800)::text from public.time_shift_totals where shift_id = tests.uvar('o1')$$, 'true');
select tests.query_true('aberta: worked_seconds = floor(now() − início) − intervalos',
  $$select worked_seconds::numeric = floor(extract(epoch from now() - (tests.midnight_brt() - interval '90 minutes'))) - 1800
     from public.time_shift_totals where shift_id = tests.uvar('o1')$$);
select tests.query_is('aberta fora do intervalo: on_break = false', $$select on_break::text from public.time_shift_totals where shift_id = tests.uvar('o1')$$, 'false');
select tests.query_is('status: a jornada de ontem aparece como aberta',
  $$select public.time_my_status()->'open_shift'->>'id'$$, tests.var('o1'));

select tests.note('jornada aberta em intervalo');
select tests.login('emp3');
select tests.lives('entrada', $$select public.time_clock_in()$$);
select tests.capture('o3', $$select (public.time_my_status()->'open_shift'->>'id')$$);
select tests.lives('correção: começou há 2h, intervalo aberto há 1h',
  $$select public.time_correct_shift(tests.uvar('o3'), now() - interval '2 hours', null,
      jsonb_build_array(tests.brk(now() - interval '1 hour', null)), 'Esqueci de registrar a pausa')$$);
select tests.query_is('em intervalo: on_break = true', $$select on_break::text from public.time_shift_totals where shift_id = tests.uvar('o3')$$, 'true');
select tests.query_is('intervalo aberto medido até now(): 3600', $$select (break_seconds::numeric = 3600)::text from public.time_shift_totals where shift_id = tests.uvar('o3')$$, 'true');
select tests.query_is('worked_seconds = 7200 − 3600', $$select (worked_seconds::numeric = 3600)::text from public.time_shift_totals where shift_id = tests.uvar('o3')$$, 'true');
select tests.lives('saída fechando o intervalo', $$select public.time_clock_out(null, true)$$);
select tests.query_is('depois da saída: on_break = false', $$select on_break::text from public.time_shift_totals where shift_id = tests.uvar('o3')$$, 'false');
select tests.query_is('depois da saída: is_open = false', $$select is_open::text from public.time_shift_totals where shift_id = tests.uvar('o3')$$, 'false');

select tests.note('jornada recém-aberta: nunca negativa');
select tests.lives('nova entrada', $$select public.time_clock_in()$$);
select tests.query_true('worked_seconds >= 0 (greatest(0, …))',
  $$select bool_and(worked_seconds >= 0) from public.time_shift_totals where user_id = tests.uid('emp3')$$);

select tests.note('anulada');
select tests.login('emp');
select tests.lives('anular a jornada de 2026-10-11', $$select public.time_void_shift((tests.jvar('j3')->>'id')::uuid, 'Registrei no dia errado')$$);
select tests.query_is('view: is_voided = true', $$select is_voided::text from public.time_shift_totals where shift_id = (tests.jvar('j3')->>'id')::uuid$$, 'true');
select tests.rows_eq('view: uma linha por jornada do dono (5)', $$select 1 from public.time_shift_totals where user_id = tests.uid('emp')$$, 5);

select tests.done();
rollback;
