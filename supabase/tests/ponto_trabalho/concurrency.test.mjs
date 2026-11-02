// ─────────────────────────────────────────────────────────────────────────────
// Concorrência REAL das batidas (contrato §3.3 passos 4–7, §5).
//
// Cada chamada é um comando autocommit numa conexão própria do papel
// authenticated (entra como authenticator e faz SET ROLE, como o PostgREST),
// em READ COMMITTED. Para as N chamadas saírem juntas de verdade, cada uma
// passa por uma "largada" independente da migration:
//   with largada as materialized (select pg_advisory_xact_lock_shared(K)) select rpc(...) from largada
// Uma conexão de controle segura o lock exclusivo K; o teste espera as N
// conexões aparecerem esperando em pg_locks e só então solta. Assim fica
// provado que as N estavam paradas no mesmo ponto e partiram juntas.
//
// Chamado pelo run.mjs (export default). Nada aqui fala com a produção.
// ─────────────────────────────────────────────────────────────────────────────
import crypto from 'node:crypto';

const BARRIER_KEY = 7744110;

export default async function concurrency({ admin, connectAdmin, connectApi, check, truth, note }) {
  const N = Math.max(2, Number(process.env.PONTO_CONCORRENCIA_N || 8));
  const ROUNDS = Math.max(2, Number(process.env.PONTO_CONCORRENCIA_RODADAS || 12));
  const tag = crypto.randomBytes(3).toString('hex');
  note(`N = ${N} conexões simultâneas por cenário; ${ROUNDS} rodadas de saída × intervalo`);

  // ── utilitários ──────────────────────────────────────────────────────────
  async function createUser(name, role) {
    const r = await admin.query('select tests.create_user($1, $2)::text as id', [`${name}_${tag}`, role]);
    return r.rows[0].id;
  }

  async function q1(sql, params = []) {
    const r = await admin.query(sql, params);
    return r.rows[0];
  }

  async function clients(uid, n) {
    const list = [];
    for (let i = 0; i < n; i += 1) list.push(await connectApi(uid));
    return list;
  }

  async function closeAll(list) {
    await Promise.all(list.map((c) => c.end().catch(() => {})));
  }

  async function run(c, sql, params = []) {
    try {
      const r = await c.query(sql, params);
      return { ok: true, value: r.rows[0]?.r ?? null };
    } catch (e) {
      return { ok: false, code: e.code, message: e.message };
    }
  }

  function outcome(r) {
    return r.ok ? 'ok' : `${r.code} ${r.message}`;
  }

  function tally(results) {
    const m = new Map();
    for (const r of results) m.set(outcome(r), (m.get(outcome(r)) ?? 0) + 1);
    return [...m.entries()].map(([k, v]) => `${v}× ${k}`).join(', ');
  }

  async function sleep(ms) {
    await new Promise((resolve) => setTimeout(resolve, ms));
  }

  async function waitUntil(fn, timeoutMs) {
    const end = Date.now() + timeoutMs;
    while (Date.now() < end) {
      if (await fn()) return true;
      await sleep(20);
    }
    return fn();
  }

  async function waitingOnBarrier() {
    const r = await q1(
      `select count(*)::int as n from pg_locks
        where locktype = 'advisory' and not granted and classid = 0 and objid = $1 and objsubid = 1`,
      [BARRIER_KEY],
    );
    return r.n;
  }

  /**
   * Dispara calls[i](client) em todos os clientes ao mesmo tempo, atrás da largada.
   * Cada call devolve { sql, params } de UMA expressão (a RPC).
   */
  async function simultaneous(label, list, makeCall) {
    const gate = await connectAdmin();
    await gate.query('select pg_advisory_lock($1)', [BARRIER_KEY]);
    const pending = list.map((c, i) => {
      const { sql, params } = makeCall(i);
      return run(
        c,
        `with largada as materialized (select pg_advisory_xact_lock_shared(${BARRIER_KEY}))
         select (${sql})::text as r from largada`,
        params,
      );
    });
    const allWaiting = await waitUntil(async () => (await waitingOnBarrier()) >= list.length, 15000);
    check(allWaiting, `${label}: as ${list.length} chamadas estavam paradas juntas na largada`, `esperando: ${await waitingOnBarrier()}`);
    await gate.query('select pg_advisory_unlock($1)', [BARRIER_KEY]);
    await gate.end();
    return Promise.all(pending);
  }

  const shiftCount = async (uid) =>
    (await q1('select count(*)::int as n from public.time_shifts where user_id = $1', [uid])).n;
  const openShiftCount = async (uid) =>
    (await q1('select count(*)::int as n from public.time_shifts where user_id = $1 and ended_at is null and voided_at is null', [uid])).n;
  const openBreakCount = async (uid) =>
    (await q1('select count(*)::int as n from public.time_breaks where user_id = $1 and ended_at is null', [uid])).n;
  const auditCount = async (uid, action) =>
    (await q1('select count(*)::int as n from public.time_audit_events where subject_user_id = $1 and action = $2', [uid, action])).n;
  const ridCount = async (rid) =>
    (await q1('select count(*)::int as n from public.time_audit_events where request_id = $1', [rid])).n;

  /** Invariantes do ponto de uma pessoa (verdade do banco). */
  async function invariants(uid) {
    return q1(
      `select
         (select count(*) from public.time_shifts s where s.user_id = $1 and s.ended_at is null and s.voided_at is null)::int as open_shifts,
         (select count(*) from public.time_breaks b join public.time_shifts s on s.id = b.shift_id
           where s.user_id = $1 and b.ended_at is null and s.ended_at is not null)::int as open_break_on_closed,
         (select count(*) from public.time_breaks b join public.time_shifts s on s.id = b.shift_id
           where s.user_id = $1 and (b.started_at < s.started_at or (s.ended_at is not null and b.ended_at > s.ended_at)))::int as outside,
         (select coalesce(max(c), 0) from (select count(*) c from public.time_breaks b
           where b.user_id = $1 and b.ended_at is null group by b.shift_id) x)::int as max_open_breaks,
         (select count(*) from public.time_breaks b join public.time_shifts s on s.id = b.shift_id
           where s.user_id = $1 and b.user_id <> s.user_id)::int as foreign_breaks`,
      [uid],
    );
  }

  function invariantsOk(inv) {
    return inv.open_shifts <= 1 && inv.open_break_on_closed === 0 && inv.outside === 0 && inv.max_open_breaks <= 1 && inv.foreign_breaks === 0;
  }

  const ok = (list) => list.filter((r) => r.ok);
  const errs = (list) => list.filter((r) => !r.ok);
  const allErr = (list, message) => errs(list).every((r) => r.code === 'P0001' && r.message === message);

  // ── 1. N× entrada ────────────────────────────────────────────────────────
  note('N× time_clock_in da mesma pessoa');
  const u1 = await createUser('conc_u1', 'employee');
  let cs = await clients(u1, N);
  let res = await simultaneous('entrada', cs, () => ({ sql: 'public.time_clock_in()', params: [] }));
  check(ok(res).length === 1, 'N× entrada → exatamente 1 sucesso', tally(res));
  check(allErr(res, 'shift_already_open'), 'as demais → shift_already_open (P0001)', tally(res));
  truth((await shiftCount(u1)) === 1, 'verdade: exatamente 1 jornada', `jornadas: ${await shiftCount(u1)}`);
  truth((await openShiftCount(u1)) === 1, 'verdade: exatamente 1 jornada aberta');
  truth((await auditCount(u1, 'clock_in')) === 1, 'verdade: exatamente 1 auditoria clock_in', `clock_in: ${await auditCount(u1, 'clock_in')}`);

  // ── 2. N× intervalo ──────────────────────────────────────────────────────
  note('N× time_start_break');
  res = await simultaneous('intervalo', cs, () => ({ sql: 'public.time_start_break()', params: [] }));
  check(ok(res).length === 1, 'N× intervalo → exatamente 1 sucesso', tally(res));
  check(allErr(res, 'break_already_open'), 'as demais → break_already_open (P0001)', tally(res));
  truth((await openBreakCount(u1)) === 1, 'verdade: exatamente 1 intervalo aberto', `abertos: ${await openBreakCount(u1)}`);
  truth((await auditCount(u1, 'break_start')) === 1, 'verdade: exatamente 1 auditoria break_start');

  // ── 3. N× retorno ────────────────────────────────────────────────────────
  note('N× time_end_break');
  res = await simultaneous('retorno', cs, () => ({ sql: 'public.time_end_break()', params: [] }));
  check(ok(res).length === 1, 'N× retorno → exatamente 1 sucesso', tally(res));
  check(allErr(res, 'no_open_break'), 'as demais → no_open_break (P0001)', tally(res));
  truth((await openBreakCount(u1)) === 0, 'verdade: nenhum intervalo aberto');
  truth((await auditCount(u1, 'break_end')) === 1, 'verdade: exatamente 1 auditoria break_end');

  // ── 4. N× saída ──────────────────────────────────────────────────────────
  note('N× time_clock_out');
  res = await simultaneous('saída', cs, () => ({ sql: 'public.time_clock_out()', params: [] }));
  check(ok(res).length === 1, 'N× saída → exatamente 1 sucesso', tally(res));
  check(allErr(res, 'no_open_shift'), 'as demais → no_open_shift (P0001)', tally(res));
  truth((await openShiftCount(u1)) === 0, 'verdade: nenhuma jornada aberta');
  truth((await auditCount(u1, 'clock_out')) === 1, 'verdade: exatamente 1 auditoria clock_out');
  truth(invariantsOk(await invariants(u1)), 'verdade: estado final válido', JSON.stringify(await invariants(u1)));
  await closeAll(cs);

  // ── 5. mesmo request_id de N conexões ────────────────────────────────────
  note('mesmo p_request_id de N conexões (entrada, intervalo, saída fechando o intervalo)');
  const u2 = await createUser('conc_u2', 'employee');
  cs = await clients(u2, N);
  const rIn = crypto.randomUUID();
  res = await simultaneous('entrada idempotente', cs, () => ({ sql: `public.time_clock_in('${rIn}'::uuid)`, params: [] }));
  check(ok(res).length === N, 'mesmo request_id na entrada → todas com sucesso', tally(res));
  const ids = new Set(ok(res).map((r) => JSON.parse(r.value).id));
  check(ids.size === 1, 'todas recebem a MESMA jornada', `ids distintos: ${ids.size}`);
  truth((await shiftCount(u2)) === 1, 'verdade: 1 jornada', `jornadas: ${await shiftCount(u2)}`);
  truth((await ridCount(rIn)) === 1, 'verdade: 1 linha de auditoria com o request_id', `linhas: ${await ridCount(rIn)}`);

  const rBr = crypto.randomUUID();
  res = await simultaneous('intervalo idempotente', cs, () => ({ sql: `public.time_start_break('${rBr}'::uuid)`, params: [] }));
  check(ok(res).length === N, 'mesmo request_id no intervalo → todas com sucesso', tally(res));
  check(new Set(ok(res).map((r) => JSON.parse(r.value).id)).size === 1, '… mesma jornada para todas');
  truth((await openBreakCount(u2)) === 1, 'verdade: 1 intervalo aberto', `abertos: ${await openBreakCount(u2)}`);
  truth((await ridCount(rBr)) === 1, 'verdade: 1 auditoria com o request_id do intervalo');

  const rOut = crypto.randomUUID();
  res = await simultaneous('saída idempotente', cs, () => ({ sql: `public.time_clock_out('${rOut}'::uuid, true)`, params: [] }));
  check(ok(res).length === N, 'mesmo request_id na saída (fechando intervalo) → todas com sucesso', tally(res));
  const endedSet = new Set(ok(res).map((r) => JSON.parse(r.value).ended_at));
  check(endedSet.size === 1 && !endedSet.has(null), '… todas veem a mesma saída', `fins distintos: ${[...endedSet].join(' | ')}`);
  truth((await ridCount(rOut)) === 1, 'verdade: 1 auditoria com o request_id da saída');
  truth((await auditCount(u2, 'clock_out')) === 1, 'verdade: 1 clock_out');
  truth(
    (await q1(`select count(*)::int as n from public.time_audit_events where subject_user_id = $1 and action = 'break_end' and request_id is null`, [u2])).n === 1,
    'verdade: 1 break_end implícito (request_id nulo)',
  );
  truth(invariantsOk(await invariants(u2)), 'verdade: estado final válido', JSON.stringify(await invariants(u2)));
  await closeAll(cs);

  // ── 6. saída × intervalo simultâneos ─────────────────────────────────────
  note('time_clock_out × time_start_break simultâneos (com e sem p_close_open_break)');
  const u3 = await createUser('conc_u3', 'employee');
  const [ca, cb] = await clients(u3, 2);
  const orders = { saida_primeiro: 0, intervalo_primeiro: 0 };
  let raceOk = true;
  const raceProblems = [];
  for (let round = 1; round <= ROUNDS; round += 1) {
    const close = round % 2 === 0;
    const pre = await run(ca, 'select public.time_clock_in()::text as r');
    if (!pre.ok) {
      raceOk = false;
      raceProblems.push(`rodada ${round}: entrada falhou (${outcome(pre)})`);
      break;
    }
    const [ra, rb] = await simultaneous(`rodada ${round}`, [ca, cb], (i) =>
      i === 0 ? { sql: `public.time_clock_out(null, ${close})`, params: [] } : { sql: 'public.time_start_break()', params: [] },
    );
    const inv = await invariants(u3);
    const open = await openShiftCount(u3);
    const openBreaks = await openBreakCount(u3);
    let valid = invariantsOk(inv);
    if (!close) {
      // Exatamente uma vence: saída primeiro (intervalo → no_open_shift) ou
      // intervalo primeiro (saída → break_open, jornada segue aberta em intervalo).
      if (ra.ok && !rb.ok && rb.message === 'no_open_shift' && open === 0) orders.saida_primeiro += 1;
      else if (!ra.ok && ra.message === 'break_open' && rb.ok && open === 1 && openBreaks === 1) orders.intervalo_primeiro += 1;
      else valid = false;
    } else {
      // Com p_close_open_break: saída primeiro (intervalo → no_open_shift) ou
      // intervalo primeiro e a saída fecha o intervalo (as duas com sucesso).
      if (ra.ok && !rb.ok && rb.message === 'no_open_shift' && open === 0) orders.saida_primeiro += 1;
      else if (ra.ok && rb.ok && open === 0 && openBreaks === 0) orders.intervalo_primeiro += 1;
      else valid = false;
    }
    if (!valid) {
      raceOk = false;
      raceProblems.push(`rodada ${round} (fechar=${close}): saída=${outcome(ra)}; intervalo=${outcome(rb)}; ${JSON.stringify(inv)}; abertas=${open}`);
    }
    // Encerra o que sobrou para a próxima rodada.
    if (openBreaks > 0) await run(ca, 'select public.time_end_break()::text as r');
    if ((await openShiftCount(u3)) > 0) await run(ca, 'select public.time_clock_out(null, true)::text as r');
  }
  check(raceOk, `saída × intervalo: ${ROUNDS} rodadas sempre num estado de uma ordem serial válida`, raceProblems.slice(0, 5).join(' || '));
  note(`ordens observadas: saída primeiro ${orders.saida_primeiro}×, intervalo primeiro ${orders.intervalo_primeiro}×`);
  truth(invariantsOk(await invariants(u3)), 'verdade: estado final válido', JSON.stringify(await invariants(u3)));
  await closeAll([ca, cb]);

  // ── 7. N pessoas ao mesmo tempo ──────────────────────────────────────────
  note('N pessoas diferentes batendo a entrada ao mesmo tempo');
  const many = [];
  for (let i = 0; i < N; i += 1) many.push(await createUser(`conc_m${i}`, i % 2 === 0 ? 'employee' : 'manager'));
  cs = [];
  for (const uid of many) cs.push(await connectApi(uid));
  res = await simultaneous('N pessoas', cs, () => ({ sql: 'public.time_clock_in()', params: [] }));
  check(ok(res).length === N, 'cada pessoa abre a própria jornada (sem bloqueio cruzado)', tally(res));
  const owners = ok(res).map((r) => JSON.parse(r.value).user_id);
  check(new Set(owners).size === N && owners.every((o) => many.includes(o)), '… cada jornada pertence a quem chamou');
  await closeAll(cs);

  // ── 8. advisory lock do contrato ─────────────────────────────────────────
  note("advisory lock por dono do ponto: hashtextextended('ponto.time:' || uid, 0)");
  const u4 = await createUser('conc_u4', 'employee');
  cs = await clients(u4, N);
  const holder = await connectAdmin();
  await holder.query(`select pg_advisory_lock(hashtextextended('ponto.time:' || $1::text, 0))`, [u4]);
  const pendingLock = cs.map((c) => run(c, 'select public.time_clock_in()::text as r'));
  const stuck = await waitUntil(
    async () =>
      (
        await q1(
          `select count(*)::int as n from pg_locks l
            where l.locktype = 'advisory' and not l.granted and l.objsubid = 1
              and ((l.classid::bigint << 32) | l.objid::bigint) = hashtextextended('ponto.time:' || $1::text, 0)`,
          [u4],
        )
      ).n >= N,
    5000,
  );
  check(stuck, 'as N chamadas esperam no advisory lock da chave do contrato (serialização por pessoa)');
  // §3.3: time_my_status é "Sem lock" — com o lock da pessoa preso (e N
  // batidas na fila), a tela de status ainda responde na hora.
  const statusConn = await connectApi(u4);
  await statusConn.query('set statement_timeout = 3000');
  const statusStart = Date.now();
  const status = await run(statusConn, 'select public.time_my_status()::text as r');
  const statusMs = Date.now() - statusStart;
  check(
    status.ok && JSON.parse(status.value).open_shift === null && statusMs < 2000,
    'time_my_status não espera o advisory lock da pessoa ("Sem lock")',
    `${outcome(status)} em ${statusMs} ms`,
  );
  await statusConn.end().catch(() => {});
  await holder.query(`select pg_advisory_unlock(hashtextextended('ponto.time:' || $1::text, 0))`, [u4]);
  await holder.end();
  res = await Promise.all(pendingLock);
  check(ok(res).length === 1 && allErr(res, 'shift_already_open'), '… liberadas, 1 sucesso e as demais shift_already_open', tally(res));
  truth((await shiftCount(u4)) === 1, 'verdade: 1 jornada');
  await closeAll(cs);

  // ── 9. N× jornada manual no mesmo horário ────────────────────────────────
  note('N× time_create_manual_shift no mesmo horário (request_ids diferentes)');
  const u5 = await createUser('conc_u5', 'employee');
  cs = await clients(u5, N);
  res = await simultaneous('jornada manual', cs, () => ({
    sql: `public.time_create_manual_shift(null, '2026-10-05 08:00-03'::timestamptz, '2026-10-05 12:00-03'::timestamptz, '[]'::jsonb, 'Esqueci de bater o ponto', gen_random_uuid())`,
    params: [],
  }));
  check(ok(res).length === 1, 'N× jornada manual sobreposta → exatamente 1 sucesso', tally(res));
  check(allErr(res, 'shift_overlap'), 'as demais → shift_overlap (P0001)', tally(res));
  truth((await shiftCount(u5)) === 1, 'verdade: 1 jornada', `jornadas: ${await shiftCount(u5)}`);
  truth((await auditCount(u5, 'create_manual')) === 1, 'verdade: 1 auditoria create_manual');

  // ── 10. N× anulação da mesma jornada ─────────────────────────────────────
  note('N× time_void_shift da mesma jornada');
  const shiftU5 = (await q1('select id::text from public.time_shifts where user_id = $1', [u5])).id;
  res = await simultaneous('anulação', cs, () => ({
    sql: `public.time_void_shift('${shiftU5}'::uuid, 'Lancei no dia errado', gen_random_uuid())`,
    params: [],
  }));
  check(ok(res).length === 1, 'N× anulação → exatamente 1 sucesso', tally(res));
  check(allErr(res, 'shift_voided'), 'as demais → shift_voided (P0001)', tally(res));
  truth((await auditCount(u5, 'void')) === 1, 'verdade: 1 auditoria void');
  await closeAll(cs);

  // ── 11. duas revisões simultâneas ────────────────────────────────────────
  note('dois super_admins revisando a mesma jornada ao mesmo tempo (mesmo updated_at)');
  const u6 = await createUser('conc_u6', 'employee');
  const sa1 = await createUser('conc_sa1', 'super_admin');
  const sa2 = await createUser('conc_sa2', 'super_admin');
  const [c6] = await clients(u6, 1);
  const manual = await run(
    c6,
    `select public.time_create_manual_shift(null, '2026-10-06 08:00-03'::timestamptz, '2026-10-06 12:00-03'::timestamptz, '[]'::jsonb, 'Esqueci de bater o ponto')::text as r`,
  );
  await c6.end();
  check(manual.ok, 'preparação: jornada pendente criada', outcome(manual));
  const body = (
    await q1(
      `select jsonb_build_array(jsonb_build_object('id', s.id, 'updated_at', s.updated_at))::text as b
         from public.time_shifts s where s.user_id = $1`,
      [u6],
    )
  ).b;
  const revs = [await connectApi(sa1), await connectApi(sa2)];
  res = await simultaneous('revisão', revs, () => ({ sql: `public.time_review_shifts('${body}'::jsonb)`, params: [] }));
  const counted = ok(res).reduce((acc, r) => acc + Number(r.value), 0);
  check(counted === 1, 'as duas revisões somam exatamente 1 jornada revisada', tally(res));
  check(errs(res).length === 1 && allErr(res, 'shift_changed'), 'a segunda vê updated_at mudado → shift_changed', tally(res));
  truth((await auditCount(u6, 'review')) === 1, 'verdade: 1 auditoria review', `review: ${await auditCount(u6, 'review')}`);
  await closeAll(revs);

  // ── 12. revisão de várias pessoas: ordem dos locks e deadlock ────────────
  // §3.3 passo 4: "várias pessoas: locks em ordem crescente de uuid". Sem essa
  // ordem, duas revisões com listas [A, B] e [B, A] se travam (40P01).
  note('revisão de jornadas de duas pessoas: advisory locks em ordem crescente de uuid, sem deadlock');
  const pa = await createUser('conc_pa', 'employee');
  const pb = await createUser('conc_pb', 'employee');
  const sa3 = await createUser('conc_sa3', 'super_admin');
  const sa4 = await createUser('conc_sa4', 'super_admin');
  const { lo, hi } = await q1('select least($1::uuid, $2::uuid)::text as lo, greatest($1::uuid, $2::uuid)::text as hi', [pa, pb]);

  async function manualShift(uid, day) {
    const c = await connectApi(uid);
    const r = await run(
      c,
      `select public.time_create_manual_shift(null, '2026-10-${day} 08:00-03'::timestamptz, '2026-10-${day} 12:00-03'::timestamptz,
         '[]'::jsonb, 'Esqueci de bater o ponto')::text as r`,
    );
    await c.end().catch(() => {});
    return r.ok ? JSON.parse(r.value) : null;
  }
  async function reviewItem(shiftId) {
    return (await q1(`select jsonb_build_object('id', s.id, 'updated_at', s.updated_at) as j from public.time_shifts s where s.id = $1`, [shiftId])).j;
  }
  const personLock = `select count(*)::int as n from pg_locks l
     where l.locktype = 'advisory' and l.objsubid = 1 and l.pid = $2 and l.granted = $3
       and ((l.classid::bigint << 32) | l.objid::bigint) = hashtextextended('ponto.time:' || $1::text, 0)`;

  // Ordem determinística: com o lock da pessoa de MAIOR uuid preso, a revisão
  // de [maior, menor] tem de estar segurando o da menor enquanto espera.
  const sLo = await manualShift(lo, '10');
  const sHi = await manualShift(hi, '10');
  check(Boolean(sLo && sHi), 'preparação: uma jornada pendente para cada pessoa');
  if (sLo && sHi) {
    const revConn = await connectApi(sa3);
    const revPid = (await revConn.query('select pg_backend_pid() as p')).rows[0].p;
    const holder2 = await connectAdmin();
    await holder2.query(`select pg_advisory_lock(hashtextextended('ponto.time:' || $1::text, 0))`, [hi]);
    const bodyHiLo = JSON.stringify([await reviewItem(sHi.id), await reviewItem(sLo.id)]);
    const pendingReview = run(revConn, 'select public.time_review_shifts($1::jsonb)::text as r', [bodyHiLo]);
    const waitingHi = await waitUntil(async () => (await q1(personLock, [hi, revPid, false])).n === 1, 5000);
    const holdsLo = (await q1(personLock, [lo, revPid, true])).n === 1;
    check(
      waitingHi && holdsLo,
      'lista [maior, menor]: a revisão segura o lock da pessoa de menor uuid enquanto espera o da maior (ordem crescente)',
      `esperando o da maior: ${waitingHi}; segurando o da menor: ${holdsLo}`,
    );
    await holder2.query(`select pg_advisory_unlock(hashtextextended('ponto.time:' || $1::text, 0))`, [hi]);
    await holder2.end();
    const rv = await pendingReview;
    check(rv.ok && Number(rv.value) === 2, '… liberada, revisa as duas jornadas (retorna 2)', outcome(rv));
    await revConn.end().catch(() => {});
  }

  // Listas cruzadas ao mesmo tempo, várias rodadas.
  const CROSS = 4;
  const crossConns = [await connectApi(sa3), await connectApi(sa4)];
  let crossOk = true;
  const crossProblems = [];
  for (let round = 1; round <= CROSS; round += 1) {
    const day = String(10 + round);
    const a = await manualShift(lo, day);
    const b = await manualShift(hi, day);
    if (!a || !b) {
      crossOk = false;
      crossProblems.push(`rodada ${round}: preparação falhou`);
      continue;
    }
    const ia = await reviewItem(a.id);
    const ib = await reviewItem(b.id);
    const [x, y] = await simultaneous(`revisão cruzada ${round}`, crossConns, (i) => ({
      sql: 'public.time_review_shifts($1::jsonb)',
      params: [JSON.stringify(i === 0 ? [ia, ib] : [ib, ia])],
    }));
    const deadlock = [x, y].some((r) => r.code === '40P01');
    const winners = [x, y].filter((r) => r.ok && Number(r.value) === 2).length;
    const changed = [x, y].filter((r) => !r.ok && r.code === 'P0001' && r.message === 'shift_changed').length;
    if (deadlock || winners !== 1 || changed !== 1) {
      crossOk = false;
      crossProblems.push(`rodada ${round}: ${outcome(x)} | ${outcome(y)}`);
    }
  }
  check(
    crossOk,
    `[A, B] × [B, A] ao mesmo tempo (${CROSS} rodadas): sem deadlock (40P01); uma revisa as duas e a outra vê shift_changed`,
    crossProblems.join(' || '),
  );
  const reviewsLo = await auditCount(lo, 'review');
  const reviewsHi = await auditCount(hi, 'review');
  truth(
    reviewsLo === CROSS + 1 && reviewsHi === CROSS + 1,
    'verdade: uma auditoria review por jornada revisada',
    `menor: ${reviewsLo}, maior: ${reviewsHi}, esperado ${CROSS + 1} cada`,
  );
  await closeAll(crossConns);

  // ── 13. oráculo pelo lock ────────────────────────────────────────────────
  // §3.3: o passo 3 (dono ou super_admin, senão shift_not_found) vem ANTES do
  // passo 4 (advisory lock do dono). Se viesse depois, quem não pode ver o
  // ponto alheio descobriria pela demora que a pessoa está batendo o ponto
  // naquele instante. Com o lock da pessoa preso, quem não pode responde na
  // hora; o super_admin (controle) espera o lock.
  note('oráculo pelo lock: quem não pode ver a jornada não espera o advisory lock do dono');
  const victim = await createUser('conc_vitima', 'employee');
  const spy = await createUser('conc_espiao', 'manager');
  const peer = await createUser('conc_colega', 'employee');
  const boss = await createUser('conc_chefe', 'super_admin');
  const [vc] = await clients(victim, 1);
  const opened = await run(vc, 'select public.time_clock_in()::text as r');
  await vc.end().catch(() => {});
  check(opened.ok, 'preparação: jornada aberta da pessoa', outcome(opened));
  if (opened.ok) {
    const vs = JSON.parse(opened.value);
    const victimKey = `hashtextextended('ponto.time:' || $1::text, 0)`;
    const correctSql = `select public.time_correct_shift($1::uuid, $2::timestamptz, null, '[]'::jsonb, 'Justificativa qualquer')::text as r`;
    const lockHolder = await connectAdmin();
    await lockHolder.query(`select pg_advisory_lock(${victimKey})`, [victim]);
    const probes = [
      { who: spy, label: 'manager corrigindo', code: 'P0001', message: 'shift_not_found', sql: correctSql, params: [vs.id, vs.started_at] },
      { who: spy, label: 'manager anulando', code: 'P0001', message: 'shift_not_found',
        sql: `select public.time_void_shift($1::uuid, 'Justificativa qualquer')::text as r`, params: [vs.id] },
      { who: peer, label: 'employee corrigindo', code: 'P0001', message: 'shift_not_found', sql: correctSql, params: [vs.id, vs.started_at] },
      { who: peer, label: 'employee anulando com p_request_id', code: 'P0001', message: 'shift_not_found',
        sql: `select public.time_void_shift($1::uuid, 'Justificativa qualquer', gen_random_uuid())::text as r`, params: [vs.id] },
      { who: spy, label: 'manager revisando', code: '42501', message: 'not_allowed',
        sql: `select public.time_review_shifts(jsonb_build_array(jsonb_build_object('id', $1::uuid, 'updated_at', $2::timestamptz)))::text as r`,
        params: [vs.id, vs.updated_at] },
      { who: spy, label: 'manager lançando jornada manual para a pessoa', code: '42501', message: 'not_allowed',
        sql: `select public.time_create_manual_shift($1::uuid, now() - interval '3 hours', now() - interval '2 hours', '[]'::jsonb, 'Justificativa qualquer')::text as r`,
        params: [victim] },
    ];
    const problems = [];
    for (const p of probes) {
      const c = await connectApi(p.who);
      await c.query('set statement_timeout = 3000');
      const t0 = Date.now();
      const r = await run(c, p.sql, p.params);
      const ms = Date.now() - t0;
      await c.end().catch(() => {});
      if (r.ok || r.code !== p.code || r.message !== p.message || ms >= 2000) problems.push(`${p.label}: ${outcome(r)} em ${ms} ms`);
    }
    check(
      problems.length === 0,
      `com o lock da pessoa preso, ${probes.length} chamadas de quem não pode respondem na hora (shift_not_found / not_allowed)`,
      problems.join(' || '),
    );
    const bc = await connectApi(boss);
    const bossPid = (await bc.query('select pg_backend_pid() as p')).rows[0].p;
    const pendingBoss = run(bc, correctSql, [vs.id, vs.started_at]);
    const bossWaits = await waitUntil(async () => (await q1(personLock, [victim, bossPid, false])).n === 1, 5000);
    check(bossWaits, 'controle: o super_admin (que pode) espera o lock da pessoa antes de corrigir');
    await lockHolder.query(`select pg_advisory_unlock(${victimKey})`, [victim]);
    await lockHolder.end();
    const br = await pendingBoss;
    check(br.ok, '… liberado, o super_admin corrige', outcome(br));
    await bc.end().catch(() => {});
    truth(
      (await auditCount(victim, 'correct')) === 1 && (await auditCount(victim, 'void')) === 0 && (await shiftCount(victim)) === 1,
      'verdade: só a correção do super_admin entrou no ponto da pessoa',
    );
  }

  // ── 14. request_id repetido em duas pessoas ao mesmo tempo ───────────────
  // §3.3 passo 7: o índice time_audit_events_request_uniq é a última barreira
  // da idempotência, e a violação dele vira request_id_conflict (P0001),
  // nunca 23505 cru. Só o super_admin age sobre duas pessoas com locks
  // diferentes: a chamada B não vê a linha ainda não confirmada de A, segue e
  // para no índice único; quando A confirma, B responde request_id_conflict e
  // desfaz o que tinha feito. A fica numa transação explícita para a ordem ser
  // determinística.
  note('mesmo request_id do super_admin para duas pessoas ao mesmo tempo: a unicidade vira request_id_conflict');
  const personA = await createUser('conc_ra', 'employee');
  const personB = await createUser('conc_rb', 'employee');
  const rsa = await createUser('conc_rsa', 'super_admin');
  const rid = crypto.randomUUID();
  const connA = await connectApi(rsa);
  const connB = await connectApi(rsa);
  const connBPid = (await connB.query('select pg_backend_pid() as p')).rows[0].p;
  const manualSql = `select public.time_create_manual_shift($1::uuid, '2026-10-07 08:00-03'::timestamptz, '2026-10-07 12:00-03'::timestamptz,
       '[]'::jsonb, 'Lançamento pelo administrador', $2::uuid)::text as r`;
  await connA.query('begin');
  const first = await run(connA, manualSql, [personA, rid]);
  check(first.ok, 'A: jornada manual da 1ª pessoa, ainda sem commit', outcome(first));
  const pendingB = connB.query(manualSql, [personB, rid]).then(
    (r) => ({ ok: true, value: r.rows[0]?.r ?? null }),
    (e) => ({ ok: false, code: e.code, message: e.message, detail: e.detail }),
  );
  const bWaits = await waitUntil(
    async () =>
      (await q1(`select count(*)::int as n from pg_locks where pid = $1 and not granted and locktype = 'transactionid'`, [connBPid])).n === 1,
    5000,
  );
  check(bWaits, 'B (mesmo request_id, 2ª pessoa) para no índice único esperando a transação de A');
  await connA.query(first.ok ? 'commit' : 'rollback');
  const second = await pendingB;
  check(
    !second.ok && second.code === 'P0001' && second.message === 'request_id_conflict'
      && second.detail === 'Esta ação já foi enviada com outro pedido. Atualize a tela.',
    'B → request_id_conflict (P0001 + frase de §3.7), não 23505',
    second.ok ? 'ok (deveria falhar)' : `${second.code} ${second.message} | ${second.detail ?? ''}`,
  );
  truth((await ridCount(rid)) === 1, 'verdade: 1 linha de auditoria com o request_id', `linhas: ${await ridCount(rid)}`);
  truth(
    (await shiftCount(personA)) === 1 && (await shiftCount(personB)) === 0,
    'verdade: só a jornada de A existe (B desfez a sua)',
    `A: ${await shiftCount(personA)}, B: ${await shiftCount(personB)}`,
  );
  await closeAll([connA, connB]);
}
