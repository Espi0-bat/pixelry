-- new_roles/01 — Ponto com os papéis novos do app (§2): partner,
-- sales_trial, employee_dev, sdr. Aceitos pelo schema integrado
-- (20261102120000); roda sempre.
-- Todos batem e corrigem o próprio ponto; nenhum vê/corrige/revisa o alheio.
begin;

select tests.create_user('partner', 'partner');
select tests.create_user('trial', 'sales_trial');
select tests.create_user('dev', 'employee_dev');
select tests.create_user('sdr', 'sdr');
select tests.create_user('emp', 'employee');
select tests.create_user('sa', 'super_admin');

select tests.login('emp');
select tests.capture('e_open', $$select public.time_clock_in()::jsonb->>'id'$$);
select tests.capture('e_closed', $$select public.time_create_manual_shift(null, tests.brt('2026-10-29 08:00'), tests.brt('2026-10-29 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')::jsonb->>'id'$$);

-- Mesmo roteiro para os quatro papéis.
select tests.note('partner');
select tests.login('partner');
select tests.query_true('partner é interno', $$select private.pt_is_internal() and not private.pt_is_super_admin()$$);
select tests.lives('partner: entrada', $$select public.time_clock_in()$$);
select tests.lives('partner: intervalo', $$select public.time_start_break()$$);
select tests.lives('partner: retorno', $$select public.time_end_break()$$);
select tests.lives('partner: saída', $$select public.time_clock_out()$$);
select tests.capture('p_m', $$select public.time_create_manual_shift(null, tests.brt('2026-10-29 08:00'), tests.brt('2026-10-29 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')::jsonb->>'id'$$);
select tests.query_is('partner corrige o próprio → pending',
  $$select public.time_correct_shift(tests.uvar('p_m'), tests.brt('2026-10-29 08:00'), tests.brt('2026-10-29 11:00'), '[]'::jsonb, 'Saí mais cedo')->>'review_status'$$, 'pending');
select tests.rows_eq('partner vê só o próprio ponto (2 jornadas)', $$select 1 from public.time_shifts$$, 2);
select tests.rows_eq('partner NÃO vê o ponto do employee', $$select 1 from public.time_shifts where user_id = tests.uid('emp')$$, 0);
select tests.rows_eq('partner NÃO vê auditorias alheias', $$select 1 from public.time_audit_events where subject_user_id <> auth.uid()$$, 0);
select tests.throws('partner corrigindo jornada alheia → shift_not_found',
  $$select public.time_correct_shift(tests.uvar('e_closed'), tests.brt('2026-10-29 08:00'), tests.brt('2026-10-29 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('partner anulando aberta alheia → shift_not_found',
  $$select public.time_void_shift(tests.uvar('e_open'), 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('partner revisando → not_allowed', $$select public.time_review_shifts('[]'::jsonb)$$, 'not_allowed', '42501');
select tests.throws('partner criando jornada para outra pessoa → not_allowed',
  $$select public.time_create_manual_shift(tests.uid('emp'), tests.brt('2026-10-30 08:00'), tests.brt('2026-10-30 12:00'), '[]'::jsonb, 'Justificativa válida')$$, 'not_allowed', '42501');

select tests.note('sales_trial');
select tests.login('trial');
select tests.query_true('sales_trial é interno', $$select private.pt_is_internal() and not private.pt_is_super_admin()$$);
select tests.lives('sales_trial: entrada', $$select public.time_clock_in()$$);
select tests.lives('sales_trial: saída', $$select public.time_clock_out()$$);
select tests.rows_eq('sales_trial vê só o próprio ponto', $$select 1 from public.time_shifts$$, 1);
select tests.throws('sales_trial corrigindo jornada alheia → shift_not_found',
  $$select public.time_correct_shift(tests.uvar('e_closed'), tests.brt('2026-10-29 08:00'), tests.brt('2026-10-29 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('sales_trial revisando → not_allowed', $$select public.time_review_shifts('[]'::jsonb)$$, 'not_allowed', '42501');

select tests.note('employee_dev');
select tests.login('dev');
select tests.query_true('employee_dev é interno', $$select private.pt_is_internal() and not private.pt_is_super_admin()$$);
select tests.lives('employee_dev: entrada', $$select public.time_clock_in()$$);
select tests.lives('employee_dev: saída fechando intervalo inexistente', $$select public.time_clock_out(null, true)$$);
select tests.rows_eq('employee_dev vê só o próprio ponto', $$select 1 from public.time_shifts$$, 1);
select tests.throws('employee_dev anulando jornada alheia → shift_not_found',
  $$select public.time_void_shift(tests.uvar('e_closed'), 'Justificativa válida')$$, 'shift_not_found', 'P0001');

select tests.note('sdr');
select tests.login('sdr');
select tests.query_true('sdr é interno', $$select private.pt_is_internal() and not private.pt_is_super_admin()$$);
select tests.query_is('pt_current_role() = sdr', $$select private.pt_current_role()$$, 'sdr');
select tests.lives('sdr: entrada', $$select public.time_clock_in()$$);
select tests.lives('sdr: intervalo', $$select public.time_start_break()$$);
select tests.lives('sdr: saída fechando o intervalo', $$select public.time_clock_out(null, true)$$);
select tests.rows_eq('sdr vê só o próprio ponto', $$select 1 from public.time_shifts$$, 1);
select tests.throws('sdr corrigindo jornada alheia → shift_not_found',
  $$select public.time_correct_shift(tests.uvar('e_closed'), tests.brt('2026-10-29 08:00'), tests.brt('2026-10-29 11:00'), '[]'::jsonb, 'Justificativa válida')$$, 'shift_not_found', 'P0001');
select tests.throws('sdr revisando → not_allowed', $$select public.time_review_shifts('[]'::jsonb)$$, 'not_allowed', '42501');

select tests.note('super_admin com os papéis novos');
select tests.login('sa');
select tests.rows_eq('super_admin vê o ponto dos quatro', $$select distinct user_id from public.time_shifts
    where user_id in (tests.uid('partner'), tests.uid('trial'), tests.uid('dev'), tests.uid('sdr'))$$, 4);
select tests.capture('sa_sdr', $$select public.time_create_manual_shift(tests.uid('sdr'), tests.brt('2026-10-30 08:00'), tests.brt('2026-10-30 12:00'), '[]'::jsonb, 'Lançado pelo administrador')::text$$);
select tests.eq('super_admin lança jornada para sdr (interno) → reviewed', tests.jvar('sa_sdr')->>'review_status', 'reviewed');
select tests.rows_eq('ponto_people do super_admin inclui os quatro papéis novos',
  $$select 1 from public.ponto_people() where role in ('partner', 'sales_trial', 'employee_dev', 'sdr')$$, 4);

select tests.done();
rollback;
