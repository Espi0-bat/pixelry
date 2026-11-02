-- 20 — RLS e escrita direta nas tabelas de ponto (§2, §3.2): cada papel vê
-- exatamente o que pode (manager NÃO vê o ponto alheio; super_admin vê tudo;
-- client/desconhecido/sem sub veem nada; anon nem tem SELECT) e ninguém
-- escreve direto nas tabelas — toda escrita passa pelas RPCs.
begin;

select tests.create_user('sa', 'super_admin');
select tests.create_user('mgr', 'manager');
select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.create_user('cli', 'client');
select tests.create_user('ghost', null);

-- Estado: sa 1 jornada/1 intervalo; mgr 1/1; emp 2/2 (uma aberta em intervalo);
-- emp2 2/0 (uma criada pelo super_admin). Auditorias: sa 1, mgr 1, emp 3, emp2 2.
select tests.login('sa');
select tests.step('sa: jornada manual', $$select public.time_create_manual_shift(null, tests.brt('2026-10-26 08:00'), tests.brt('2026-10-26 12:00'),
    jsonb_build_array(tests.brk(tests.brt('2026-10-26 10:00'), tests.brt('2026-10-26 10:15'))), 'Lançando o meu dia')$$);
select tests.login('mgr');
select tests.step('mgr: jornada manual', $$select public.time_create_manual_shift(null, tests.brt('2026-10-26 08:00'), tests.brt('2026-10-26 12:00'),
    jsonb_build_array(tests.brk(tests.brt('2026-10-26 10:00'), tests.brt('2026-10-26 10:15'))), 'Esqueci de bater o ponto')$$);
select tests.capture('mg', $$select id::text from public.time_shifts where user_id = auth.uid()$$);
select tests.login('emp');
select tests.capture('e1', $$select public.time_create_manual_shift(null, tests.brt('2026-10-26 08:00'), tests.brt('2026-10-26 12:00'),
    jsonb_build_array(tests.brk(tests.brt('2026-10-26 10:00'), tests.brt('2026-10-26 10:15'))), 'Esqueci de bater o ponto')::jsonb->>'id'$$);
select tests.step('emp: entrada', $$select public.time_clock_in()$$);
select tests.step('emp: intervalo', $$select public.time_start_break()$$);
select tests.capture('eo', $$select public.time_my_status()->'open_shift'->>'id'$$);
select tests.login('emp2');
select tests.step('emp2: jornada manual', $$select public.time_create_manual_shift(null, tests.brt('2026-10-26 08:00'), tests.brt('2026-10-26 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')$$);
select tests.login('sa');
select tests.step('sa: jornada para emp2', $$select public.time_create_manual_shift(tests.uid('emp2'), tests.brt('2026-10-27 08:00'), tests.brt('2026-10-27 12:00'), '[]'::jsonb, 'Lançado pelo administrador')$$);
select tests.logout();
select tests.admin_rows('verdade: 6 jornadas', $$select 1 from public.time_shifts$$, 6);
select tests.admin_rows('verdade: 4 intervalos', $$select 1 from public.time_breaks$$, 4);
select tests.admin_rows('verdade: 7 auditorias', $$select 1 from public.time_audit_events$$, 7);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('employee: só o próprio ponto');
select tests.login('emp');
select tests.rows_eq('jornadas visíveis = 2 (as próprias)', $$select 1 from public.time_shifts$$, 2);
select tests.rows_eq('nenhuma jornada alheia', $$select 1 from public.time_shifts where user_id <> auth.uid()$$, 0);
select tests.rows_eq('intervalos visíveis = 2', $$select 1 from public.time_breaks$$, 2);
select tests.rows_eq('nenhum intervalo alheio', $$select 1 from public.time_breaks where user_id <> auth.uid()$$, 0);
select tests.rows_eq('auditorias visíveis = 3', $$select 1 from public.time_audit_events$$, 3);
select tests.rows_eq('view de totais: 2', $$select 1 from public.time_shift_totals$$, 2);
select tests.rows_eq('jornada do manager pelo id: 0', $$select 1 from public.time_shifts where id = tests.uvar('mg')$$, 0);

select tests.note('employee que teve jornada lançada pelo super_admin vê a auditoria dela');
select tests.login('emp2');
select tests.rows_eq('jornadas visíveis = 2', $$select 1 from public.time_shifts$$, 2);
select tests.rows_eq('auditorias visíveis = 2 (inclui a do super_admin sobre mim)', $$select 1 from public.time_audit_events$$, 2);
select tests.rows_eq('… com autor super_admin', $$select 1 from public.time_audit_events where actor_id = tests.uid('sa')$$, 1);

select tests.note('manager: NÃO vê o ponto de ninguém além do próprio');
select tests.login('mgr');
select tests.rows_eq('jornadas visíveis = 1', $$select 1 from public.time_shifts$$, 1);
select tests.rows_eq('nenhuma jornada alheia', $$select 1 from public.time_shifts where user_id <> auth.uid()$$, 0);
select tests.rows_eq('jornada aberta do employee pelo id: 0', $$select 1 from public.time_shifts where id = tests.uvar('eo')$$, 0);
select tests.rows_eq('intervalos visíveis = 1', $$select 1 from public.time_breaks$$, 1);
select tests.rows_eq('intervalos da jornada do employee: 0', $$select 1 from public.time_breaks where shift_id = tests.uvar('e1')$$, 0);
select tests.rows_eq('auditorias visíveis = 1', $$select 1 from public.time_audit_events$$, 1);
select tests.rows_eq('view de totais: 1', $$select 1 from public.time_shift_totals$$, 1);
select tests.rows_eq('view: nenhum total alheio', $$select 1 from public.time_shift_totals where user_id <> auth.uid()$$, 0);
select tests.query_is('status do manager não mostra o ponto alheio', $$select jsonb_typeof(public.time_my_status()->'open_shift')$$, 'null');

select tests.note('super_admin: vê o ponto de todos');
select tests.login('sa');
select tests.rows_eq('jornadas visíveis = 6', $$select 1 from public.time_shifts$$, 6);
select tests.rows_eq('intervalos visíveis = 4', $$select 1 from public.time_breaks$$, 4);
select tests.rows_eq('auditorias visíveis = 7', $$select 1 from public.time_audit_events$$, 7);
select tests.rows_eq('view de totais: 6', $$select 1 from public.time_shift_totals$$, 6);
select tests.rows_eq('jornada aberta do employee pelo id: 1', $$select 1 from public.time_shifts where id = tests.uvar('eo')$$, 1);
select tests.rows_eq('filtro por pessoa (visão da equipe)', $$select 1 from public.time_shifts where user_id = tests.uid('emp')$$, 2);

select tests.note('client, desconhecido e JWT sem sub: nada');
select tests.login('cli');
select tests.rows_eq('client: jornadas 0', $$select 1 from public.time_shifts$$, 0);
select tests.rows_eq('client: intervalos 0', $$select 1 from public.time_breaks$$, 0);
select tests.rows_eq('client: auditorias 0', $$select 1 from public.time_audit_events$$, 0);
select tests.rows_eq('client: totais 0', $$select 1 from public.time_shift_totals$$, 0);
select tests.login('ghost');
select tests.rows_eq('desconhecido: jornadas 0', $$select 1 from public.time_shifts$$, 0);
select tests.rows_eq('desconhecido: intervalos 0', $$select 1 from public.time_breaks$$, 0);
select tests.rows_eq('desconhecido: auditorias 0', $$select 1 from public.time_audit_events$$, 0);
select tests.rows_eq('desconhecido: totais 0', $$select 1 from public.time_shift_totals$$, 0);
select tests.login_without_sub();
select tests.rows_eq('sem sub: jornadas 0', $$select 1 from public.time_shifts$$, 0);
select tests.rows_eq('sem sub: auditorias 0', $$select 1 from public.time_audit_events$$, 0);

select tests.note('anon: sem SELECT nem EXECUTE');
select tests.login_anon();
select tests.denied('anon: SELECT time_shifts', $$select 1 from public.time_shifts$$);
select tests.denied('anon: SELECT time_breaks', $$select 1 from public.time_breaks$$);
select tests.denied('anon: SELECT time_audit_events', $$select 1 from public.time_audit_events$$);
select tests.denied('anon: SELECT time_shift_totals', $$select 1 from public.time_shift_totals$$);
select tests.denied('anon: time_my_status', $$select public.time_my_status()$$);
select tests.denied('anon: time_clock_in', $$select public.time_clock_in()$$);
select tests.denied('anon: time_start_break', $$select public.time_start_break()$$);
select tests.denied('anon: time_end_break', $$select public.time_end_break()$$);
select tests.denied('anon: time_clock_out', $$select public.time_clock_out()$$);
select tests.denied('anon: time_correct_shift',
  $$select public.time_correct_shift(gen_random_uuid(), now() - interval '2 hours', now() - interval '1 hour', '[]'::jsonb, 'Justificativa válida')$$);
select tests.denied('anon: time_create_manual_shift',
  $$select public.time_create_manual_shift(null, now() - interval '2 hours', now() - interval '1 hour', '[]'::jsonb, 'Justificativa válida')$$);
select tests.denied('anon: time_void_shift', $$select public.time_void_shift(gen_random_uuid(), 'Justificativa válida')$$);
select tests.denied('anon: time_review_shifts', $$select public.time_review_shifts('[]'::jsonb)$$);
select tests.denied('anon: ponto_people', $$select * from public.ponto_people()$$);
select tests.denied('anon: setval na sequência de time_audit_events.seq',
  $$select setval(pg_get_serial_sequence('public.time_audit_events', 'seq'), 1)$$);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('nenhuma escrita direta nas tabelas de ponto (employee nas próprias linhas)');
select tests.login('emp');
select tests.denied('INSERT time_shifts',
  $$insert into public.time_shifts (user_id, started_at, ended_at) values (auth.uid(), now() - interval '50 hours', now() - interval '49 hours')$$);
select tests.denied('UPDATE time_shifts (fechar a própria jornada)', $$update public.time_shifts set ended_at = now() where id = tests.uvar('eo')$$);
select tests.denied('UPDATE time_shifts (marcar revisada)', $$update public.time_shifts set review_status = 'reviewed' where user_id = auth.uid()$$);
select tests.denied('DELETE time_shifts', $$delete from public.time_shifts where user_id = auth.uid()$$);
select tests.denied('TRUNCATE time_shifts', $$truncate public.time_shifts cascade$$);
select tests.denied('INSERT time_breaks',
  $$insert into public.time_breaks (shift_id, user_id, started_at) values (tests.uvar('e1'), auth.uid(), tests.brt('2026-10-26 11:00'))$$);
select tests.denied('UPDATE time_breaks', $$update public.time_breaks set ended_at = now() where user_id = auth.uid()$$);
select tests.denied('DELETE time_breaks', $$delete from public.time_breaks where user_id = auth.uid()$$);
select tests.denied('INSERT time_audit_events',
  $$insert into public.time_audit_events (subject_user_id, actor_id, action) values (auth.uid(), auth.uid(), 'clock_in')$$);
select tests.denied('UPDATE time_audit_events', $$update public.time_audit_events set reason = 'apagando rastros' where actor_id = auth.uid()$$);
select tests.denied('DELETE time_audit_events', $$delete from public.time_audit_events where actor_id = auth.uid()$$);
select tests.throws('INSERT na view de totais', $$insert into public.time_shift_totals (shift_id) values (gen_random_uuid())$$, null, null);
-- As colunas seq são identity (§3.2): a sequência delas não pode ser mexida
-- pela API (setval quebraria a ordem e o índice único das auditorias).
select tests.denied('setval na sequência de time_audit_events.seq → sem privilégio',
  $$select setval(pg_get_serial_sequence('public.time_audit_events', 'seq'), 1)$$);
select tests.denied('nextval na sequência de work_task_events.seq → sem privilégio',
  $$select nextval(pg_get_serial_sequence('public.work_task_events', 'seq'))$$);
-- §3.4: time_shift_json é revogada de authenticated (só as RPCs a usam).
select tests.denied('private.time_shift_json direto → sem EXECUTE',
  $$select private.time_shift_json(tests.uvar('e1'))$$);

select tests.note('nem o super_admin escreve direto');
select tests.login('sa');
select tests.denied('super_admin: INSERT time_shifts',
  $$insert into public.time_shifts (user_id, started_at, ended_at) values (tests.uid('emp'), now() - interval '50 hours', now() - interval '49 hours')$$);
select tests.denied('super_admin: UPDATE time_shifts', $$update public.time_shifts set review_status = 'reviewed' where user_id = tests.uid('emp')$$);
select tests.denied('super_admin: DELETE time_shifts', $$delete from public.time_shifts where user_id = tests.uid('emp')$$);
select tests.denied('super_admin: DELETE time_audit_events', $$delete from public.time_audit_events$$);
select tests.denied('super_admin: UPDATE time_breaks', $$update public.time_breaks set ended_at = now()$$);

select tests.logout();
select tests.admin_rows('verdade: continuam 6 jornadas, 4 intervalos e 7 auditorias',
  $$select 1 from public.time_shifts having count(*) = 6
     and (select count(*) from public.time_breaks) = 4 and (select count(*) from public.time_audit_events) = 7$$, 1);

select tests.done();
rollback;
