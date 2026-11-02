-- 16 — Oráculo fechado (§3.3 passo 3): quem não é dono nem super_admin recebe
-- SEMPRE shift_not_found ao corrigir/anular jornada alheia — aberta,
-- encerrada, revisada, anulada ou inexistente — e antes de qualquer outra
-- validação (justificativa, intervalos). Client/desconhecido recebem
-- not_allowed antes de qualquer leitura; JWT sem sub, not_authenticated.
begin;

select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.create_user('mgr', 'manager');
select tests.create_user('sa', 'super_admin');
select tests.create_user('cli', 'client');
select tests.create_user('ghost', null);

select tests.login('emp');
select tests.capture('ec', $$select public.time_create_manual_shift(null, tests.brt('2026-10-22 08:00'), tests.brt('2026-10-22 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')::jsonb->>'id'$$);
select tests.capture('ev', $$select public.time_create_manual_shift(null, tests.brt('2026-10-23 08:00'), tests.brt('2026-10-23 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')::jsonb->>'id'$$);
select tests.step('anula ev', $$select public.time_void_shift(tests.uvar('ev'), 'Lancei no dia errado')$$);
select tests.step('entrada (eo aberta)', $$select public.time_clock_in()$$);
select tests.capture('eo', $$select public.time_my_status()->'open_shift'->>'id'$$);
select tests.login('sa');
select tests.capture('er', $$select public.time_create_manual_shift(tests.uid('emp'), tests.brt('2026-10-24 08:00'), tests.brt('2026-10-24 12:00'), '[]'::jsonb, 'Lançado pelo administrador')::jsonb->>'id'$$);
select tests.logout();
select tests.admin_capture('audit_before', $$select count(*)::text from public.time_audit_events where subject_user_id = tests.uid('emp')$$);
select tests.admin_capture('shifts_before', $$select md5(string_agg(s::text, '|' order by s.id)) from public.time_shifts s where s.user_id = tests.uid('emp')$$);

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('manager em jornada alheia → sempre shift_not_found');
select tests.login('mgr');
select tests.throws('corrigir ABERTA alheia → shift_not_found',
  $$select public.time_correct_shift(tests.uvar('eo'), now() - interval '1 hour', null, '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('corrigir ENCERRADA alheia → shift_not_found',
  $$select public.time_correct_shift(tests.uvar('ec'), tests.brt('2026-10-22 08:00'), tests.brt('2026-10-22 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('corrigir REVISADA alheia → shift_not_found (não shift_locked)',
  $$select public.time_correct_shift(tests.uvar('er'), tests.brt('2026-10-24 08:00'), tests.brt('2026-10-24 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('corrigir ANULADA alheia → shift_not_found (não shift_voided)',
  $$select public.time_correct_shift(tests.uvar('ev'), tests.brt('2026-10-23 08:00'), tests.brt('2026-10-23 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('corrigir INEXISTENTE → shift_not_found',
  $$select public.time_correct_shift(gen_random_uuid(), tests.brt('2026-10-23 08:00'), tests.brt('2026-10-23 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('alheia com justificativa inválida → shift_not_found (não invalid_reason)',
  $$select public.time_correct_shift(tests.uvar('ec'), tests.brt('2026-10-22 08:00'), tests.brt('2026-10-22 11:00'), '[]'::jsonb, null)$$, 'shift_not_found', 'P0001');
select tests.throws('alheia encerrada com p_ended_at nulo → shift_not_found (não cannot_reopen)',
  $$select public.time_correct_shift(tests.uvar('ec'), tests.brt('2026-10-22 08:00'), null, '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('alheia com intervalos malformados → shift_not_found (não invalid_breaks)',
  $$select public.time_correct_shift(tests.uvar('ec'), tests.brt('2026-10-22 08:00'), tests.brt('2026-10-22 11:00'), '{}'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('alheia com horário no futuro → shift_not_found (não future_timestamp)',
  $$select public.time_correct_shift(tests.uvar('ec'), tests.brt('2026-10-22 08:00'), clock_timestamp() + interval '1 day', '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('anular ABERTA alheia → shift_not_found',
  $$select public.time_void_shift(tests.uvar('eo'), 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('anular ENCERRADA alheia → shift_not_found',
  $$select public.time_void_shift(tests.uvar('ec'), 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('anular REVISADA alheia → shift_not_found',
  $$select public.time_void_shift(tests.uvar('er'), 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('anular ANULADA alheia → shift_not_found',
  $$select public.time_void_shift(tests.uvar('ev'), 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('anular alheia com justificativa curta → shift_not_found',
  $$select public.time_void_shift(tests.uvar('ec'), 'x')$$, 'shift_not_found', 'P0001');
select tests.throws('anular INEXISTENTE → shift_not_found',
  $$select public.time_void_shift(gen_random_uuid(), 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('com p_request_id: alheia → shift_not_found (checagem de dono vem antes da idempotência)',
  $$select public.time_void_shift(tests.uvar('ec'), 'Justificativa válida', gen_random_uuid())$$, 'shift_not_found', 'P0001');
select tests.throws('manager criando jornada para outra pessoa → not_allowed',
  $$select public.time_create_manual_shift(tests.uid('emp'), tests.brt('2026-10-25 08:00'), tests.brt('2026-10-25 12:00'), '[]'::jsonb, 'Justificativa válida')$$, 'not_allowed', '42501');
select tests.throws('manager revisando → not_allowed',
  $$select public.time_review_shifts(jsonb_build_array(jsonb_build_object('id', tests.uvar('ec'), 'updated_at', now())))$$, 'not_allowed', '42501');

select tests.note('outro employee, mesmo resultado');
select tests.login('emp2');
select tests.throws('employee corrigindo aberta alheia → shift_not_found',
  $$select public.time_correct_shift(tests.uvar('eo'), now() - interval '1 hour', null, '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('employee corrigindo revisada alheia → shift_not_found',
  $$select public.time_correct_shift(tests.uvar('er'), tests.brt('2026-10-24 08:00'), tests.brt('2026-10-24 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('employee anulando anulada alheia → shift_not_found',
  $$select public.time_void_shift(tests.uvar('ev'), 'Justificativa válida')$$, 'shift_not_found', 'P0001');

select tests.note('o dono recebe o erro de estado real (contraste)');
select tests.login('emp');
select tests.throws('dono: revisada → shift_locked',
  $$select public.time_correct_shift(tests.uvar('er'), tests.brt('2026-10-24 08:00'), tests.brt('2026-10-24 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'shift_locked', 'P0001');
select tests.throws('dono: anulada → shift_voided',
  $$select public.time_correct_shift(tests.uvar('ev'), tests.brt('2026-10-23 08:00'), tests.brt('2026-10-23 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'shift_voided', 'P0001');

select tests.note('client, desconhecido e JWT sem sub: barrados antes de ler a jornada');
select tests.login('cli');
select tests.throws('client: time_my_status → not_allowed', $$select public.time_my_status()$$, 'not_allowed', '42501');
select tests.throws('client: entrada → not_allowed', $$select public.time_clock_in()$$, 'not_allowed', '42501');
select tests.throws('client: intervalo → not_allowed', $$select public.time_start_break()$$, 'not_allowed', '42501');
select tests.throws('client: retorno → not_allowed', $$select public.time_end_break()$$, 'not_allowed', '42501');
select tests.throws('client: saída → not_allowed', $$select public.time_clock_out()$$, 'not_allowed', '42501');
select tests.throws('client: corrigir jornada existente → not_allowed',
  $$select public.time_correct_shift(tests.uvar('ec'), tests.brt('2026-10-22 08:00'), tests.brt('2026-10-22 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'not_allowed', '42501');
select tests.throws('client: corrigir inexistente → not_allowed (mesmo erro)',
  $$select public.time_correct_shift(gen_random_uuid(), tests.brt('2026-10-22 08:00'), tests.brt('2026-10-22 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'not_allowed', '42501');
select tests.throws('client: anular → not_allowed', $$select public.time_void_shift(tests.uvar('ec'), 'Justificativa válida')$$, 'not_allowed', '42501');
select tests.throws('client: jornada manual → not_allowed',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-25 08:00'), tests.brt('2026-10-25 12:00'), '[]'::jsonb, 'Justificativa válida')$$, 'not_allowed', '42501');
select tests.login('ghost');
select tests.throws('sem perfil: time_my_status → not_allowed', $$select public.time_my_status()$$, 'not_allowed', '42501');
select tests.throws('sem perfil: entrada → not_allowed', $$select public.time_clock_in()$$, 'not_allowed', '42501');
select tests.throws('sem perfil: corrigir → not_allowed',
  $$select public.time_correct_shift(tests.uvar('ec'), tests.brt('2026-10-22 08:00'), tests.brt('2026-10-22 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'not_allowed', '42501');
select tests.throws('sem perfil: anular → not_allowed', $$select public.time_void_shift(tests.uvar('ec'), 'Justificativa válida')$$, 'not_allowed', '42501');
select tests.throws('sem perfil: jornada manual → not_allowed',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-25 08:00'), tests.brt('2026-10-25 12:00'), '[]'::jsonb, 'Justificativa válida')$$, 'not_allowed', '42501');
select tests.login_without_sub();
select tests.throws('sem sub: time_my_status → not_authenticated', $$select public.time_my_status()$$, 'not_authenticated', '42501');
select tests.throws('sem sub: entrada → not_authenticated', $$select public.time_clock_in()$$, 'not_authenticated', '42501');
select tests.throws('sem sub: intervalo → not_authenticated', $$select public.time_start_break()$$, 'not_authenticated', '42501');
select tests.throws('sem sub: retorno → not_authenticated', $$select public.time_end_break()$$, 'not_authenticated', '42501');
select tests.throws('sem sub: saída → not_authenticated', $$select public.time_clock_out()$$, 'not_authenticated', '42501');
select tests.throws('sem sub: corrigir → not_authenticated',
  $$select public.time_correct_shift(tests.uvar('ec'), tests.brt('2026-10-22 08:00'), tests.brt('2026-10-22 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'not_authenticated', '42501');
select tests.throws('sem sub: anular → not_authenticated', $$select public.time_void_shift(tests.uvar('ec'), 'Justificativa válida')$$, 'not_authenticated', '42501');
select tests.throws('sem sub: jornada manual → not_authenticated',
  $$select public.time_create_manual_shift(null, tests.brt('2026-10-25 08:00'), tests.brt('2026-10-25 12:00'), '[]'::jsonb, 'Justificativa válida')$$, 'not_authenticated', '42501');

select tests.logout();
select tests.admin_query_is('nada mudou nas jornadas do employee', $$select md5(string_agg(s::text, '|' order by s.id)) from public.time_shifts s where s.user_id = tests.uid('emp')$$, tests.var('shifts_before'));
select tests.admin_query_is('nenhuma auditoria nova sobre o employee', $$select count(*)::text from public.time_audit_events where subject_user_id = tests.uid('emp')$$, tests.var('audit_before'));
select tests.admin_rows('nenhuma jornada criada para client/desconhecido',
  $$select 1 from public.time_shifts where user_id in (tests.uid('cli'), tests.uid('ghost'))$$, 0);

select tests.done();
rollback;
