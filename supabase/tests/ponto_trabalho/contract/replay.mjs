#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// Replay do contrato app Dart × SQL real (sem rede, sem PostgREST, sem binário
// novo).
//
// Pega os pedidos HTTP que os repositórios Dart enviam (capturados pelos testes
// com servidor falso: fixtures/time_tracking_requests.json e
// fixtures/work_requests.json) e os executa contra a migration REAL num
// PostgreSQL 17.5 descartável, traduzindo cada um no SQL que o PostgREST
// geraria (postgrest.mjs) e rodando como o papel real (authenticator →
// authenticated/anon, request.jwt.claims). Em seguida confere:
//   1. estático: toda RPC, parâmetro nomeado, tipo, tabela, coluna, embutido e
//      grant que o Dart usa existe na migration com tipo compatível;
//   2. dinâmico: cada pedido dá o status/código esperado para o papel que o
//      envia, num roteiro com estado (bater ponto, corrigir, revisar, criar
//      tarefa, registrar, entregar…);
//   3. formato: toda chave que o fromJson do Dart lê está na resposta real, com
//      o formato esperado (instantes ISO com fuso, datas YYYY-MM-DD, lista
//      time_breaks, server_now nas RPCs, inteiros como número).
// O roteiro roda em duas bases, uma com a sessão em UTC (como o Supabase) e
// outra em Pacific/Kiritimati (+14:00), para provar que nada depende do fuso.
//
// Nunca fala com a produção: nenhuma CLI do Supabase, nenhuma rede externa.
//
// Uso (na pasta supabase/tests/ponto_trabalho):
//   npm run test:contract
//   node contract/replay.mjs --gravar <pasta>   grava as respostas reais (JSON)
//                                                para os testes Dart de parsing
//   PONTO_TZ=America/Sao_Paulo node contract/replay.mjs   um fuso só
//   PONTO_PORTAS=55640-55659 node contract/replay.mjs     faixa de portas
// ─────────────────────────────────────────────────────────────────────────────
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import EmbeddedPostgres from 'embedded-postgres';
import pg from 'pg';
import { EmulatorError, execute, findRelationship, loadSchemaCache, parseQuery, resolveFunction } from './postgrest.mjs';
import { dartInstantToJson, instantMicros, jsonValueFits, shapeFor, validateShape } from './shapes.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SUITE = path.resolve(HERE, '..');
const DEFAULT_MIGRATION = path.resolve(SUITE, '../../migrations/20261101170000_ponto_trabalho.sql');
// PONTO_MIGRATION / PONTO_FIXTURES: só para validar o próprio replay (mutantes).
const MIGRATION = process.env.PONTO_MIGRATION ? path.resolve(process.env.PONTO_MIGRATION) : DEFAULT_MIGRATION;
const STUB = path.join(SUITE, 'stub', 'supabase_stub.sql');
const FIXTURES = process.env.PONTO_FIXTURES ? path.resolve(process.env.PONTO_FIXTURES) : path.join(HERE, 'fixtures');
const TIMEZONES = process.env.PONTO_TZ ? [process.env.PONTO_TZ] : ['UTC', 'Pacific/Kiritimati'];
// Papéis que o app já modela e a profiles_role_check de hoje rejeita (contrato
// §6.2). Com PONTO_SIMULAR_PAPEIS_NOVOS=1 a constraint é ampliada SÓ neste
// banco descartável (como no npm test) e o roteiro dos papéis novos roda.
const SIMULATE_NEW_ROLES = process.env.PONTO_SIMULAR_PAPEIS_NOVOS === '1';
const NEW_ROLES = ['partner', 'sales_trial', 'employee_dev', 'sdr'];

const argv = process.argv.slice(2);
const SAVE_DIR = (() => {
  const i = argv.indexOf('--gravar');
  return i >= 0 ? path.resolve(argv[i + 1] ?? '') : null;
})();

// ── Saída ───────────────────────────────────────────────────────────────────
const stats = { ok: 0, fail: 0 };
const failures = [];
let where = '';

function line(text = '') {
  process.stdout.write(text + '\n');
}

function short(text, max = 300) {
  const s = String(text ?? '').replace(/\s+/g, ' ').trim();
  return s.length > max ? s.slice(0, max) + '…' : s;
}

function check(ok, label, detail) {
  if (ok) {
    stats.ok += 1;
    line(`  ok     ${label}`);
  } else {
    stats.fail += 1;
    failures.push(`${where}${label}${detail ? ' — ' + short(detail) : ''}`);
    line(`  FALHA  ${label}`);
    if (detail) line(`           ${short(detail, 600)}`);
  }
  return Boolean(ok);
}

// ── Capturas ────────────────────────────────────────────────────────────────
function loadCaptures() {
  const time = JSON.parse(fs.readFileSync(path.join(FIXTURES, 'time_tracking_requests.json'), 'utf8'));
  const work = JSON.parse(fs.readFileSync(path.join(FIXTURES, 'work_requests.json'), 'utf8'));
  const out = new Map();
  for (const [name, r] of Object.entries(time)) {
    if (name.startsWith('_')) continue;
    out.set(`time:${name}`, { feature: 'time', name, method: r.method, path: r.path, query: r.query ?? {}, body: r.body ?? null, headers: r.headers ?? {}, call: r.call });
  }
  for (const r of work.requests) {
    out.set(`work:${r.name}`, { feature: 'work', name: r.name, method: r.method, path: r.path, query: r.query ?? {}, body: r.body ?? null, headers: r.headers ?? {}, call: r.call });
  }
  return out;
}

// ── Pessoas (ids fixos = os das capturas) ───────────────────────────────────
const ID = {
  // ponto (test/features/time_tracking/support/time_fixtures.dart)
  ana: 'aaaaaaaa-0000-4000-8000-000000000001',
  bruno: 'aaaaaaaa-0000-4000-8000-000000000002',
  caio: 'aaaaaaaa-0000-4000-8000-000000000003',
  admin: 'aaaaaaaa-0000-4000-8000-000000000009',
  // trabalho (test/features/work/support/work_fixtures.dart)
  me: 'a0000000-0000-4000-8000-000000000001',
  other: 'a0000000-0000-4000-8000-000000000002',
  wadmin: 'a0000000-0000-4000-8000-000000000003',
  // papéis sem acesso ao ponto alheio / sem acesso ao módulo
  gestor: '99999999-0000-4000-8000-000000000001',
  cliente: '99999999-0000-4000-8000-000000000002',
  semperfil: '99999999-0000-4000-8000-000000000003',
};
// Papéis novos (só com PONTO_SIMULAR_PAPEIS_NOVOS=1).
const NEW_ID = {
  socio: '77777777-0000-4000-8000-000000000001',
  trial: '77777777-0000-4000-8000-000000000002',
  dev: '77777777-0000-4000-8000-000000000003',
  sdr: '77777777-0000-4000-8000-000000000004',
};
const NEW_ROLE = { socio: 'partner', trial: 'sales_trial', dev: 'employee_dev', sdr: 'sdr' };
const ROLE = {
  ana: 'employee', bruno: 'employee', caio: 'employee', admin: 'super_admin',
  me: 'employee', other: 'employee', wadmin: 'super_admin',
  gestor: 'manager', cliente: 'client', semperfil: null,
};
const S1 = 'bbbbbbbb-0000-4000-8000-000000000001';
const S2 = 'bbbbbbbb-0000-4000-8000-000000000002';
const S3 = 'bbbbbbbb-0000-4000-8000-000000000003';
const W_SHIFT = 'e0000000-0000-4000-8000-000000000001';
const W_SHIFT_VOIDED = 'e0000000-0000-4000-8000-000000000002';
const TASK = 'b0000000-0000-4000-8000-000000000001';
const TASK2 = 'b0000000-0000-4000-8000-000000000002';
const LOG = 'c0000000-0000-4000-8000-000000000001';
const LOG2 = 'c0000000-0000-4000-8000-000000000002';
const LOG_X = 'c0000000-0000-4000-8000-0000000000ff';
const DELIV = 'd0000000-0000-4000-8000-000000000001';
const DELIV2 = 'd0000000-0000-4000-8000-000000000002';

const SEED = `
insert into auth.users (id, email, raw_user_meta_data) values
  ('${ID.ana}',       'ana@contrato.test',       '{"full_name": "Ana Lima"}'),
  ('${ID.bruno}',     'bruno@contrato.test',     '{"full_name": "Bruno Souza"}'),
  ('${ID.caio}',      'caio@contrato.test',      '{"full_name": "Caio Prado"}'),
  ('${ID.admin}',     'alvaro@contrato.test',    '{"full_name": "Álvaro Admin"}'),
  ('${ID.me}',        'me@contrato.test',        '{"full_name": "Ana Souza"}'),
  ('${ID.other}',     'other@contrato.test',     '{"full_name": "bruno Lima"}'),
  ('${ID.wadmin}',    'wadmin@contrato.test',    '{}'),
  ('${ID.gestor}',    'gestor@contrato.test',    '{"full_name": "Gestora"}'),
  ('${ID.cliente}',   'cliente@contrato.test',   '{"full_name": "Cliente"}'),
  ('${ID.semperfil}', 'semperfil@contrato.test', '{"full_name": "Sem perfil"}');
${Object.entries(ROLE)
  .filter(([, r]) => r && r !== 'client')
  .map(([k, r]) => `update public.profiles set role = '${r}' where id = '${ID[k]}';`)
  .join('\n')}
delete from public.profiles where id = '${ID.semperfil}';

-- Jornadas com os ids das capturas (como postgres, só a preparação).
insert into public.time_shifts (id, user_id, started_at, ended_at, source) values
  ('${S1}', '${ID.ana}',  '2026-10-30T11:02:00Z', '2026-10-30T20:10:00Z', 'clock'),
  -- 31/10 22:00 → 01/11 02:00 em Brasília: atravessa a meia-noite.
  ('${S2}', '${ID.ana}',  '2026-11-01T01:00:00Z', '2026-11-01T05:00:00Z', 'clock'),
  -- aberta desde 01/11 07:30 em Brasília, em intervalo desde 10:10.
  ('${S3}', '${ID.caio}', '2026-11-01T10:30:00Z', null, 'clock'),
  ('${W_SHIFT}', '${ID.me}', '2026-11-01T11:00:00Z', '2026-11-01T20:00:00Z', 'clock'),
  ('${W_SHIFT_VOIDED}', '${ID.me}', '2026-10-31T11:00:00Z', '2026-10-31T20:00:00Z', 'clock');
update public.time_shifts
   set voided_at = '2026-10-31T21:00:00Z', voided_by = '${ID.me}',
       void_reason = 'Jornada aberta por engano', review_status = 'pending'
 where id = '${W_SHIFT_VOIDED}';
insert into public.time_breaks (id, shift_id, user_id, started_at, ended_at) values
  ('dddddddd-0000-4000-8000-000000000001', '${S1}', '${ID.ana}',  '2026-10-30T15:00:00Z', '2026-10-30T15:45:00Z'),
  ('dddddddd-0000-4000-8000-000000000003', '${S3}', '${ID.caio}', '2026-11-01T13:10:00Z', null);
`;

const WIDEN_ROLE_CHECK = `
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('super_admin', 'partner', 'manager', 'sales_trial', 'employee_dev', 'employee', 'sdr', 'client'));
`;
const NEW_SEED = `
insert into auth.users (id, email, raw_user_meta_data) values
${Object.keys(NEW_ID).map((k) => `  ('${NEW_ID[k]}', '${k}@contrato.test', '{"full_name": "Papel ${NEW_ROLE[k]}"}')`).join(',\n')};
${Object.keys(NEW_ID).map((k) => `update public.profiles set role = '${NEW_ROLE[k]}' where id = '${NEW_ID[k]}';`).join('\n')}
`;

function actor(alias) {
  if (alias === 'anon') return { role: 'anon' };
  return { role: 'authenticated', uid: ID[alias] ?? NEW_ID[alias] };
}

// ── Roteiro ─────────────────────────────────────────────────────────────────
// Cada passo: captura (feature:nome), quem envia, o resultado esperado e
// verificações do conteúdo. `remap` troca ids da captura (só ids gerados no
// cliente que precisam de outro valor no roteiro); `rewrite` troca valores
// gerados pelo SERVIDOR (updated_at) pelos reais, no formato do Dart.
const ok200 = { status: 200 };
const created = { status: 201 };
const p0001 = (message) => ({ status: 400, code: 'P0001', message });
const denied = (message) => ({ status: 403, code: '42501', ...(message ? { message } : {}) });

const ids = (rows) => (Array.isArray(rows) ? rows.map((r) => r.id) : []);
const sameInstant = (a, b) => {
  try {
    return instantMicros(a) === instantMicros(b);
  } catch {
    return false;
  }
};

const TIME_STEPS = [
  { c: 'fetchStatus', as: 'anon', expect: { status: 401, code: '42501' }, why: 'anon não executa as RPCs' },
  { c: 'fetchStatus', as: 'cliente', expect: denied('not_allowed') },
  { c: 'fetchStatus', as: 'semperfil', expect: denied('not_allowed'), why: 'papel desconhecido (sem perfil)' },
  { c: 'fetchStatus', as: 'ana', expect: ok200, check: (b, t) => t(b.open_shift === null, 'fora da jornada: open_shift null') },
  {
    c: 'clockIn', as: 'ana', expect: ok200,
    check: (b, t, ctx) => {
      ctx.anaShift = b.id;
      ctx.rpcKeys = Object.keys(b).filter((k) => k !== 'server_now').sort().join();
      t(b.user_id === ID.ana && b.ended_at === null && b.source === 'clock' && b.note === null && b.time_breaks.length === 0,
        'jornada aberta da própria pessoa, sem intervalos, nota null');
    },
  },
  { c: 'clockIn', as: 'ana', label: 'repetição com o mesmo p_request_id', expect: ok200, check: (b, t, ctx) => t(b.id === ctx.anaShift, 'idempotente: devolve a MESMA jornada') },
  { c: 'clockIn.withNote', as: 'ana', expect: p0001('shift_already_open'), detail: 'Você já tem uma jornada aberta.' },
  { c: 'startBreak', as: 'ana', expect: ok200, check: (b, t, ctx) => t(b.id === ctx.anaShift && b.time_breaks.filter((x) => x.ended_at === null).length === 1, 'um intervalo aberto') },
  {
    c: 'endBreak', as: 'ana', expect: ok200,
    check: (b, t, ctx) => {
      ctx.rpcBreakKeys = Object.keys(b.time_breaks[0] ?? {}).sort().join();
      t(b.time_breaks.length === 1 && b.time_breaks[0].ended_at !== null, 'intervalo encerrado');
    },
  },
  { c: 'clockOut', as: 'ana', expect: ok200, check: (b, t) => t(b.ended_at !== null && b.time_breaks.every((x) => x.ended_at !== null), 'jornada encerrada') },
  { c: 'clockIn.withNote', as: 'bruno', expect: ok200, check: (b, t) => t(b.note === 'Começando pelo cliente X' && b.user_id === ID.bruno, 'p_note gravado já aparado') },
  { c: 'startBreak', as: 'bruno', expect: ok200 },
  { c: 'clockOut', as: 'bruno', expect: p0001('break_open'), detail: 'Encerre o intervalo antes de registrar a saída.', why: 'p_close_open_break: false com intervalo aberto' },
  {
    c: 'clockOut.closeOpenBreak', as: 'bruno', expect: ok200,
    check: (b, t) => t(b.ended_at !== null && b.time_breaks.length === 1 && sameInstant(b.time_breaks[0].ended_at, b.ended_at) && b.note === 'Saída antes por consulta médica',
      'p_close_open_break: true fecha o intervalo no mesmo instante da saída; p_note da saída gravado'),
  },
  { c: 'fetchStatus', as: 'caio', expect: ok200, check: (b, t) => t(b.open_shift?.id === S3 && b.open_shift.time_breaks.length === 1 && b.open_shift.time_breaks[0].ended_at === null, 'jornada aberta em intervalo, com time_breaks') },
  {
    c: 'correctShift.openShift', as: 'caio', expect: ok200,
    check: (b, t) => t(b.id === S3 && b.ended_at === null && sameInstant(b.started_at, '2026-11-01T10:45:00Z') && b.time_breaks.length === 1 &&
      sameInstant(b.time_breaks[0].started_at, '2026-11-01T13:00:00Z') && b.time_breaks[0].ended_at === null && b.review_status === 'pending' && b.last_corrected_by === ID.caio,
      'p_ended_at null + intervalo com ended_at null: jornada continua aberta, pendente'),
  },
  { c: 'correctShift', as: 'gestor', expect: p0001('shift_not_found'), why: 'manager não corrige ponto alheio (oráculo fechado)' },
  {
    c: 'correctShift', as: 'ana', expect: ok200,
    check: (b, t) => t(b.id === S1 && b.review_status === 'pending' && sameInstant(b.ended_at, '2026-10-30T20:30:00Z') && b.time_breaks.length === 1 &&
      sameInstant(b.time_breaks[0].started_at, '2026-10-30T15:00:00Z') && sameInstant(b.time_breaks[0].ended_at, '2026-10-30T16:00:00Z'),
      'horários UTC "…Z" do Dart gravados; intervalos substituídos; pendente'),
  },
  { c: 'createManualShift.self', as: 'ana', expect: ok200, check: (b, t) => t(b.user_id === ID.ana && b.source === 'manual' && b.review_status === 'pending' && b.work_date === '2026-10-29' && b.time_breaks.length === 1, 'p_user_id null = a própria pessoa; manual, pendente') },
  { c: 'createManualShift.otherPerson', as: 'ana', expect: denied('not_allowed'), why: 'só o super_admin inclui jornada de outra pessoa' },
  {
    c: 'createManualShift.otherPerson', as: 'admin', expect: ok200,
    check: (b, t) => t(b.user_id === ID.bruno && b.review_status === 'reviewed' && b.reviewed_by === ID.admin && b.work_date === '2026-10-28' && b.time_breaks.length === 0,
      'super_admin: jornada da outra pessoa, já revisada; p_breaks [] aceito'),
  },
  { c: 'voidShift', as: 'ana', expect: ok200, check: (b, t) => t(b.id === S2 && b.voided_by === ID.ana && b.void_reason === 'Jornada aberta por engano no celular' && b.review_status === 'pending' && b.work_date === '2026-10-31', 'anulada; work_date = dia de início (atravessa a meia-noite)') },
  {
    c: 'fetchShifts.own', as: 'ana', expect: ok200,
    check: (b, t, ctx) => {
      t(b.every((r) => r.user_id === ID.ana), 'só jornadas da própria pessoa');
      t([S1, S2].every((id) => ids(b).includes(id)) && b.some((r) => r.source === 'manual'), 'inclui a corrigida, a anulada e a manual');
      t(b.every((r, i) => i === 0 || instantMicros(r.started_at) >= instantMicros(b[i - 1].started_at)), 'order=started_at.asc');
      t(b.every((r) => r.work_date >= '2026-10-26' && r.work_date <= '2026-11-01'), 'work_date=gte/lte com datas YYYY-MM-DD');
      t(b.every((r) => Object.keys(r).sort().join() === ctx.rpcKeys && r.time_breaks.every((x) => Object.keys(x).sort().join() === ctx.rpcBreakKeys)),
        'mesmas chaves na RPC (sem server_now) e no embedding select=*,time_breaks(*) (§3.4)', `rpc: ${ctx.rpcKeys} | rpc break: ${ctx.rpcBreakKeys}`);
    },
  },
  { c: 'fetchShifts.own', as: 'gestor', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: manager não vê o ponto alheio (0 linhas)') },
  {
    c: 'fetchShifts.team', as: 'admin', expect: ok200,
    check: (b, t) => t([ID.ana, ID.bruno, ID.caio].every((u) => b.some((r) => r.user_id === u)), 'super_admin vê o ponto de todos'),
  },
  { c: 'fetchShifts.team', as: 'gestor', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: manager sem filtro também não vê ninguém') },
  { c: 'fetchShifts.team', as: 'cliente', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: client vê 0 linhas') },
  {
    c: 'fetchPendingReview', as: 'admin', expect: ok200,
    check: (b, t, ctx) => {
      ctx.pending = b;
      t([S1, S2, S3].every((id) => ids(b).includes(id)) && b.every((r) => r.review_status === 'pending'), 'pendentes de todos (anulada e aberta incluídas)');
    },
  },
  { c: 'fetchPendingReview', as: 'ana', expect: ok200, check: (b, t) => t(b.length > 0 && b.every((r) => r.user_id === ID.ana), 'RLS: a pessoa só vê as próprias pendências') },
  { c: 'reviewShifts', as: 'admin', label: 'updated_at da captura (antigo)', expect: p0001('shift_changed'), why: 'o updated_at enviado não é o atual' },
  { c: 'reviewShifts', as: 'gestor', expect: denied('not_allowed') },
  {
    c: 'reviewShifts', as: 'admin', label: 'updated_at reais, ida e volta pelo DateTime do Dart',
    rewrite: (req, ctx) => {
      const body = structuredClone(req.body);
      body.p_shifts = body.p_shifts.map((item) => {
        const row = ctx.pending?.find((r) => r.id === item.id);
        if (!row) throw new Error(`jornada ${item.id} não veio em fetchPendingReview`);
        // TimeShift.fromJson(row).updatedAt → instantToJson (toUtc().toIso8601String()).
        return { ...item, updated_at: dartInstantToJson(row.updated_at) };
      });
      return { ...req, body };
    },
    expect: ok200,
    check: (b, t) => t(b === 2, 'revisa as 2 jornadas (o inteiro vem como número JSON)'),
  },
  {
    c: 'fetchAuditTrail', as: 'ana', expect: ok200,
    check: (b, t) => {
      t(b.every((e, i) => i === 0 || e.seq > b[i - 1].seq), 'order=seq.asc');
      const corr = b.find((e) => e.action === 'correct');
      t(corr && corr.actor_id === ID.ana && corr.reason === 'Esqueci de bater a saída no horário certo' &&
        sameInstant(corr.before?.ended_at, '2026-10-30T20:10:00Z') && sameInstant(corr.after?.ended_at, '2026-10-30T20:30:00Z'),
        'correção com autor, justificativa (aparada pelo Dart), antes e depois');
      const rev = b.find((e) => e.action === 'review');
      t(rev && rev.actor_id === ID.admin && rev.reason === 'Semana conferida', 'revisão com autor e nota');
    },
  },
  { c: 'fetchAuditTrail', as: 'gestor', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: manager não vê a auditoria alheia') },
  {
    c: 'fetchPeople', as: 'ana', expect: ok200,
    check: (b, t) => t(ids(b).includes(ID.ana) && ids(b).includes(ID.admin) && !ids(b).includes(ID.gestor), 'eu + quem mexeu no meu ponto'),
  },
  {
    c: 'fetchPeople', as: 'admin', expect: ok200,
    check: (b, t) => t(['ana', 'bruno', 'caio', 'admin', 'me', 'other', 'wadmin', 'gestor'].every((k) => ids(b).includes(ID[k])) &&
      !ids(b).includes(ID.cliente) && !ids(b).includes(ID.semperfil), 'super_admin: todos os internos, sem client nem sem perfil'),
  },
  { c: 'fetchPeople', as: 'cliente', expect: ok200, check: (b, t) => t(Array.isArray(b) && b.length === 0, 'client: conjunto vazio') },
];

const WORK_STEPS = [
  { c: 'fetchPeople', as: 'me', expect: ok200, check: (b, t) => t(b.length === 1 && b[0].id === ID.me && b[0].role === 'employee', 'sem tarefas: só eu') },
  {
    c: 'createTask.full', as: 'me', expect: created,
    check: (b, t) => t(b.id === TASK && b.created_by === ID.me && b.assignee_id === ID.me && b.status === 'todo' && b.priority === 'high' &&
      b.due_date === '2026-11-05' && b.completed_at === null, 'created_by do servidor; due_date YYYY-MM-DD; status padrão'),
  },
  {
    c: 'createTask.retry.insert_conflict', as: 'me', expect: { status: 409, code: '23505' },
    check: (e, t) => t(`${e.message} ${e.details ?? ''}`.includes('work_tasks_pkey'), 'mensagem cita work_tasks_pkey (o Dart só trata a repetição assim)', JSON.stringify(e)),
  },
  { c: 'createTask.retry.fetch_existing', as: 'me', expect: ok200, check: (b, t) => t(b.id === TASK, 'devolve a tarefa já criada') },
  { c: 'createTask.minimal_unassigned', as: 'me', remap: { [TASK]: TASK2 }, expect: denied(), why: 'não super_admin não cria sem responsável (RLS)' },
  { c: 'createTask.minimal_unassigned', as: 'wadmin', remap: { [TASK]: TASK2 }, expect: created, check: (b, t) => t(b.assignee_id === null && b.created_by === ID.wadmin && b.priority === 'medium', 'super_admin cria sem responsável') },
  { c: 'fetchTasks.mine.default', as: 'me', expect: ok200, check: (b, t) => t(ids(b).join() === TASK, 'minhas tarefas abertas') },
  { c: 'fetchTasks.createdByMe.priorities_due_range', as: 'me', expect: ok200, check: (b, t) => t(ids(b).join() === TASK, 'priority=in.(…) e due_date=gte/lte') },
  { c: 'fetchTask', as: 'me', expect: ok200, check: (b, t) => t(b.id === TASK, 'objeto único (.single())') },
  { c: 'fetchTask', as: 'other', expect: { status: 406, code: 'PGRST116' }, why: 'RLS esconde a tarefa alheia' },
  { c: 'fetchTasks.team.everything', as: 'wadmin', expect: ok200, check: (b, t) => t([TASK, TASK2].every((id) => ids(b).includes(id)), 'super_admin vê todas') },
  { c: 'fetchTasks.team.everything', as: 'me', expect: ok200, check: (b, t) => t(ids(b).join() === TASK, 'RLS: sem filtro, a pessoa só vê as suas') },
  { c: 'fetchTasks.team.everything', as: 'gestor', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: manager não vê tarefa alheia') },
  {
    c: 'addLog.full', as: 'me', expect: created,
    check: (b, t) => t(b.id === LOG && b.user_id === ID.me && b.shift_id === W_SHIFT && b.task_id === TASK && b.logged_on === '2026-11-01' && b.minutes_spent === 45,
      'user_id do servidor; jornada e tarefa vinculadas'),
  },
  {
    c: 'addLog.retry.insert_conflict', as: 'me', expect: { status: 409, code: '23505' },
    check: (e, t) => t(`${e.message} ${e.details ?? ''}`.includes('work_logs_pkey'), 'mensagem cita work_logs_pkey', JSON.stringify(e)),
  },
  { c: 'addLog.retry.fetch_existing', as: 'me', expect: ok200, check: (b, t) => t(b.id === LOG, 'devolve o registro já criado') },
  {
    c: 'addLog.minimal', as: 'me', remap: { [LOG]: LOG2 }, expect: created,
    check: (b, t, ctx) => t(b.task_id === null && b.shift_id === null && b.logged_on === ctx.businessToday, `logged_on omitido = hoje em Brasília (${ctx.businessToday})`),
  },
  { c: 'addLog.full', as: 'other', remap: { [LOG]: LOG_X }, expect: denied(), why: 'tarefa e jornada alheias (RLS)' },
  { c: 'fetchLogs.all_filters', as: 'me', expect: ok200, check: (b, t) => t(ids(b).join() === LOG, 'todos os filtros') },
  { c: 'fetchLogs.task_mine', as: 'me', expect: ok200, check: (b, t) => t(ids(b).join() === LOG, 'meus registros da tarefa') },
  { c: 'fetchLogs.task_all', as: 'wadmin', expect: ok200, check: (b, t) => t(ids(b).join() === LOG, 'super_admin vê o registro de outra pessoa') },
  { c: 'fetchLogs.by_shift', as: 'me', expect: ok200, check: (b, t) => t(ids(b).join() === LOG, 'registros da jornada') },
  { c: 'fetchLogs.by_shift', as: 'other', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: registro alheio invisível') },
  {
    c: 'addDeliverable.full', as: 'me', expect: created,
    check: (b, t) => t(b.id === DELIV && b.created_by === ID.me && b.work_log_id === LOG && b.url === 'https://exemplo.com/p.pdf', 'created_by do servidor; registro da mesma tarefa'),
  },
  {
    c: 'addDeliverable.retry.insert_conflict', as: 'me', expect: { status: 409, code: '23505' },
    check: (e, t) => t(`${e.message} ${e.details ?? ''}`.includes('work_deliverables_pkey'), 'mensagem cita work_deliverables_pkey', JSON.stringify(e)),
  },
  { c: 'addDeliverable.retry.fetch_existing', as: 'me', expect: ok200, check: (b, t) => t(b.id === DELIV, 'devolve a entrega já criada') },
  { c: 'addDeliverable.minimal', as: 'me', remap: { [DELIV]: DELIV2 }, expect: created, check: (b, t) => t(b.work_log_id === null && b.url === null && b.notes === null, 'só título') },
  {
    c: 'fetchDeliverables', as: 'me', expect: ok200,
    check: (b, t) => t(b.length === 2 && b.every((r, i) => i === 0 || instantMicros(r.created_at) <= instantMicros(b[i - 1].created_at)), 'order=created_at.desc'),
  },
  { c: 'updateTask.status_only', as: 'me', expect: ok200, check: (b, t) => t(b.status === 'in_progress' && b.completed_at === null, 'status pelo PATCH') },
  {
    c: 'updateTask.title_status_priority', as: 'me', expect: ok200,
    check: (b, t) => t(b.title === 'Proposta v2' && b.status === 'done' && b.priority === 'low' && typeof b.completed_at === 'string', 'quem criou muda título/status/prioridade; completed_at do servidor'),
  },
  { c: 'fetchTasks.mine.closed_only', as: 'me', expect: ok200, check: (b, t) => t(ids(b).join() === TASK, 'status=in.("done","canceled")') },
  { c: 'updateTask.clear_flags', as: 'me', expect: denied('task_field_not_allowed'), why: 'só o super_admin muda o responsável' },
  { c: 'updateTask.clear_flags', as: 'wadmin', expect: ok200, check: (b, t) => t(b.assignee_id === null && b.description === null && b.due_date === null, 'null do Dart limpa as colunas') },
  { c: 'updateTask.set_description_due_assignee', as: 'wadmin', expect: ok200, check: (b, t) => t(b.assignee_id === ID.other && b.due_date === '2026-11-09' && b.description === 'Nova descrição', 'reatribuição e prazo YYYY-MM-DD') },
  { c: 'updateTask.status_only', as: 'other', expect: ok200, check: (b, t) => t(b.status === 'in_progress' && b.completed_at === null, 'responsável que não criou muda só o status') },
  // canceled (entrar e sair) é de quem criou e do super_admin. O app espelha
  // isso em WorkAccess.allowedStatuses (não oferece ao responsável que não criou).
  { c: 'updateTask.cancel', as: 'other', expect: denied('task_field_not_allowed'), why: 'responsável que não criou não cancela' },
  { c: 'updateTask.cancel', as: 'me', expect: ok200, check: (b, t) => t(b.status === 'canceled' && b.completed_at === null, 'quem criou cancela') },
  { c: 'updateTask.status_only', as: 'other', label: 'tirar do cancelamento', expect: denied('task_field_not_allowed'), why: 'responsável que não criou não tira do cancelamento' },
  { c: 'updateTask.status_only', as: 'me', label: 'criador reabre', expect: ok200, check: (b, t) => t(b.status === 'in_progress', 'quem criou tira do cancelamento') },
  { c: 'fetchTasks.team.assignee_overdue', as: 'wadmin', expect: ok200, check: (b, t) => t(b.every((r) => r.due_date < '2026-11-01'), 'due_date=lt.<hoje>') },
  { c: 'fetchTasks.mine.empty_statuses', as: 'other', remap: { [ID.me]: ID.other }, expect: ok200, check: (b, t) => t(ids(b).join() === TASK, 'sem filtro de status') },
  {
    c: 'fetchHistory', as: 'me', expect: ok200,
    check: (b, t) => {
      t(b.every((e, i) => i === 0 || e.seq > b[i - 1].seq), 'order=seq.asc');
      const createdEv = b.find((e) => e.action === 'created');
      t(createdEv && ['title', 'status', 'priority', 'assignee_id', 'due_date'].every((k) => k in createdEv.changes), 'created: retrato de title/status/priority/assignee_id/due_date');
      const logEv = b.find((e) => e.action === 'log_added');
      t(logEv && Object.keys(logEv.changes).join() === 'log_id' && logEv.changes.log_id === LOG, 'log_added: só {log_id}');
      t(b.some((e) => e.action === 'deliverable_added' && e.changes.deliverable_id === DELIV && e.changes.title === 'Proposta final'), 'deliverable_added: {deliverable_id, title}');
      t(b.some((e) => e.action === 'updated' && e.changes.status?.to === 'done'), 'updated: {campo: {from, to}}');
    },
  },
  { c: 'fetchHistory', as: 'gestor', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: histórico de tarefa alheia invisível') },
  {
    c: 'fetchPeople', as: 'me', expect: ok200,
    check: (b, t) => t([ID.me, ID.other, ID.wadmin].every((id) => ids(b).includes(id)) && b.find((p) => p.id === ID.wadmin)?.full_name === '', 'eu + responsável + autor dos eventos; nome vazio vira ""'),
  },
  {
    c: 'fetchRecentShifts.default', as: 'me', expect: ok200,
    check: (b, t) => t(ids(b).join() === W_SHIFT && !ids(b).includes(W_SHIFT_VOIDED), 'voided_at=is.null tira a anulada; work_date=gte'),
  },
  { c: 'fetchRecentShifts.today', as: 'me', expect: ok200, check: (b, t) => t(ids(b).join() === W_SHIFT, 'só hoje') },
  { c: 'fetchRecentShifts.today', as: 'other', expect: ok200, check: (b, t) => t(b.length === 0, 'user_id=eq.<eu> de outra pessoa: 0 linhas') },
];

// ── Papéis novos (partner, sales_trial, employee_dev, sdr) ─────────────────
const T_DEV = 'b0000000-0000-4000-8000-0000000000d1';
const T_SDR = 'b0000000-0000-4000-8000-0000000000d2';
const T_SDR_OWN = 'b0000000-0000-4000-8000-0000000000d3';
const L_SDR = 'c0000000-0000-4000-8000-0000000000d1';

const NEW_ROLE_TIME_STEPS = [
  ...['socio', 'trial', 'dev', 'sdr'].map((who) => ({
    c: 'fetchStatus', as: who, expect: ok200, check: (b, t) => t(b.open_shift === null, `${NEW_ROLE[who]} é interno: usa o ponto`),
  })),
  { c: 'clockIn', as: 'sdr', expect: ok200, check: (b, t) => t(b.user_id === NEW_ID.sdr, 'sdr bate o próprio ponto') },
  { c: 'clockOut', as: 'sdr', expect: ok200, check: (b, t) => t(b.user_id === NEW_ID.sdr && b.ended_at !== null, 'sdr registra a saída') },
  { c: 'fetchShifts.team', as: 'socio', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: partner não vê o ponto alheio') },
  { c: 'fetchPendingReview', as: 'socio', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: partner não vê pendências alheias') },
  { c: 'fetchShifts.own', as: 'dev', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: employee_dev não vê o ponto alheio') },
  { c: 'correctShift', as: 'socio', expect: p0001('shift_not_found'), why: 'partner não corrige ponto alheio' },
  { c: 'voidShift', as: 'trial', expect: p0001('shift_not_found'), why: 'sales_trial não anula ponto alheio' },
  { c: 'reviewShifts', as: 'socio', expect: denied('not_allowed') },
  { c: 'createManualShift.otherPerson', as: 'socio', expect: denied('not_allowed') },
  { c: 'fetchAuditTrail', as: 'dev', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: auditoria alheia invisível') },
  { c: 'fetchPeople', as: 'socio', expect: ok200, check: (b, t) => t(ids(b).join() === NEW_ID.socio, 'partner sem tarefas: só ele') },
];

const NEW_ROLE_WORK_STEPS = [
  { c: 'createTask.full', as: 'sdr', remap: { [TASK]: T_SDR_OWN, [ID.me]: NEW_ID.sdr }, expect: denied(), why: 'sdr não cria tarefa (RLS)' },
  { c: 'createTask.full', as: 'dev', remap: { [TASK]: T_DEV, [ID.me]: NEW_ID.dev }, expect: created, check: (b, t) => t(b.created_by === NEW_ID.dev, 'employee_dev cria para si') },
  { c: 'createTask.full', as: 'wadmin', remap: { [TASK]: T_SDR, [ID.me]: NEW_ID.sdr }, expect: created, check: (b, t) => t(b.assignee_id === NEW_ID.sdr, 'super_admin atribui ao sdr') },
  { c: 'fetchTasks.mine.default', as: 'sdr', remap: { [ID.me]: NEW_ID.sdr }, expect: ok200, check: (b, t) => t(ids(b).join() === T_SDR, 'sdr vê a tarefa atribuída') },
  { c: 'updateTask.cancel', as: 'sdr', remap: { [TASK]: T_SDR }, expect: denied('task_field_not_allowed'), why: 'sdr nunca usa canceled' },
  { c: 'updateTask.title_status_priority', as: 'sdr', remap: { [TASK]: T_SDR }, expect: denied('task_field_not_allowed'), why: 'sdr só muda o status' },
  { c: 'updateTask.status_only', as: 'sdr', remap: { [TASK]: T_SDR }, expect: ok200, check: (b, t) => t(b.status === 'in_progress', 'sdr muda o status') },
  { c: 'addLog.minimal', as: 'sdr', remap: { [LOG]: L_SDR }, expect: created, check: (b, t) => t(b.user_id === NEW_ID.sdr, 'sdr registra o que fez') },
  { c: 'fetchTasks.team.everything', as: 'socio', expect: ok200, check: (b, t) => t(b.length === 0, 'RLS: partner não vê tarefa alheia') },
  { c: 'fetchPeople', as: 'sdr', expect: ok200, check: (b, t) => t(ids(b).includes(NEW_ID.sdr) && ids(b).includes(ID.wadmin), 'sdr: ele + quem criou a tarefa dele') },
];

// ── Checagem estática (catálogo) ────────────────────────────────────────────
async function staticCheck(admin, cache, cap) {
  const problems = [];
  const m = /^\/rest\/v1\/(rpc\/)?([A-Za-z_][A-Za-z0-9_]*)$/.exec(cap.path);
  if (!m) return [`caminho não reconhecido: ${cap.path}`];
  if (m[1]) {
    let fn;
    try {
      fn = resolveFunction(cache, m[2], Object.keys(cap.body ?? {}));
    } catch (e) {
      return [`${e.pgrst?.code ?? ''} ${e.message}${e.pgrst?.hint ? ' | ' + e.pgrst.hint : ''}`];
    }
    for (const [k, v] of Object.entries(cap.body ?? {})) {
      const arg = fn.args.find((a) => a.name === k);
      if (!jsonValueFits(v, arg.type)) problems.push(`parâmetro ${k} ${arg.type} não aceita o valor JSON ${JSON.stringify(v)}`);
    }
    const priv = await admin.query(
      `select has_function_privilege('authenticated', $1::oid, 'execute') as auth, has_function_privilege('anon', $1::oid, 'execute') as anon`,
      [fn.oid],
    );
    if (!priv.rows[0].auth) problems.push(`authenticated sem EXECUTE em public.${fn.name}`);
    if (priv.rows[0].anon) problems.push(`anon com EXECUTE em public.${fn.name}`);
    const expectedReturn = {
      fetchStatus: 'jsonb', reviewShifts: 'integer', fetchPeople: 'record',
    }[cap.name.split('.')[0]] ?? 'jsonb';
    if (fn.rettype !== expectedReturn) problems.push(`public.${fn.name} devolve ${fn.rettype}; o Dart espera ${expectedReturn}`);
    if (cap.name.split('.')[0] === 'fetchPeople') {
      if (!fn.retset) problems.push('ponto_people precisa devolver conjunto (o Dart espera lista)');
      const cols = await admin.query(`select pg_get_function_result($1::oid) as r`, [fn.oid]);
      if (!/TABLE\(id uuid, full_name text, role text\)/.test(cols.rows[0].r)) problems.push(`ponto_people devolve ${cols.rows[0].r}`);
    }
    return problems;
  }
  const table = cache.tables.get(m[2]);
  if (!table) return [`tabela public.${m[2]} não existe`];
  const has = (t, c) => cache.tables.get(t)?.columns.some((x) => x.name === c);
  let parsed;
  try {
    parsed = parseQuery(cap.query);
  } catch (e) {
    return [`query que o emulador não entende: ${e.message}`];
  }
  const walk = (tname, items) => {
    for (const it of items ?? []) {
      if (it.kind === 'col' && !has(tname, it.name)) problems.push(`select: coluna ${tname}.${it.name} não existe`);
      if (it.kind === 'embed') {
        try {
          findRelationship(cache, tname, it.name);
        } catch (e) {
          problems.push(`embutido ${it.name}: ${e.message}`);
          continue;
        }
        walk(it.name, it.items);
        for (const o of parsed.embedOrder.get(it.name) ?? []) if (!has(it.name, o.col)) problems.push(`order de ${it.name}: coluna ${o.col} não existe`);
      }
    }
  };
  walk(table.name, parsed.select);
  for (const f of parsed.filters) if (!has(table.name, f.col)) problems.push(`filtro: coluna ${table.name}.${f.col} não existe`);
  for (const o of parsed.order) if (!has(table.name, o.col)) problems.push(`order: coluna ${table.name}.${o.col} não existe`);
  const tpriv = await admin.query(
    `select has_table_privilege('authenticated', $1, 'select') as auth, has_table_privilege('anon', $1, 'select') as anon`,
    [`public.${table.name}`],
  );
  if (!tpriv.rows[0].auth) problems.push(`authenticated sem SELECT em ${table.name}`);
  if (tpriv.rows[0].anon) problems.push(`anon com SELECT em ${table.name}`);
  if (cap.method === 'POST' || cap.method === 'PATCH') {
    const privilege = cap.method === 'POST' ? 'INSERT' : 'UPDATE';
    for (const [k, v] of Object.entries(cap.body ?? {})) {
      const col = table.columns.find((c) => c.name === k);
      if (!col) {
        problems.push(`corpo: coluna ${table.name}.${k} não existe`);
        continue;
      }
      if (!jsonValueFits(v, col.type)) problems.push(`corpo: ${k} ${col.type} não aceita ${JSON.stringify(v)}`);
      const p = await admin.query(`select has_column_privilege('authenticated', $1, $2, $3) as ok`, [`public.${table.name}`, k, privilege]);
      if (!p.rows[0].ok) problems.push(`authenticated sem ${privilege} na coluna ${table.name}.${k}`);
    }
  }
  return problems;
}

// ── Postgres descartável ────────────────────────────────────────────────────
function portCandidates() {
  const spec = process.env.PONTO_PORTAS;
  if (!spec) return [0, 0, 0, 0, 0];
  const [a, b] = spec.split('-').map(Number);
  const out = [];
  for (let p = a; p <= (b || a); p += 1) out.push(p);
  return out;
}

function portIsFree(p) {
  return new Promise((resolve) => {
    const srv = net.createServer();
    srv.unref();
    srv.once('error', () => resolve(null));
    srv.listen(p, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ponto-contrato-pg-'));
const dataDir = path.join(tmpRoot, 'data');
const adminPassword = crypto.randomBytes(18).toString('hex');
const apiPassword = crypto.randomBytes(18).toString('hex');
const pgLog = [];
let db = null;
let port = null;

async function boot() {
  let initialised = false;
  let lastError = null;
  for (const candidate of portCandidates()) {
    const p = await portIsFree(candidate);
    if (p == null) continue;
    const instance = new EmbeddedPostgres({
      databaseDir: dataDir,
      user: 'postgres',
      password: adminPassword,
      port: p,
      persistent: false,
      initdbFlags: ['--encoding=UTF8', '--locale=C'],
      onLog: (msg) => pgLog.push(String(msg)),
      onError: (msg) => pgLog.push(String(msg)),
      postgresFlags: ['-c', 'listen_addresses=127.0.0.1', '-c', 'unix_socket_directories=', '-c', 'fsync=off', '-c', 'synchronous_commit=off', '-c', 'full_page_writes=off'],
    });
    try {
      if (!initialised) {
        await instance.initialise();
        initialised = true;
      }
      await instance.start();
      db = instance;
      port = p;
      return;
    } catch (e) {
      lastError = e;
    }
  }
  throw new Error(`não foi possível subir o Postgres local: ${lastError ?? 'nenhuma porta livre'}\n${pgLog.slice(-20).join('')}`);
}

async function shutdown() {
  try {
    if (db) await db.stop();
  } catch {
    // o processo já pode ter saído
  }
  db = null;
  fs.rmSync(tmpRoot, { recursive: true, force: true });
}

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, async () => {
    await shutdown();
    process.exit(130);
  });
}

async function connect(database, { user = 'postgres', password = adminPassword, timezone }) {
  const c = new pg.Client({ host: '127.0.0.1', port, user, password, database, application_name: 'ponto-contrato' });
  c.on('error', () => {});
  await c.connect();
  await c.query(`set timezone = '${timezone}'`);
  await c.query('set statement_timeout = 60000');
  return c;
}

// ── Execução de um roteiro ──────────────────────────────────────────────────
function applyRemap(cap, remap) {
  if (!remap) return cap;
  let text = JSON.stringify(cap);
  for (const [from, to] of Object.entries(remap)) text = text.split(from).join(to);
  return JSON.parse(text);
}

async function runSteps({ feature, steps, captures, api, cache, ctx, used, saved }) {
  for (const step of steps) {
    const key = `${feature}:${step.c}`;
    const base = captures.get(key);
    const title = `${step.c} como ${step.as}${step.label ? ` (${step.label})` : ''}`;
    line(`  -- ${title}${step.why ? ` — ${step.why}` : ''}`);
    if (!base) {
      check(false, `${title}: captura inexistente`, key);
      continue;
    }
    used.add(key);
    let req = applyRemap(base, step.remap);
    try {
      if (step.rewrite) req = step.rewrite(req, ctx);
    } catch (e) {
      check(false, `${title}: preparação do pedido`, e.message);
      continue;
    }
    let res;
    try {
      res = await execute(api, cache, req, actor(step.as));
    } catch (e) {
      check(false, `${title}: ${e instanceof EmulatorError ? 'emulador' : 'execução'}`, e.message);
      continue;
    }
    const exp = step.expect;
    const got = res.error ? `${res.status} ${res.error.code} ${res.error.message}` : `${res.status}`;
    const statusOk =
      res.status === exp.status &&
      (exp.code == null || res.error?.code === exp.code) &&
      (exp.message == null || res.error?.message === exp.message) &&
      (exp.code != null || !res.error);
    check(statusOk, `${title}: ${exp.status}${exp.code ? ' ' + exp.code : ''}${exp.message ? ' ' + exp.message : ''}`, statusOk ? null : `obtido ${got}${res.error?.details ? ' | ' + res.error.details : ''}`);
    if (statusOk && step.detail) check(res.error?.details === step.detail, `${title}: detail pt-BR do contrato §3.7`, `obtido ${res.error?.details}`);
    const tcheck = (ok, label, detail) => check(ok, `${title}: ${label}`, ok ? null : detail ?? JSON.stringify(res.body ?? res.error)?.slice(0, 400));
    if (statusOk && !res.error) {
      const shape = shapeFor(feature, step.c);
      const problems = validateShape(shape, res.body);
      check(problems.length === 0, `${title}: formato que o fromJson do Dart lê (${shape})`, problems.slice(0, 8).join(' | '));
    }
    if (statusOk && step.check) {
      try {
        step.check(res.error ?? res.body, tcheck, ctx);
      } catch (e) {
        check(false, `${title}: verificação`, e.stack);
      }
    }
    saved.push({
      step: title,
      capture: step.c,
      as: step.as,
      role: ROLE[step.as] ?? NEW_ROLE[step.as] ?? (step.as === 'anon' ? 'anon' : null),
      // ids da captura trocados neste passo (o teste Dart refaz a chamada com eles)
      remap: step.remap ?? {},
      request: { method: req.method, path: req.path, query: req.query, body: req.body },
      status: res.status,
      ...(res.error ? { error: res.error } : { body: res.body }),
    });
  }
}

async function runDatabase(timezone, index, captures, admin0) {
  const dbname = `contrato_${index}`;
  await admin0.query(`create database ${dbname}`);
  const admin = await connect(dbname, { timezone });
  where = `[${timezone}] `;
  line('');
  line(`== Base ${dbname}: fuso da sessão ${timezone}`);
  await admin.query('begin');
  await admin.query(fs.readFileSync(STUB, 'utf8'));
  await admin.query('commit');
  await admin.query('begin');
  await admin.query(fs.readFileSync(MIGRATION, 'utf8'));
  await admin.query('commit');
  check(true, 'stub do Supabase + migration 20261101170000_ponto_trabalho.sql aplicados');
  await admin.query('begin');
  await admin.query(SEED);
  await admin.query('commit');
  const roles = await admin.query(`select count(*)::int as n from public.profiles where id = any($1::uuid[])`, [Object.values(ID)]);
  check(roles.rows[0].n === Object.values(ID).length - 1, 'pessoas semeadas (super_admin, manager, employee, client e uma sem perfil)');
  // O schema atual rejeita os papéis novos (pendência global §6.2).
  const rejected = [];
  for (const role of NEW_ROLES) {
    try {
      await admin.query('begin');
      await admin.query(`update public.profiles set role = $1 where id = $2`, [role, ID.gestor]);
      await admin.query('rollback');
    } catch (e) {
      await admin.query('rollback').catch(() => {});
      if (e.code === '23514') rejected.push(role);
      else throw e;
    }
  }
  const runNewRoles = rejected.length === 0 || SIMULATE_NEW_ROLES;
  if (runNewRoles) {
    await admin.query('begin');
    if (rejected.length) await admin.query(WIDEN_ROLE_CHECK);
    await admin.query(NEW_SEED);
    await admin.query('commit');
    check(true, rejected.length
      ? `PONTO_SIMULAR_PAPEIS_NOVOS=1: profiles_role_check ampliada SÓ neste banco; semeados ${NEW_ROLES.join(', ')}`
      : `o schema já aceita ${NEW_ROLES.join(', ')}; semeados`);
  }
  const cache = await loadSchemaCache(admin);

  line('');
  line(`== [${timezone}] estático: cada captura contra o catálogo da migration`);
  for (const [key, cap] of captures) {
    const problems = await staticCheck(admin, cache, cap);
    check(problems.length === 0, `${key} → ${cap.method} ${cap.path.replace('/rest/v1', '')}: nomes, tipos e grants existem na migration`, problems.join(' | '));
  }

  const api = await connect(dbname, { user: 'authenticator', password: apiPassword, timezone });
  const ctx = {
    businessToday: (await admin.query(`select ((now() at time zone 'America/Sao_Paulo')::date)::text as d`)).rows[0].d,
  };
  const used = new Set();
  const saved = { time: [], work: [] };
  line('');
  line(`== [${timezone}] ponto: pedidos do SupabaseTimeTrackingRepository`);
  await runSteps({ feature: 'time', steps: TIME_STEPS, captures, api, cache, ctx, used, saved: saved.time });
  line('');
  line(`== [${timezone}] trabalho: pedidos do SupabaseWorkRepository`);
  await runSteps({ feature: 'work', steps: WORK_STEPS, captures, api, cache, ctx, used, saved: saved.work });

  line('');
  if (!runNewRoles) {
    line(
      `== [${timezone}] papéis novos: PULADO — o schema atual (profiles_role_check) rejeita ${rejected.join(', ')}. ` +
        'Rode PONTO_SIMULAR_PAPEIS_NOVOS=1 npm run test:contract para simular só neste banco descartável.',
    );
  } else {
    // Fora do arquivo gravado para o Dart (que cobre os papéis aceitos hoje).
    line(`== [${timezone}] papéis novos (${NEW_ROLES.join(', ')})`);
    await runSteps({ feature: 'time', steps: NEW_ROLE_TIME_STEPS, captures, api, cache, ctx, used, saved: [] });
    await runSteps({ feature: 'work', steps: NEW_ROLE_WORK_STEPS, captures, api, cache, ctx, used, saved: [] });
  }

  line('');
  const unused = [...captures.keys()].filter((k) => !used.has(k));
  check(unused.length === 0, `toda captura do Dart tem passo no roteiro (${captures.size} capturas)`, `sem passo: ${unused.join(', ')}`);
  await api.end();
  await admin.end();
  where = '';
  return saved;
}

function selfTestDartInstants() {
  // Pares conferidos pelos testes Dart (supabase_time_tracking_repository_test.dart).
  const pairs = [
    ['2026-10-30T20:31:02.123456+00:00', '2026-10-30T20:31:02.123456Z'],
    ['2026-10-31T06:00:00-03:00', '2026-10-31T09:00:00.000Z'],
    ['2026-11-01T11:02:13.5+00:00', '2026-11-01T11:02:13.500Z'],
    ['2026-11-02T13:15:37.12345+14:00', '2026-11-01T23:15:37.123450Z'],
  ];
  for (const [input, expected] of pairs) {
    const got = dartInstantToJson(input);
    check(got === expected, `conversão de instante igual à do Dart: ${input} → ${expected}`, `obtido ${got}`);
  }
}

async function main() {
  line('Replay do contrato app Dart × SQL real (PostgreSQL local descartável; nunca produção)');
  if (MIGRATION !== DEFAULT_MIGRATION) line(`AVISO: PONTO_MIGRATION definido: testando ${MIGRATION} (só para validar o replay)`);
  if (FIXTURES !== path.join(HERE, 'fixtures')) line(`AVISO: PONTO_FIXTURES definido: capturas de ${FIXTURES} (só para validar o replay)`);
  const captures = loadCaptures();
  line(`Capturas: ${[...captures.values()].filter((c) => c.feature === 'time').length} do ponto, ${[...captures.values()].filter((c) => c.feature === 'work').length} do trabalho`);
  line('');
  line('== conversão de instantes (DateTime do Dart)');
  selfTestDartInstants();

  await boot();
  line(`Postgres local na porta ${port} (dados em ${dataDir}, removidos no fim)`);
  const admin0 = await connect('postgres', { timezone: 'UTC' });
  line(`Versão do servidor: ${(await admin0.query('show server_version')).rows[0].server_version}`);
  // authenticator é do cluster: o stub cria, a senha é só desta execução.
  await admin0.query(`do $$ begin if not exists (select 1 from pg_roles where rolname = 'authenticator') then create role authenticator login noinherit; end if; end $$`);
  await admin0.query(`alter role authenticator password '${apiPassword}'`);

  const results = [];
  for (const [i, tz] of TIMEZONES.entries()) {
    results.push({ timezone: tz, saved: await runDatabase(tz, i + 1, captures, admin0) });
  }
  await admin0.end();

  if (SAVE_DIR) {
    fs.mkdirSync(SAVE_DIR, { recursive: true });
    const about =
      'Respostas REAIS da migration 20261101170000_ponto_trabalho.sql aos pedidos capturados do app, ' +
      'geradas por supabase/tests/ponto_trabalho/contract/replay.mjs (PostgreSQL 17.5 local, PostgREST emulado). ' +
      'Regerar: cd supabase/tests/ponto_trabalho && node contract/replay.mjs --gravar <pasta>.';
    for (const feature of ['time', 'work']) {
      const file = path.join(SAVE_DIR, feature === 'time' ? 'time_tracking_real_responses.json' : 'work_real_responses.json');
      const data = {
        _about: about,
        runs: results.map((r) => ({ session_timezone: r.timezone, responses: r.saved[feature] })),
      };
      fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
      line(`Respostas reais gravadas em ${file}`);
    }
  }
  return summary();
}

function summary() {
  line('');
  line('== Resumo');
  line(`${stats.ok + stats.fail} verificação(ões): ${stats.ok} ok, ${stats.fail} falha(s)`);
  if (failures.length) {
    line('Falhas:');
    for (const f of failures) line(`  - ${short(f, 500)}`);
  }
  return stats.fail > 0 ? 1 : 0;
}

let code = 1;
try {
  code = await main();
} catch (e) {
  line('');
  line(`ERRO no replay: ${e?.code ?? ''} ${e?.message ?? e}${e?.detail ? ' | ' + e.detail : ''}${e?.where ? ' | ' + e.where : ''}`);
  if (e?.stack) line(e.stack);
  if (pgLog.length) line(pgLog.slice(-30).join(''));
  code = 1;
} finally {
  await shutdown();
}
process.exit(code);
