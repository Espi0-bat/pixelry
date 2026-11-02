-- 15 — Revisão (time_review_shifts, §3.3): só super_admin; null/vazio → 0;
-- shift_not_found / shift_changed / shift_open; já revisada é ignorada; ids
-- repetidos contam uma vez; tudo ou nada; anuladas pendentes podem ser
-- revisadas; auditoria review por jornada alterada; trava do dono depois.
begin;

select tests.create_user('emp', 'employee');
select tests.create_user('mgr', 'manager');
select tests.create_user('sa', 'super_admin');
select tests.create_user('cli', 'client');
select tests.create_user('ghost', null);

select tests.login('emp');
select tests.capture('p1', $$select public.time_create_manual_shift(null, tests.brt('2026-10-19 08:00'), tests.brt('2026-10-19 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')::jsonb->>'id'$$);
select tests.capture('p2', $$select public.time_create_manual_shift(null, tests.brt('2026-10-20 08:00'), tests.brt('2026-10-20 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')::jsonb->>'id'$$);
select tests.capture('v1', $$select public.time_create_manual_shift(null, tests.brt('2026-10-21 08:00'), tests.brt('2026-10-21 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')::jsonb->>'id'$$);
select tests.step('anula v1 (fica pendente)', $$select public.time_void_shift(tests.uvar('v1'), 'Lancei no dia errado')$$);
select tests.step('jornada do relógio n1: entrada', $$select public.time_clock_in()$$);
select tests.capture('n1', $$select public.time_clock_out()::jsonb->>'id'$$);
select tests.step('jornada aberta o1', $$select public.time_clock_in()$$);
select tests.capture('o1', $$select public.time_my_status()->'open_shift'->>'id'$$);
select tests.login('mgr');
select tests.capture('mg', $$select public.time_create_manual_shift(null, tests.brt('2026-10-19 08:00'), tests.brt('2026-10-19 12:00'), '[]'::jsonb, 'Esqueci de bater o ponto')::jsonb->>'id'$$);

-- Corpo de p_shifts a partir do estado atual (lido pelo super_admin).
-- tests.var('xxx') guarda o JSON pronto para cada caso.

select tests.note('só super_admin revisa');
select tests.throws('manager revisando a PRÓPRIA jornada → not_allowed',
  $$select public.time_review_shifts(jsonb_build_array(jsonb_build_object('id', tests.uvar('mg'), 'updated_at', now())))$$, 'not_allowed', '42501');
select tests.throws('manager com lista vazia → not_allowed (checa papel antes de tudo)',
  $$select public.time_review_shifts('[]'::jsonb)$$, 'not_allowed', '42501');
select tests.throws('manager com null → not_allowed', $$select public.time_review_shifts(null)$$, 'not_allowed', '42501');
select tests.throws('manager revisando jornada alheia → not_allowed',
  $$select public.time_review_shifts(jsonb_build_array(jsonb_build_object('id', tests.uvar('p1'), 'updated_at', now())))$$, 'not_allowed', '42501');
select tests.login('emp');
select tests.throws('employee → not_allowed', $$select public.time_review_shifts('[]'::jsonb)$$, 'not_allowed', '42501');
select tests.login('cli');
select tests.throws('client → not_allowed', $$select public.time_review_shifts('[]'::jsonb)$$, 'not_allowed', '42501');
select tests.login('ghost');
select tests.throws('sem perfil → not_allowed', $$select public.time_review_shifts('[]'::jsonb)$$, 'not_allowed', '42501');
select tests.login_without_sub();
select tests.throws('JWT sem sub → not_authenticated', $$select public.time_review_shifts('[]'::jsonb)$$, 'not_authenticated', '42501');
select tests.login_anon();
select tests.denied('anon sem EXECUTE', $$select public.time_review_shifts('[]'::jsonb)$$);
select tests.admin_rows('nenhuma revisão feita por quem não pode',
  $$select 1 from public.time_shifts where review_status = 'reviewed'$$, 0);

select tests.note('super_admin');
select tests.login('sa');
select tests.query_is('null → 0', $$select public.time_review_shifts(null)::text$$, '0');
select tests.query_is('lista vazia → 0', $$select public.time_review_shifts('[]'::jsonb)::text$$, '0');
select tests.query_is('null em JSON → 0', $$select public.time_review_shifts('null'::jsonb)::text$$, '0');
-- p_shifts malformado: o contrato não fixa o código, mas a leitura
-- conservadora (§0) é rejeitar — nunca devolver 0 como se não houvesse o que
-- revisar, nem revisar sem a trava otimista do updated_at.
select tests.throws('p_shifts objeto (não lista) → rejeitado',
  $$select public.time_review_shifts((select jsonb_build_object('id', s.id, 'updated_at', s.updated_at) from public.time_shifts s where s.id = tests.uvar('p1')))$$);
select tests.throws('elemento que não é objeto → rejeitado', $$select public.time_review_shifts('[1]'::jsonb)$$);
select tests.throws('elemento sem updated_at → rejeitado (sem trava otimista não revisa)',
  $$select public.time_review_shifts(jsonb_build_array(jsonb_build_object('id', tests.uvar('p1'))))$$);
select tests.throws('updated_at nulo → rejeitado',
  $$select public.time_review_shifts(jsonb_build_array(jsonb_build_object('id', tests.uvar('p1'), 'updated_at', null)))$$);
select tests.throws('id que não é uuid → rejeitado',
  $$select public.time_review_shifts('[{"id": "abc", "updated_at": "2026-10-19T12:00:00Z"}]'::jsonb)$$);
select tests.throws('updated_at que não é horário → rejeitado',
  $$select public.time_review_shifts(jsonb_build_array(jsonb_build_object('id', tests.uvar('p1'), 'updated_at', 'ontem')))$$);
select tests.admin_rows('nenhuma lista malformada revisou nada nem gerou auditoria',
  $$select 1 from public.time_shifts where review_status = 'reviewed'
    union all select 1 from public.time_audit_events where action = 'review'$$, 0);
select tests.query_is('retorno é integer',
  $$select pg_get_function_result('public.time_review_shifts(jsonb, text)'::regprocedure)$$, 'integer');
select tests.capture('body_p1', $$select jsonb_build_array(jsonb_build_object('id', s.id, 'updated_at', s.updated_at))::text
    from public.time_shifts s where s.id = tests.uvar('p1')$$);
select tests.query_is('revisa uma pendente → 1', $$select public.time_review_shifts(tests.jvar('body_p1'), 'Conferido com a agenda')::text$$, '1');
select tests.admin_query_is('p1 reviewed, reviewed_by = super_admin, reviewed_at = instante da chamada',
  $$select (review_status = 'reviewed' and reviewed_by = tests.uid('sa') and reviewed_at between now() and clock_timestamp())::text
     from public.time_shifts where id = tests.uvar('p1')$$, 'true');
select tests.query_true('auditoria review: autor super_admin, dono emp, nota, before pending → after reviewed',
  $$select count(*) = 1 and bool_and(actor_id = tests.uid('sa') and subject_user_id = tests.uid('emp') and reason = 'Conferido com a agenda'
                                      and before->>'review_status' = 'pending' and after->>'review_status' = 'reviewed'
                                      and (after->>'reviewed_by')::uuid = tests.uid('sa'))
     from public.time_audit_events where shift_id = tests.uvar('p1') and action = 'review'$$);
select tests.capture('body_p1b', $$select jsonb_build_array(jsonb_build_object('id', s.id, 'updated_at', s.updated_at))::text
    from public.time_shifts s where s.id = tests.uvar('p1')$$);
select tests.query_is('já revisada (updated_at atual) → ignorada, retorna 0', $$select public.time_review_shifts(tests.jvar('body_p1b'))::text$$, '0');
select tests.admin_rows('… sem nova auditoria', $$select 1 from public.time_audit_events where shift_id = tests.uvar('p1') and action = 'review'$$, 1);

select tests.throws('updated_at diferente do enviado → shift_changed',
  $$select public.time_review_shifts(jsonb_build_array(jsonb_build_object('id', tests.uvar('p2'), 'updated_at', '2000-01-01T00:00:00Z')))$$,
  'shift_changed', 'P0001');
select tests.throws('uma válida + uma desatualizada → shift_changed (tudo ou nada)',
  $$select public.time_review_shifts(
      (select jsonb_agg(x) from (
         select jsonb_build_object('id', s.id, 'updated_at', s.updated_at) x from public.time_shifts s where s.id = tests.uvar('p2')
         union all select jsonb_build_object('id', tests.uvar('n1'), 'updated_at', '2000-01-01T00:00:00Z')) q))$$,
  'shift_changed', 'P0001');
select tests.admin_query_is('… p2 continua pending', $$select review_status from public.time_shifts where id = tests.uvar('p2')$$, 'pending');
select tests.throws('jornada aberta → shift_open',
  $$select public.time_review_shifts((select jsonb_build_array(jsonb_build_object('id', s.id, 'updated_at', s.updated_at))
      from public.time_shifts s where s.id = tests.uvar('o1')))$$,
  'shift_open', 'P0001');
select tests.throws('id inexistente → shift_not_found',
  $$select public.time_review_shifts(jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'updated_at', now())))$$,
  'shift_not_found', 'P0001');
select tests.query_is('id repetido conta uma vez → 1',
  $$select public.time_review_shifts((select jsonb_build_array(
      jsonb_build_object('id', s.id, 'updated_at', s.updated_at), jsonb_build_object('id', s.id, 'updated_at', s.updated_at))
      from public.time_shifts s where s.id = tests.uvar('p2')))::text$$, '1');
select tests.admin_rows('… uma auditoria review para p2', $$select 1 from public.time_audit_events where shift_id = tests.uvar('p2') and action = 'review'$$, 1);
select tests.query_is('jornada do relógio (none) + anulada pendente → 2',
  $$select public.time_review_shifts((select jsonb_agg(jsonb_build_object('id', s.id, 'updated_at', s.updated_at))
      from public.time_shifts s where s.id in (tests.uvar('n1'), tests.uvar('v1'))))::text$$, '2');
select tests.admin_query_is('anulada revisada continua anulada e fica reviewed',
  $$select (review_status = 'reviewed' and voided_at is not null)::text from public.time_shifts where id = tests.uvar('v1')$$, 'true');
select tests.admin_query_is('none → reviewed', $$select review_status from public.time_shifts where id = tests.uvar('n1')$$, 'reviewed');
select tests.admin_query_is('nota nula → reason nula na auditoria',
  $$select (reason is null)::text from public.time_audit_events where shift_id = tests.uvar('n1') and action = 'review'$$, 'true');
select tests.admin_rows('jornada aberta não foi revisada', $$select 1 from public.time_shifts where id = tests.uvar('o1') and review_status = 'reviewed'$$, 0);
select tests.query_true('super_admin vê as pendências da equipe (fetchPendingReview): só a do manager restou',
  $$select count(*) = 1 and bool_and(user_id = tests.uid('mgr')) from public.time_shifts where review_status = 'pending'$$);

select tests.note('depois de revisada, só o super_admin altera');
select tests.login('emp');
select tests.throws('dono corrigindo revisada → shift_locked',
  $$select public.time_correct_shift(tests.uvar('p1'), tests.brt('2026-10-19 08:00'), tests.brt('2026-10-19 11:00'), '[]'::jsonb, 'Quero corrigir de novo')$$,
  'shift_locked', 'P0001');
select tests.throws('dono anulando revisada → shift_locked',
  $$select public.time_void_shift(tests.uvar('p1'), 'Quero anular esta jornada')$$, 'shift_locked', 'P0001');
select tests.query_true('dono vê quem revisou e quando (reviewed_by/reviewed_at)',
  $$select reviewed_by = tests.uid('sa') and reviewed_at is not null from public.time_shifts where id = tests.uvar('p1')$$);
select tests.login('sa');
select tests.capture('c', $$select public.time_correct_shift(tests.uvar('p1'), tests.brt('2026-10-19 08:00'), tests.brt('2026-10-19 11:00'), '[]'::jsonb, 'Ajuste após conversa')::text$$);
select tests.eq('super_admin corrige a revisada; continua reviewed', tests.jvar('c')->>'review_status', 'reviewed');

select tests.done();
rollback;
