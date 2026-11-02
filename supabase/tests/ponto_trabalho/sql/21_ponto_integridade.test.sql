-- 21 — Regras críticas do banco para o ponto (§3.2), como POSTGRES de
-- propósito: constraints, índices únicos parciais, exclusão por sobreposição e
-- os triggers IMEDIATOS de integridade rejeitam linhas inválidas mesmo sem
-- passar pelas RPCs (defesa em profundidade). Imutabilidade da auditoria para
-- postgres, service_role e authenticated. FKs restrict/cascade.
begin;

select tests.create_user('emp', 'employee');
select tests.create_user('emp2', 'employee');
select tests.create_user('ghost', null);
select tests.logout();
select tests.eq('caso explícito: este arquivo escreve como postgres', current_user::text, 'postgres');

-- Jornada base J: 2026-10-01 08:00–12:00 com intervalo 09:00–10:00.
select tests.capture('j', $$insert into public.time_shifts (user_id, started_at, ended_at)
    values (tests.uid('emp'), tests.brt('2026-10-01 08:00'), tests.brt('2026-10-01 12:00')) returning id::text$$);
select tests.capture('jb', $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at)
    values (tests.uvar('j'), tests.uid('emp'), tests.brt('2026-10-01 09:00'), tests.brt('2026-10-01 10:00')) returning id::text$$);

select tests.note('time_shifts: checks e defaults');
select tests.admin_query_is('defaults: source clock, review none, work_date em Brasília',
  $$select source || '|' || review_status || '|' || work_date from public.time_shifts where id = tests.uvar('j')$$, 'clock|none|2026-10-01');
select tests.throws_constraint('fim = início → time_shifts_range_chk',
  $$insert into public.time_shifts (user_id, started_at, ended_at) values (tests.uid('emp'), tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 08:00'))$$,
  '23514', 'time_shifts_range_chk');
select tests.throws_constraint('fim antes do início → time_shifts_range_chk',
  $$insert into public.time_shifts (user_id, started_at, ended_at) values (tests.uid('emp'), tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 07:00'))$$,
  '23514', 'time_shifts_range_chk');
select tests.throws_constraint('anulação parcial (voided_at sem voided_by/void_reason) → time_shifts_void_chk',
  $$insert into public.time_shifts (user_id, started_at, ended_at, voided_at) values (tests.uid('emp'), tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 09:00'), now())$$,
  '23514', 'time_shifts_void_chk');
select tests.throws_constraint('void_reason sem voided_at → time_shifts_void_chk',
  $$insert into public.time_shifts (user_id, started_at, ended_at, void_reason) values (tests.uid('emp'), tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 09:00'), 'motivo qualquer')$$,
  '23514', 'time_shifts_void_chk');
select tests.throws_constraint('reviewed sem reviewed_at/by → time_shifts_review_chk',
  $$insert into public.time_shifts (user_id, started_at, ended_at, review_status) values (tests.uid('emp'), tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 09:00'), 'reviewed')$$,
  '23514', 'time_shifts_review_chk');
select tests.throws_constraint('reviewed_at/by preenchidos sem status reviewed → time_shifts_review_chk',
  $$insert into public.time_shifts (user_id, started_at, ended_at, review_status, reviewed_at, reviewed_by)
    values (tests.uid('emp'), tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 09:00'), 'pending', now(), tests.uid('emp2'))$$,
  '23514', 'time_shifts_review_chk');
select tests.throws_constraint('revisada e aberta → time_shifts_reviewed_closed_chk',
  $$insert into public.time_shifts (user_id, started_at, review_status, reviewed_at, reviewed_by)
    values (tests.uid('emp2'), tests.brt('2026-10-02 08:00'), 'reviewed', now(), tests.uid('emp'))$$,
  '23514', 'time_shifts_reviewed_closed_chk');
select tests.throws('source fora da lista → 23514',
  $$insert into public.time_shifts (user_id, started_at, ended_at, source) values (tests.uid('emp'), tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 09:00'), 'app')$$, null, '23514');
select tests.throws('review_status fora da lista → 23514',
  $$insert into public.time_shifts (user_id, started_at, ended_at, review_status) values (tests.uid('emp'), tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 09:00'), 'approved')$$, null, '23514');
select tests.throws('nota com 501 caracteres → 23514',
  $$insert into public.time_shifts (user_id, started_at, ended_at, note) values (tests.uid('emp'), tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 09:00'), repeat('n', 501))$$, null, '23514');
select tests.throws('work_date é gerado (não aceita valor) → 428C9',
  $$insert into public.time_shifts (user_id, started_at, ended_at, work_date) values (tests.uid('emp'), tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 09:00'), '2026-10-02')$$, null, '428C9');
select tests.throws('dono sem perfil → FK 23503',
  $$insert into public.time_shifts (user_id, started_at, ended_at) values (tests.uid('ghost'), tests.brt('2026-10-02 08:00'), tests.brt('2026-10-02 09:00'))$$, null, '23503');

select tests.note('time_shifts: sobreposição e uma aberta por pessoa');
select tests.throws_constraint('jornadas sobrepostas → time_shifts_no_overlap (23P01)',
  $$insert into public.time_shifts (user_id, started_at, ended_at) values (tests.uid('emp'), tests.brt('2026-10-01 11:00'), tests.brt('2026-10-01 13:00'))$$,
  '23P01', 'time_shifts_no_overlap');
select tests.lives('jornadas encostadas são válidas ([) )',
  $$insert into public.time_shifts (user_id, started_at, ended_at) values (tests.uid('emp'), tests.brt('2026-10-01 12:00'), tests.brt('2026-10-01 13:00'))$$);
select tests.lives('anulada pode sobrepor (exclusão só entre não anuladas)',
  $$insert into public.time_shifts (user_id, started_at, ended_at, voided_at, voided_by, void_reason)
    values (tests.uid('emp'), tests.brt('2026-10-01 08:30'), tests.brt('2026-10-01 11:30'), now(), tests.uid('emp'), 'lançada em duplicidade')$$);
select tests.lives('outra pessoa no mesmo horário é válida',
  $$insert into public.time_shifts (user_id, started_at, ended_at) values (tests.uid('emp2'), tests.brt('2026-10-01 08:00'), tests.brt('2026-10-01 12:00'))$$);
select tests.capture('open1', $$insert into public.time_shifts (user_id, started_at) values (tests.uid('emp'), tests.brt('2026-10-03 08:00')) returning id::text$$);
select tests.query_true('segunda aberta da mesma pessoa → time_shifts_one_open_per_user ou time_shifts_no_overlap',
  $$select t.o_sqlstate in ('23505', '23P01') and t.o_constraint in ('time_shifts_one_open_per_user', 'time_shifts_no_overlap')
     from tests._try($q$insert into public.time_shifts (user_id, started_at) values (tests.uid('emp'), tests.brt('2026-10-04 08:00'))$q$) t$$);
select tests.lives('anulada sobreposta à jornada aberta não conflita',
  $$insert into public.time_shifts (user_id, started_at, ended_at, voided_at, voided_by, void_reason)
    values (tests.uid('emp'), tests.brt('2026-10-04 08:00'), tests.brt('2026-10-04 09:00'), now(), tests.uid('emp'), 'teste de anulada')$$);
select tests.query_is('índice parcial time_shifts_one_open_per_user (definição exata)',
  $$select pg_get_indexdef('public.time_shifts_one_open_per_user'::regclass)$$,
  'CREATE UNIQUE INDEX time_shifts_one_open_per_user ON public.time_shifts USING btree (user_id) WHERE ((ended_at IS NULL) AND (voided_at IS NULL))');

select tests.note('time_breaks: trigger imediato time_breaks_guard');
select tests.throws('intervalo com user_id diferente do dono → break_outside_shift 23514',
  $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at) values (tests.uvar('j'), tests.uid('emp2'), tests.brt('2026-10-01 10:30'), tests.brt('2026-10-01 10:45'))$$,
  'break_outside_shift', '23514');
select tests.throws('intervalo antes da entrada → break_outside_shift 23514',
  $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at) values (tests.uvar('j'), tests.uid('emp'), tests.brt('2026-10-01 07:30'), tests.brt('2026-10-01 08:15'))$$,
  'break_outside_shift', '23514');
select tests.throws('intervalo depois da saída → break_outside_shift 23514',
  $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at) values (tests.uvar('j'), tests.uid('emp'), tests.brt('2026-10-01 11:30'), tests.brt('2026-10-01 12:30'))$$,
  'break_outside_shift', '23514');
select tests.throws('intervalo aberto em jornada encerrada → break_open_on_closed_shift 23514',
  $$insert into public.time_breaks (shift_id, user_id, started_at) values (tests.uvar('j'), tests.uid('emp'), tests.brt('2026-10-01 11:00'))$$,
  'break_open_on_closed_shift', '23514');
select tests.throws('UPDATE do intervalo para além da saída → break_outside_shift 23514',
  $$update public.time_breaks set ended_at = tests.brt('2026-10-01 12:30') where id = tests.uvar('jb')$$,
  'break_outside_shift', '23514');
select tests.throws('UPDATE do intervalo para aberto em jornada encerrada → break_open_on_closed_shift 23514',
  $$update public.time_breaks set ended_at = null where id = tests.uvar('jb')$$,
  'break_open_on_closed_shift', '23514');
select tests.throws_constraint('intervalo com fim <= início (dentro da jornada) → time_breaks_range_chk',
  $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at) values (tests.uvar('j'), tests.uid('emp'), tests.brt('2026-10-01 11:00'), tests.brt('2026-10-01 11:00'))$$,
  '23514', 'time_breaks_range_chk');
select tests.throws_constraint('intervalos sobrepostos → time_breaks_no_overlap (23P01)',
  $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at) values (tests.uvar('j'), tests.uid('emp'), tests.brt('2026-10-01 09:30'), tests.brt('2026-10-01 10:30'))$$,
  '23P01', 'time_breaks_no_overlap');
select tests.lives('intervalos encostados entre si e nas bordas são válidos',
  $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at) values
      (tests.uvar('j'), tests.uid('emp'), tests.brt('2026-10-01 08:00'), tests.brt('2026-10-01 09:00')),
      (tests.uvar('j'), tests.uid('emp'), tests.brt('2026-10-01 10:00'), tests.brt('2026-10-01 11:00')),
      (tests.uvar('j'), tests.uid('emp'), tests.brt('2026-10-01 11:00'), tests.brt('2026-10-01 12:00'))$$);
select tests.lives('intervalo aberto em jornada aberta é válido',
  $$insert into public.time_breaks (shift_id, user_id, started_at) values (tests.uvar('open1'), tests.uid('emp'), tests.brt('2026-10-03 09:00'))$$);
select tests.query_true('segundo intervalo aberto na mesma jornada → time_breaks_one_open_per_shift ou time_breaks_no_overlap',
  $$select t.o_sqlstate in ('23505', '23P01') and t.o_constraint in ('time_breaks_one_open_per_shift', 'time_breaks_no_overlap')
     from tests._try($q$insert into public.time_breaks (shift_id, user_id, started_at) values (tests.uvar('open1'), tests.uid('emp'), tests.brt('2026-10-03 10:00'))$q$) t$$);
select tests.query_is('índice parcial time_breaks_one_open_per_shift (definição exata)',
  $$select pg_get_indexdef('public.time_breaks_one_open_per_shift'::regclass)$$,
  'CREATE UNIQUE INDEX time_breaks_one_open_per_shift ON public.time_breaks USING btree (shift_id) WHERE (ended_at IS NULL)');

select tests.note('time_shifts: trigger AFTER UPDATE revalida os intervalos ATUAIS');
select tests.throws('adiantar a saída para antes do fim de um intervalo → break_outside_shift 23514',
  $$update public.time_shifts set ended_at = tests.brt('2026-10-01 11:30') where id = tests.uvar('j')$$, 'break_outside_shift', '23514');
select tests.throws('atrasar a entrada para depois do início de um intervalo → break_outside_shift 23514',
  $$update public.time_shifts set started_at = tests.brt('2026-10-01 08:30') where id = tests.uvar('j')$$, 'break_outside_shift', '23514');
select tests.throws('encerrar jornada com intervalo aberto → break_open_on_closed_shift 23514',
  $$update public.time_shifts set ended_at = tests.brt('2026-10-03 12:00') where id = tests.uvar('open1')$$, 'break_open_on_closed_shift', '23514');
-- "user_id igual ao da jornada" (§3.2) vale nos dois lados: trocar o dono da
-- jornada deixaria os intervalos com o user_id antigo (e visíveis pela RLS ao
-- dono antigo). O novo dono não tem jornada nenhuma, para a exclusão por
-- sobreposição não responder antes.
select tests.create_user('emp_novo', 'employee');
select tests.throws('trocar o dono de jornada com intervalos → break_outside_shift 23514',
  $$update public.time_shifts set user_id = tests.uid('emp_novo') where id = tests.uvar('j')$$, 'break_outside_shift', '23514');
select tests.lives('ordem das RPCs funciona: apaga intervalos → atualiza jornada → insere intervalos',
  $$with d as (delete from public.time_breaks where shift_id = tests.uvar('j') returning 1) select count(*) from d$$);
select tests.lives('… atualiza a jornada sem intervalos', $$update public.time_shifts set started_at = tests.brt('2026-10-01 08:30'), ended_at = tests.brt('2026-10-01 11:30') where id = tests.uvar('j')$$);
select tests.lives('… insere os novos intervalos',
  $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at) values (tests.uvar('j'), tests.uid('emp'), tests.brt('2026-10-01 09:00'), tests.brt('2026-10-01 09:30'))$$);
select tests.lives('ordem de encerramento: fecha o intervalo → fecha a jornada',
  $$update public.time_breaks set ended_at = tests.brt('2026-10-03 11:00') where shift_id = tests.uvar('open1') and ended_at is null$$);
select tests.lives('… e a jornada', $$update public.time_shifts set ended_at = tests.brt('2026-10-03 12:00') where id = tests.uvar('open1')$$);

select tests.note('updated_at');
select tests.capture('u', $$insert into public.time_shifts (user_id, started_at, ended_at, updated_at)
    values (tests.uid('emp2'), tests.brt('2026-10-05 08:00'), tests.brt('2026-10-05 09:00'), '2000-01-01T00:00:00Z') returning id::text$$);
select tests.lives('UPDATE da jornada', $$update public.time_shifts set note = 'nota' where id = tests.uvar('u')$$);
select tests.admin_query_is('trigger pt_set_updated_at: updated_at = now() após UPDATE',
  $$select (updated_at = now())::text from public.time_shifts where id = tests.uvar('u')$$, 'true');
select tests.capture('ub', $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at, updated_at)
    values (tests.uvar('u'), tests.uid('emp2'), tests.brt('2026-10-05 08:10'), tests.brt('2026-10-05 08:20'), '2000-01-01T00:00:00Z') returning id::text$$);
select tests.lives('UPDATE do intervalo', $$update public.time_breaks set ended_at = tests.brt('2026-10-05 08:25') where id = tests.uvar('ub')$$);
select tests.admin_query_is('time_breaks: updated_at = now() após UPDATE',
  $$select (updated_at = now())::text from public.time_breaks where id = tests.uvar('ub')$$, 'true');

select tests.note('FKs: intervalo some com a jornada; perfil com ponto não é apagado');
select tests.capture('del', $$insert into public.time_shifts (user_id, started_at, ended_at) values (tests.uid('emp2'), tests.brt('2026-10-06 08:00'), tests.brt('2026-10-06 09:00')) returning id::text$$);
select tests.step('intervalo da jornada a apagar', $$insert into public.time_breaks (shift_id, user_id, started_at, ended_at) values (tests.uvar('del'), tests.uid('emp2'), tests.brt('2026-10-06 08:10'), tests.brt('2026-10-06 08:20'))$$);
select tests.affects('jornada sem auditoria pode ser apagada pelo dono do banco', $$delete from public.time_shifts where id = tests.uvar('del')$$, 1);
select tests.admin_rows('… e o intervalo vai junto (on delete cascade)', $$select 1 from public.time_breaks where shift_id = tests.uvar('del')$$, 0);
select tests.throws('perfil com jornadas não é apagado (on delete restrict) → 23503',
  $$delete from public.profiles where id = tests.uid('emp')$$, null, '23503');

-- ─────────────────────────────────────────────────────────────────────────────
select tests.note('time_audit_events: checks, unicidade e imutabilidade');
select tests.capture('ev1', $$insert into public.time_audit_events (shift_id, subject_user_id, actor_id, action, request_id)
    values (tests.uvar('j'), tests.uid('emp'), tests.uid('emp'), 'clock_in', tests.new_id('req')) returning id::text$$);
select tests.capture('ev2', $$insert into public.time_audit_events (shift_id, subject_user_id, actor_id, action)
    values (tests.uvar('j'), tests.uid('emp'), tests.uid('emp'), 'clock_out') returning id::text$$);
select tests.admin_true('seq crescente e created_at = clock_timestamp() (difere dentro da transação)',
  $$select b.seq > a.seq and b.created_at > a.created_at and a.created_at > now()
     from public.time_audit_events a, public.time_audit_events b where a.id = tests.uvar('ev1') and b.id = tests.uvar('ev2')$$);
select tests.throws('seq é identity ALWAYS (não aceita valor) → 428C9',
  $$insert into public.time_audit_events (seq, subject_user_id, actor_id, action) values (1, tests.uid('emp'), tests.uid('emp'), 'clock_in')$$, null, '428C9');
select tests.throws_constraint('mesmo (autor, request_id) → time_audit_events_request_uniq',
  $$insert into public.time_audit_events (subject_user_id, actor_id, action, request_id) values (tests.uid('emp'), tests.uid('emp'), 'clock_out', tests.uvar('req'))$$,
  '23505', 'time_audit_events_request_uniq');
select tests.lives('mesmo request_id com outro autor é válido',
  $$insert into public.time_audit_events (subject_user_id, actor_id, action, request_id) values (tests.uid('emp2'), tests.uid('emp2'), 'clock_in', tests.uvar('req'))$$);
select tests.lives('request_id nulo repetido é válido',
  $$insert into public.time_audit_events (subject_user_id, actor_id, action) values (tests.uid('emp'), tests.uid('emp'), 'break_end')$$);
select tests.throws_constraint('correct com justificativa curta → time_audit_reason_chk',
  $$insert into public.time_audit_events (subject_user_id, actor_id, action, reason) values (tests.uid('emp'), tests.uid('emp'), 'correct', 'curta')$$,
  '23514', 'time_audit_reason_chk');
select tests.throws_constraint('create_manual sem justificativa → time_audit_reason_chk',
  $$insert into public.time_audit_events (subject_user_id, actor_id, action) values (tests.uid('emp'), tests.uid('emp'), 'create_manual')$$,
  '23514', 'time_audit_reason_chk');
select tests.throws_constraint('void com justificativa só de espaços → time_audit_reason_chk',
  $$insert into public.time_audit_events (subject_user_id, actor_id, action, reason) values (tests.uid('emp'), tests.uid('emp'), 'void', '              ')$$,
  '23514', 'time_audit_reason_chk');
select tests.throws('ação fora da lista → 23514',
  $$insert into public.time_audit_events (subject_user_id, actor_id, action) values (tests.uid('emp'), tests.uid('emp'), 'delete')$$, null, '23514');
select tests.throws('justificativa com 1001 caracteres → 23514',
  $$insert into public.time_audit_events (subject_user_id, actor_id, action, reason) values (tests.uid('emp'), tests.uid('emp'), 'review', repeat('r', 1001))$$, null, '23514');
select tests.throws('postgres: UPDATE na auditoria → audit_immutable 42501',
  $$update public.time_audit_events set reason = 'reescrito' where id = tests.uvar('ev1')$$, 'audit_immutable', '42501');
select tests.throws('postgres: DELETE na auditoria → audit_immutable 42501',
  $$delete from public.time_audit_events where id = tests.uvar('ev1')$$, 'audit_immutable', '42501');
select tests.throws('jornada com auditoria não é apagada (restrict) → 23503',
  $$delete from public.time_shifts where id = tests.uvar('j')$$, null, '23503');
select tests.login_service();
-- service_role mantém os grants padrão (o contrato só revoga de anon/authenticated):
-- quem barra é o trigger. Um grant mais estrito também é aceito (42501).
select tests.throws('service_role: UPDATE na auditoria → bloqueado (42501)',
  $$update public.time_audit_events set reason = 'reescrito' where id = tests.uvar('ev1')$$, null, '42501');
select tests.throws('service_role: DELETE na auditoria → bloqueado (42501)',
  $$delete from public.time_audit_events where id = tests.uvar('ev1')$$, null, '42501');
select tests.login('emp');
select tests.denied('authenticated: UPDATE na auditoria → sem grant', $$update public.time_audit_events set reason = 'x' where id = tests.uvar('ev1')$$);
select tests.denied('authenticated: DELETE na auditoria → sem grant', $$delete from public.time_audit_events where id = tests.uvar('ev1')$$);
select tests.logout();
select tests.admin_rows('auditoria intacta', $$select 1 from public.time_audit_events where id = tests.uvar('ev1') and reason is null$$, 1);

select tests.done();
rollback;
