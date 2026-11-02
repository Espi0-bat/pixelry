#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// Runner dos testes do banco do módulo Ponto e Trabalho.
//
// Sobe um PostgreSQL 17.5 descartável (embedded-postgres, porta livre,
// diretório temporário, persistent:false), carrega a baseline local
// compartilhada (supabase/tests/local/supabase_baseline.sql) e os helpers,
// aplica TODAS as migrations do app móvel (CRM, Ponto, Financeiro e a de
// integração 20261102120000) comparando um retrato do catálogo, reaplica as
// que declaram idempotência, roda cada sql/**/*.test.sql numa conexão própria
// (begin … rollback) e depois concurrency.test.mjs (autocommit, conexões
// separadas). A suíte testa o módulo no ESTADO INTEGRADO: os papéis novos
// são aceitos e a proteção de profiles é a compartilhada.
//
// Nunca fala com a produção: não usa a CLI do Supabase nem rede externa.
//
// Uso:
//   npm test                                   suíte padrão
//   node run.mjs --somente-harness             só baseline + helpers + sql/00_* (dispensa as migrations)
//   node run.mjs --filtro 14_                  só os arquivos cujo caminho contém o texto
//   node run.mjs --sem-concorrencia            pula concurrency.test.mjs
// Saída: uma linha por asserção, resumo no fim, exit 1 se houver falha real.
// ─────────────────────────────────────────────────────────────────────────────
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
import EmbeddedPostgres from 'embedded-postgres';
import pg from 'pg';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const MIGRATIONS_DIR = path.resolve(HERE, '../../migrations');
const MODULE_MIGRATION = path.join(MIGRATIONS_DIR, '20261101170000_ponto_trabalho.sql');
// PONTO_MIGRATION: só para validar o próprio harness; substitui o arquivo do
// módulo na lista, mantendo as demais migrations.
const MODULE_OVERRIDE = process.env.PONTO_MIGRATION ? path.resolve(process.env.PONTO_MIGRATION) : null;
const BASELINE = path.resolve(HERE, '../local/supabase_baseline.sql');

// Mesma regra de supabase/tests/local/list_migrations.sh: todas as 202611*
// em ordem de nome; a reaplicação pula as migrations do CRM 150000/150100/
// 150200/150400, que criam policies e funções sem "if exists" de propósito.
function listMigrations() {
  return fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((f) => /^202611\d+_.*\.sql$/.test(f))
    .sort()
    .map((f) => path.join(MIGRATIONS_DIR, f))
    .map((f) => (f === MODULE_MIGRATION && MODULE_OVERRIDE ? MODULE_OVERRIDE : f));
}
const NOT_REAPPLIED = /^(20261101150000|20261101150100|20261101150200|20261101150400)_/;
function isReapplied(f) {
  return !NOT_REAPPLIED.test(path.basename(f));
}
const HELPERS = path.join(HERE, 'sql', '_helpers.sql');
const SQL_DIR = path.join(HERE, 'sql');
const CONCURRENCY = path.join(HERE, 'concurrency.test.mjs');

// Fuso da sessão de propósito diferente de Brasília e de UTC: qualquer cálculo
// de data que dependa do fuso da sessão (em vez de America/Sao_Paulo explícito)
// aparece como falha.
const SESSION_TZ = process.env.PONTO_TZ || 'Pacific/Kiritimati';
const NEW_ROLES = ['partner', 'sales_trial', 'employee_dev', 'sdr'];

const argv = process.argv.slice(2);
const HARNESS_ONLY = argv.includes('--somente-harness');
const SKIP_CONCURRENCY = argv.includes('--sem-concorrencia');
const FILTER = (() => {
  const i = argv.indexOf('--filtro');
  return i >= 0 ? argv[i + 1] ?? '' : null;
})();

// ── Saída e contagem ────────────────────────────────────────────────────────
const stats = { ok: 0, fail: 0, expected: 0, skipped: 0, warnings: [] };
const failures = [];
let currentGroup = 'padrão';
let currentFile = '';

function line(text = '') {
  process.stdout.write(text + '\n');
}

function short(text, max = 400) {
  if (text == null) return '';
  const s = String(text).replace(/\s+/g, ' ').trim();
  return s.length > max ? s.slice(0, max) + '…' : s;
}

/** Registra uma asserção. `expectedFailure` = arquivo de sql/global/. */
function record({ ok, label, detail, as, kind = 'assert' }, { expectedFailure = false } = {}) {
  const tag = as ? `[${as}] ` : '';
  if (ok) {
    stats.ok += 1;
    line(`  ok     ${tag}${label}`);
    return;
  }
  if (expectedFailure) {
    stats.expected += 1;
    line(`  FALHA ESPERADA (pendência global) ${tag}${label}`);
    if (detail) line(`           ${short(detail)}`);
    return;
  }
  stats.fail += 1;
  const where = currentFile ? `${currentFile}: ` : '';
  failures.push(`${where}${label}${detail ? ' — ' + short(detail, 300) : ''}`);
  line(`  FALHA  ${tag}${label}`);
  if (detail) line(`           ${short(detail)}`);
}

function warn(text) {
  stats.warnings.push(text);
  line(`  AVISO  ${text}`);
}

function header(text) {
  line('');
  line(`== ${text}`);
}

// ── Postgres descartável ────────────────────────────────────────────────────
async function freePort() {
  return new Promise((resolve, reject) => {
    const srv = net.createServer();
    srv.unref();
    srv.on('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ponto-trabalho-pg-'));
const dataDir = path.join(tmpRoot, 'data');
const adminPassword = crypto.randomBytes(18).toString('hex');
const apiPassword = crypto.randomBytes(18).toString('hex');
const pgLog = [];
let db = null;
let port = null;
// Retrato do catálogo logo depois da 2ª aplicação (base da 3ª, no fim).
let catalogAfterMigration = null;

function pgOptions(p) {
  return {
    databaseDir: dataDir,
    user: 'postgres',
    password: adminPassword,
    port: p,
    persistent: false,
    // UTF8 como o Supabase (sem isto o embedded-postgres cria o cluster em
    // SQL_ASCII: char_length contaria bytes e os textos pt-BR seriam só bytes).
    // Locale C para o resultado não depender do sistema operacional.
    initdbFlags: ['--encoding=UTF8', '--locale=C'],
    onLog: (m) => pgLog.push(String(m)),
    onError: (m) => pgLog.push(String(m)),
    postgresFlags: [
      '-c', 'listen_addresses=127.0.0.1',
      '-c', 'unix_socket_directories=',
      '-c', 'fsync=off',
      '-c', 'synchronous_commit=off',
      '-c', 'full_page_writes=off',
      '-c', 'max_connections=200',
    ],
  };
}

async function boot() {
  let initialised = false;
  let lastError = null;
  for (let attempt = 1; attempt <= 5; attempt += 1) {
    const p = await freePort();
    const instance = new EmbeddedPostgres(pgOptions(p));
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
  throw new Error(`não foi possível subir o Postgres local: ${lastError ?? 'erro desconhecido'}\n${pgLog.slice(-20).join('')}`);
}

async function shutdown() {
  try {
    if (db) await db.stop();
  } catch {
    // o processo já pode ter saído
  }
  db = null;
  try {
    fs.rmSync(tmpRoot, { recursive: true, force: true });
  } catch {
    // diretório temporário: o sistema limpa depois
  }
}

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, async () => {
    await shutdown();
    process.exit(130);
  });
}

async function connect({ user = 'postgres', password = adminPassword, timeoutMs = 60000 } = {}) {
  const c = new pg.Client({
    host: '127.0.0.1',
    port,
    user,
    password,
    database: 'postgres',
    application_name: 'ponto-trabalho-tests',
  });
  c.on('error', () => {});
  await c.connect();
  await c.query(`set timezone = '${SESSION_TZ}'`);
  await c.query(`set statement_timeout = ${Number(timeoutMs)}`);
  return c;
}

function describePgError(e) {
  if (!e) return '';
  const parts = [`${e.code ?? ''} ${e.message ?? e}`.trim()];
  if (e.detail) parts.push(`detail: ${e.detail}`);
  if (e.hint) parts.push(`hint: ${e.hint}`);
  if (e.where) parts.push(`where: ${e.where}`);
  if (e.position) parts.push(`posição: ${e.position}`);
  return parts.join(' | ');
}

/** Linha/coluna de uma posição (1-based, em caracteres) dentro do texto. */
function positionToLine(text, position) {
  const pos = Number(position);
  if (!pos || !text) return null;
  const before = text.slice(0, pos - 1);
  const lineNo = before.split('\n').length;
  const srcLine = text.split('\n')[lineNo - 1] ?? '';
  return `linha ${lineNo}: ${srcLine.trim().slice(0, 200)}`;
}

// ── Retrato do catálogo ─────────────────────────────────────────────────────
// Tudo de public/private/extensions/auth: relações (ACL, RLS, opções, view),
// colunas (tipo, default, gerada, ACL), constraints, índices, policies,
// triggers, funções (definição + ACL + dono), tipos, extensões, privilégios
// padrão e atributos/participação dos papéis da API. ACLs são ordenadas para o
// retrato não depender da ordem de concessão.
const SNAPSHOT_SQL = `
with sch as (
  select oid, nspname from pg_namespace
   where nspname in ('public', 'private', 'extensions', 'auth', 'crm_private', 'finance_private')
),
items(kind, name, parent, detail) as (
  select 'schema', n.nspname, '',
         coalesce((select string_agg(a::text, ',' order by a::text) from unnest(n.nspacl) a), '')
    from pg_namespace n where n.nspname in ('public', 'private', 'extensions', 'auth', 'crm_private', 'finance_private')
  union all
  select 'rel', s.nspname || '.' || c.relname, '',
         c.relkind::text || '|acl=' || coalesce((select string_agg(a::text, ',' order by a::text) from unnest(c.relacl) a), '')
         || '|rls=' || c.relrowsecurity || '|force=' || c.relforcerowsecurity
         || '|opts=' || coalesce(array_to_string(c.reloptions, ','), '')
         || '|owner=' || c.relowner::regrole::text
         || case when c.relkind in ('v', 'm') then '|def=' || pg_get_viewdef(c.oid) else '' end
    from pg_class c join sch s on s.oid = c.relnamespace
   where c.relkind in ('r', 'p', 'v', 'm', 'S', 'f')
  union all
  select 'col', s.nspname || '.' || c.relname || '.' || a.attname, s.nspname || '.' || c.relname,
         format_type(a.atttypid, a.atttypmod) || '|nn=' || a.attnotnull
         || '|def=' || coalesce(pg_get_expr(d.adbin, d.adrelid), '')
         || '|gen=' || a.attgenerated::text || '|ident=' || a.attidentity::text || '|pos=' || a.attnum
         || '|acl=' || coalesce((select string_agg(x::text, ',' order by x::text) from unnest(a.attacl) x), '')
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join sch s on s.oid = c.relnamespace
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attnum > 0 and not a.attisdropped and c.relkind in ('r', 'p', 'v', 'm', 'f')
  union all
  select 'con', s.nspname || '.' || c.relname || '.' || co.conname, s.nspname || '.' || c.relname,
         co.contype::text || '|' || pg_get_constraintdef(co.oid) || '|defer=' || co.condeferrable || '|valid=' || co.convalidated
    from pg_constraint co join pg_class c on c.oid = co.conrelid join sch s on s.oid = c.relnamespace
  union all
  select 'idx', s.nspname || '.' || ic.relname, ts.nspname || '.' || tc.relname, pg_get_indexdef(i.indexrelid)
    from pg_index i
    join pg_class ic on ic.oid = i.indexrelid
    join sch s on s.oid = ic.relnamespace
    join pg_class tc on tc.oid = i.indrelid
    join pg_namespace ts on ts.oid = tc.relnamespace
  union all
  select 'pol', s.nspname || '.' || c.relname || '.' || p.polname, s.nspname || '.' || c.relname,
         p.polcmd::text || '|perm=' || p.polpermissive
         || '|roles=' || coalesce((select string_agg(case when r = 0 then 'public' else r::regrole::text end, ',' order by 1) from unnest(p.polroles) r), '')
         || '|using=' || coalesce(pg_get_expr(p.polqual, p.polrelid), '')
         || '|check=' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
    from pg_policy p join pg_class c on c.oid = p.polrelid join sch s on s.oid = c.relnamespace
  union all
  select 'trg', s.nspname || '.' || c.relname || '.' || t.tgname, s.nspname || '.' || c.relname,
         pg_get_triggerdef(t.oid) || '|en=' || t.tgenabled::text
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join sch s on s.oid = c.relnamespace
   where not t.tgisinternal
  union all
  select 'fn', s.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', '',
         p.prokind::text || '|' || case when p.prokind in ('f', 'p') then pg_get_functiondef(p.oid) else '' end
         || '|acl=' || coalesce((select string_agg(a::text, ',' order by a::text) from unnest(p.proacl) a), 'DEFAULT')
         || '|owner=' || p.proowner::regrole::text
    from pg_proc p join sch s on s.oid = p.pronamespace
  union all
  select 'type', s.nspname || '.' || t.typname, '',
         t.typtype::text || '|acl=' || coalesce((select string_agg(a::text, ',' order by a::text) from unnest(t.typacl) a), '')
    from pg_type t join sch s on s.oid = t.typnamespace
   where t.typtype in ('e', 'd', 'r', 'm')
      or (t.typtype = 'c' and exists (select 1 from pg_class rc where rc.oid = t.typrelid and rc.relkind = 'c'))
  union all
  select 'comment', 'rel:' || s.nspname || '.' || c.relname || coalesce('.' || a.attname, ''), s.nspname || '.' || c.relname, d.description
    from pg_description d
    join pg_class c on d.classoid = 'pg_class'::regclass and d.objoid = c.oid
    join sch s on s.oid = c.relnamespace
    left join pg_attribute a on a.attrelid = c.oid and a.attnum = d.objsubid and d.objsubid > 0
  union all
  select 'comment', 'fn:' || s.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', '', d.description
    from pg_description d
    join pg_proc p on d.classoid = 'pg_proc'::regclass and d.objoid = p.oid
    join sch s on s.oid = p.pronamespace
  union all
  select 'ext', e.extname, '', e.extversion || '|' || e.extnamespace::regnamespace::text from pg_extension e
  union all
  select 'defacl', coalesce(d.defaclnamespace::regnamespace::text, '*') || '.' || d.defaclrole::regrole::text || '.' || d.defaclobjtype::text, '',
         coalesce((select string_agg(a::text, ',' order by a::text) from unnest(d.defaclacl) a), '')
    from pg_default_acl d
  union all
  select 'role', r.rolname, '',
         'super=' || r.rolsuper || '|inherit=' || r.rolinherit || '|login=' || r.rolcanlogin
         || '|bypassrls=' || r.rolbypassrls || '|createrole=' || r.rolcreaterole
         || '|member_of=' || coalesce((select string_agg(g.rolname, ',' order by g.rolname)
                                         from pg_auth_members m join pg_roles g on g.oid = m.roleid
                                        where m.member = r.oid), '')
         || '|config=' || coalesce((select array_to_string(rs.setconfig, ',') from pg_db_role_setting rs
                                     where rs.setrole = r.oid and rs.setdatabase = 0), '')
    from pg_roles r where r.rolname in ('anon', 'authenticated', 'service_role', 'authenticator', 'postgres')
)
select kind, name, parent, coalesce(detail, '') as detail from items order by kind, name
`;

async function snapshot(c) {
  const r = await c.query(SNAPSHOT_SQL);
  const map = new Map();
  for (const row of r.rows) map.set(`${row.kind}|${row.name}`, row);
  return map;
}

function diffSnapshots(a, b) {
  const added = [];
  const removed = [];
  const changed = [];
  for (const [k, row] of b) {
    if (!a.has(k)) added.push(row);
    else if (a.get(k).detail !== row.detail) changed.push({ before: a.get(k), after: row });
  }
  for (const [k, row] of a) if (!b.has(k)) removed.push(row);
  return { added, removed, changed };
}

function printDiff({ added, removed, changed }, limit = 40) {
  const out = [];
  for (const r of removed) out.push(`- ${r.kind} ${r.name}`);
  for (const r of added) out.push(`+ ${r.kind} ${r.name}`);
  for (const { before, after } of changed) {
    out.push(`~ ${after.kind} ${after.name}`);
    out.push(`    antes:  ${short(before.detail, 300)}`);
    out.push(`    depois: ${short(after.detail, 300)}`);
  }
  for (const l of out.slice(0, limit * 3)) line(`           ${l}`);
  if (out.length > limit * 3) line(`           … e mais ${out.length - limit * 3} linha(s)`);
}

const DATA_SQL = `
select
  (select md5(coalesce(string_agg(u::text, '|' order by u.id), '')) from auth.users u) as users,
  (select md5(coalesce(string_agg(concat_ws('|', p.id, p.role, p.full_name, p.email, p.company_name), '|' order by p.id), ''))
     from public.profiles p) as profiles,
  (select count(*) from auth.users)::int as user_count
`;

// ── Execução dos arquivos SQL ───────────────────────────────────────────────
function listTests(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.test.sql'))
    .sort()
    .map((f) => path.join(dir, f));
}

function rel(p) {
  return path.relative(HERE, p);
}

function matchesFilter(p) {
  return FILTER == null || rel(p).includes(FILTER);
}

async function baselineUsers(admin) {
  return (await admin.query('select count(*)::int as n from auth.users')).rows[0].n;
}

/**
 * Roda um arquivo .test.sql numa conexão própria, dentro de begin … rollback.
 * `expectedFailure`: arquivo de sql/global/ (falha esperada, não derruba).
 */
async function runSqlFile(admin, file, { expectedFailure = false } = {}) {
  currentFile = rel(file);
  header(`${currentFile}${expectedFailure ? '  (pendência global: falha esperada)' : ''}`);
  const text = fs.readFileSync(file, 'utf8');
  const before = await baselineUsers(admin);
  const c = await connect();
  let asserts = 0;
  let failed = 0;
  let realFailuresInFile = 0;
  let done = false;
  c.on('notice', (n) => {
    const msg = n.message ?? '';
    if (!msg.startsWith('PT ')) return;
    let ev;
    try {
      ev = JSON.parse(msg.slice(3));
    } catch {
      return;
    }
    if (ev.kind === 'note') {
      line(`  -- ${ev.label}`);
      return;
    }
    if (ev.kind === 'done') {
      done = true;
      return;
    }
    asserts += 1;
    // Em sql/global/, só a asserção que falha "do jeito esperado" é falha
    // esperada. Preparação que falhou ou erro inesperado (objeto do módulo
    // ausente, erro de SQL) é falha real: senão um módulo quebrado passaria
    // despercebido como "pendência global".
    const realProblem = ev.kind === 'setup' || /^erro inesperado/.test(ev.detail ?? '');
    if (!ev.ok && !realProblem) failed += 1;
    if (!ev.ok && realProblem) realFailuresInFile += 1;
    record(ev, { expectedFailure: expectedFailure && !realProblem });
  });

  let error = null;
  try {
    await c.query('begin');
    await c.query(text);
  } catch (e) {
    error = e;
  }
  try {
    await c.query('rollback');
  } catch {
    // conexão pode ter caído
  }
  await c.end().catch(() => {});

  if (error) {
    const where = positionToLine(text, error.position);
    failed += 1;
    record(
      {
        ok: false,
        label: 'arquivo interrompido por erro fora de um helper',
        detail: `${describePgError(error)}${where ? ' | ' + where : ''}`,
        kind: 'setup',
      },
      { expectedFailure: false },
    );
  } else if (!done) {
    failed += 1;
    record({ ok: false, label: 'arquivo não chegou ao tests.done()', kind: 'setup' });
  }
  if (asserts === 0) {
    record({ ok: false, label: 'arquivo sem nenhuma asserção', kind: 'setup' });
  }

  const after = await baselineUsers(admin);
  if (after !== before) {
    record({
      ok: false,
      label: 'arquivo deixou estado no banco (faltou rollback?)',
      detail: `auth.users: ${before} → ${after}`,
      kind: 'setup',
    });
  }

  if (expectedFailure) {
    if (failed === 0 && !error && realFailuresInFile === 0) {
      warn(
        `${currentFile}: todas as asserções passaram. A pendência global parece resolvida; ` +
          'remova a marcação (mova o arquivo de sql/global/ para sql/).',
      );
    } else {
      line(`  => pendência global confirmada (${failed} asserção(ões) falhando como esperado)`);
    }
  }
  currentFile = '';
}

// ── Migration ───────────────────────────────────────────────────────────────
async function applyMigration(admin, text, label) {
  try {
    await admin.query('begin');
    await admin.query(text);
    await admin.query('commit');
    return null;
  } catch (e) {
    await admin.query('rollback').catch(() => {});
    const where = positionToLine(text, e.position);
    return `${describePgError(e)}${where ? ' | ' + where : ''}`;
  }
}

const MODULE_TABLES = ['time_shifts', 'time_breaks', 'time_audit_events', 'work_tasks', 'work_logs', 'work_deliverables', 'work_task_events'];

// Objetos PREEXISTENTES (da baseline) que o conjunto de migrations altera de
// propósito. Qualquer outra diferença em objeto preexistente é falha. Chave:
// `${kind}|${name}` do retrato.
const EXPECTED_PREEXISTING_CHANGES = new Set([
  // CRM 20261101150000: papéis do app e ajuste de acesso por pessoa.
  'col|public.profiles.crm_access',
  'con|public.profiles.profiles_crm_access_check',
  'con|public.profiles.profiles_role_check',
  'comment|rel:public.profiles.crm_access',
  // CRM 20261101150300: lead novo do site entra no CRM.
  'trg|public.leads.leads_to_crm_trg',
  // Financeiro 20261101174510/174520: índices e auditoria em invoices.
  'idx|public.idx_invoices_due_date',
  'idx|public.idx_invoices_paid_at',
  'trg|public.invoices.finance_audit_invoice_trg',
  // Integração 20261102120000: profiles sem INSERT/DELETE para authenticated
  // (ACL da relação), guarda compartilhada, helpers globais e visibilidade.
  'rel|public.profiles',
  'trg|public.profiles.profiles_guard_insert_role',
  'pol|public.profiles.team_members_see_each_other',
  'fn|public.is_admin()',
  'fn|public.is_team()',
  // (os comentários novos em is_admin/is_team não contam: comentário de função
  // não tem relação-mãe no retrato.)
]);

async function migrationPhase(admin) {
  const files = listMigrations();
  const reapply = files.filter(isReapplied);
  header(`migrations do app móvel (${files.length} arquivos; ${reapply.length} reaplicados como prova de idempotência)`);
  currentFile = 'migration';
  for (const f of files) line(`           ${path.basename(f)}${isReapplied(f) ? '' : '   (não reaplicada: não declara idempotência)'}`);

  // A CLI roda cada migration na própria transação: nenhum arquivo abre nem
  // fecha transação (contrato §3.0).
  const txLines = [];
  for (const f of files) {
    const text = fs.readFileSync(f, 'utf8');
    text
      .split('\n')
      .map((l, i) => ({ l: l.replace(/--.*$/, ''), i: i + 1 }))
      .filter(({ l }) => /^\s*(begin|commit|rollback|start\s+transaction|end\s+transaction)\s*;/i.test(l))
      .forEach(({ l, i }) => txLines.push(`${path.basename(f)} linha ${i}: ${l.trim()}`));
  }
  record({
    ok: txLines.length === 0,
    label: 'nenhuma migration tem begin/commit explícito',
    detail: txLines.join('; '),
  });

  // Dados preexistentes: algumas pessoas reais na baseline antes das migrations.
  await admin.query(`
    begin;
    select tests.create_user('semente_admin', 'super_admin');
    select tests.create_user('semente_gestor', 'manager');
    select tests.create_user('semente_func', 'employee');
    select tests.create_user('semente_cliente', 'client');
    commit;
  `);
  const data0 = (await admin.query(DATA_SQL)).rows[0];
  const s0 = await snapshot(admin);

  for (const f of files) {
    const err = await applyMigration(admin, fs.readFileSync(f, 'utf8'), '1ª');
    record({ ok: !err, label: `1ª aplicação: ${path.basename(f)}`, detail: err });
    if (err) {
      currentFile = '';
      return false;
    }
  }
  const s1 = await snapshot(admin);
  const data1 = (await admin.query(DATA_SQL)).rows[0];

  // Objetos preexistentes: nada da baseline some; o que muda ou ganha algo
  // pendurado (policy/trigger/coluna/índice em profiles, leads, invoices…) é
  // exatamente a lista EXPECTED_PREEXISTING_CHANGES.
  const d01 = diffSnapshots(s0, s1);
  const s0Rels = new Set([...s0.values()].filter((r) => r.kind === 'rel').map((r) => r.name));
  const touched = {
    added: d01.added.filter((r) => r.parent && s0Rels.has(r.parent)),
    removed: d01.removed,
    changed: d01.changed,
  };
  record({
    ok: touched.removed.length === 0,
    label: 'nenhum objeto preexistente removido',
    detail: touched.removed.map((r) => `${r.kind} ${r.name}`).join(', '),
  });
  const touchedKeys = new Set([
    ...touched.added.map((r) => `${r.kind}|${r.name}`),
    ...touched.changed.map(({ after }) => `${after.kind}|${after.name}`),
  ]);
  const unexpected = [...touchedKeys].filter((k) => !EXPECTED_PREEXISTING_CHANGES.has(k)).sort();
  const missing = [...EXPECTED_PREEXISTING_CHANGES].filter((k) => !touchedKeys.has(k)).sort();
  record({
    ok: unexpected.length === 0 && missing.length === 0,
    label: `mudanças em objetos preexistentes: exatamente as ${EXPECTED_PREEXISTING_CHANGES.size} previstas (profiles, leads, invoices, is_admin, is_team)`,
    detail: [unexpected.length ? `inesperadas: ${unexpected.join(', ')}` : '', missing.length ? `previstas mas ausentes: ${missing.join(', ')}` : '']
      .filter(Boolean)
      .join(' | ') || null,
  });
  if (unexpected.length) {
    printDiff({
      added: touched.added.filter((r) => unexpected.includes(`${r.kind}|${r.name}`)),
      removed: [],
      changed: touched.changed.filter(({ after }) => unexpected.includes(`${after.kind}|${after.name}`)),
    });
  }
  line(`           (${d01.added.length} objeto(s) novo(s) no catálogo)`);

  record({
    ok: data1.users === data0.users && data1.profiles === data0.profiles,
    label: 'migrations não alteram dados preexistentes (auth.users, profiles: id, papel, nome, e-mail, empresa)',
  });

  // 2ª aplicação: só as que declaram idempotência; o catálogo e os dados não
  // podem mudar.
  for (const f of reapply) {
    const err = await applyMigration(admin, fs.readFileSync(f, 'utf8'), '2ª');
    record({ ok: !err, label: `2ª aplicação seguida sem erro (idempotente): ${path.basename(f)}`, detail: err });
    if (err) {
      currentFile = '';
      return false;
    }
  }
  const s2 = await snapshot(admin);
  catalogAfterMigration = s2;
  const d12 = diffSnapshots(s1, s2);
  const n = d12.added.length + d12.removed.length + d12.changed.length;
  record({
    ok: n === 0,
    label: 'retrato do catálogo idêntico após a 2ª aplicação (definições + ACLs)',
    detail: n ? `${n} diferença(s); ver abaixo` : null,
  });
  if (n) printDiff(d12);
  const data2 = (await admin.query(DATA_SQL)).rows[0];
  record({
    ok: data2.users === data0.users && data2.profiles === data0.profiles,
    label: '2ª aplicação não altera dados',
  });

  // Tabelas do módulo nascem vazias (nenhum dado semeado pela migration do
  // Ponto; o CRM semeia etapas de funil de propósito e fica fora daqui).
  const newTables = [...s1.values()]
    .filter((r) => r.kind === 'rel' && !s0.has(`rel|${r.name}`) && /^[rp]\|/.test(r.detail) && /^public\.(time_|work_)/.test(r.name))
    .map((r) => r.name);
  const nonEmpty = [];
  for (const t of newTables) {
    const [schema, table] = t.split('.');
    const q = await admin.query(`select count(*)::int as n from ${pg.escapeIdentifier(schema)}.${pg.escapeIdentifier(table)}`);
    if (q.rows[0].n !== 0) nonEmpty.push(`${t}=${q.rows[0].n}`);
  }
  record({
    ok: newTables.length === MODULE_TABLES.length && nonEmpty.length === 0,
    label: `a migration do Ponto não semeia dados (${newTables.length} tabela(s) nova(s) vazias)`,
    detail: nonEmpty.join(', ') || (newTables.length !== MODULE_TABLES.length ? `tabelas: ${newTables.join(', ')}` : null),
  });

  // Remove as sementes: os testes partem de um banco sem pessoas.
  try {
    await admin.query(`delete from auth.users where email like 'semente\\_%'`);
  } catch (e) {
    record({ ok: false, label: 'remover pessoas semente após as migrations', detail: describePgError(e) });
  }
  currentFile = '';
  return true;
}

// ── 3ª aplicação, com dados ─────────────────────────────────────────────────
// A 1ª e a 2ª aplicação rodam com as tabelas do módulo vazias. No fim da
// suíte há linhas confirmadas (a concorrência roda em autocommit) e mais uma
// semente em cada uma das 7 tabelas: aplicar o arquivo de novo não pode falhar,
// mudar o catálogo nem tocar em nenhuma linha (§3.0 "deixar o mesmo estado").
// Antes, confere que nenhum arquivo de teste deixou sobra no catálogo (os
// grants temporários do sql/34 têm de ter sumido com o rollback).

const SEED_FOR_REAPPLY = `
do $$
declare
  v_user  uuid;
  v_shift uuid;
  v_task  uuid;
  v_log   uuid;
begin
  insert into auth.users (email, raw_user_meta_data)
  values ('reaplicar.' || gen_random_uuid() || '@teste.local', '{"full_name": "Semente da 3ª aplicação"}')
  returning id into v_user;
  update public.profiles set role = 'employee' where id = v_user;
  insert into public.time_shifts (user_id, started_at, ended_at, source, review_status)
  values (v_user, now() - interval '3 hours', now() - interval '1 hour', 'manual', 'pending')
  returning id into v_shift;
  insert into public.time_breaks (shift_id, user_id, started_at, ended_at)
  values (v_shift, v_user, now() - interval '2 hours', now() - interval '110 minutes');
  insert into public.time_audit_events (shift_id, subject_user_id, actor_id, action, reason, after)
  values (v_shift, v_user, v_user, 'create_manual', 'Semente da 3ª aplicação', '{}'::jsonb);
  insert into public.work_tasks (title, assignee_id, created_by)
  values ('Semente da 3ª aplicação', v_user, v_user)
  returning id into v_task;
  insert into public.work_logs (user_id, task_id, shift_id, summary)
  values (v_user, v_task, v_shift, 'Semente da 3ª aplicação')
  returning id into v_log;
  insert into public.work_deliverables (task_id, work_log_id, created_by, title, url)
  values (v_task, v_log, v_user, 'Semente da 3ª aplicação', 'https://exemplo.test/semente');
end;
$$;
`;

async function moduleData(admin) {
  const out = {};
  for (const t of MODULE_TABLES) {
    const r = await admin.query(
      `select count(*)::int as n, md5(coalesce(string_agg(x::text, '|' order by x.id), '')) as h from public.${pg.escapeIdentifier(t)} x`,
    );
    out[t] = r.rows[0];
  }
  return out;
}

async function thirdApplication(admin) {
  header('migrations: 3ª aplicação (as idempotentes), com dados confirmados nas tabelas do módulo');
  currentFile = 'migration (3ª aplicação)';
  const reapply = listMigrations().filter(isReapplied);

  const sBefore = await snapshot(admin);
  if (catalogAfterMigration) {
    const d = diffSnapshots(catalogAfterMigration, sBefore);
    const n = d.added.length + d.removed.length + d.changed.length;
    record({
      ok: n === 0,
      label: 'os testes não deixaram sobra no catálogo (grants/objetos temporários desfeitos no rollback)',
      detail: n ? `${n} diferença(s); ver abaixo` : null,
    });
    if (n) printDiff(d);
  }

  try {
    await admin.query(SEED_FOR_REAPPLY);
  } catch (e) {
    record({ ok: false, label: 'semente para a 3ª aplicação', detail: describePgError(e), kind: 'setup' });
    currentFile = '';
    return;
  }
  const dataBefore = await moduleData(admin);
  const empty = MODULE_TABLES.filter((t) => dataBefore[t].n === 0);
  record({
    ok: empty.length === 0,
    label: `as 7 tabelas do módulo têm linhas antes da 3ª aplicação (${MODULE_TABLES.map((t) => `${t}=${dataBefore[t].n}`).join(', ')})`,
    detail: empty.length ? `vazias: ${empty.join(', ')}` : null,
  });

  for (const f of reapply) {
    const err = await applyMigration(admin, fs.readFileSync(f, 'utf8'), '3ª');
    record({ ok: !err, label: `3ª aplicação, com dados, sem erro: ${path.basename(f)}`, detail: err });
    if (err) {
      currentFile = '';
      return;
    }
  }
  const sAfter = await snapshot(admin);
  const d = diffSnapshots(sBefore, sAfter);
  const n = d.added.length + d.removed.length + d.changed.length;
  record({
    ok: n === 0,
    label: 'migration: retrato do catálogo idêntico após a 3ª aplicação',
    detail: n ? `${n} diferença(s); ver abaixo` : null,
  });
  if (n) printDiff(d);
  const dataAfter = await moduleData(admin);
  const changed = MODULE_TABLES.filter((t) => dataAfter[t].n !== dataBefore[t].n || dataAfter[t].h !== dataBefore[t].h);
  record({
    ok: changed.length === 0,
    label: 'migration: 3ª aplicação não altera nenhuma linha das tabelas do módulo',
    detail: changed.length ? `alteradas: ${changed.join(', ')}` : null,
  });
  currentFile = '';
}

// ── Principal ───────────────────────────────────────────────────────────────
async function main() {
  line('Testes do banco — Ponto e Trabalho (PostgreSQL local descartável; nunca produção)');
  const moduleFile = listMigrations().find((f) => path.basename(f) === path.basename(MODULE_MIGRATION) || f === MODULE_OVERRIDE);
  if (!HARNESS_ONLY && (!moduleFile || !fs.existsSync(moduleFile))) {
    line('');
    line(`ERRO: migration do módulo não encontrada: ${MODULE_OVERRIDE ?? MODULE_MIGRATION}`);
    line('A suíte testa essa migration; sem ela não há o que testar.');
    line('Para validar só o harness (baseline + helpers): node run.mjs --somente-harness');
    return 1;
  }
  if (!fs.existsSync(BASELINE)) {
    line('');
    line(`ERRO: baseline não encontrada: ${BASELINE}`);
    return 1;
  }

  if (MODULE_OVERRIDE) {
    warn(`PONTO_MIGRATION definido: testando ${MODULE_OVERRIDE} no lugar de ${MODULE_MIGRATION} (só para validar o harness)`);
  }
  await boot();
  line(`Postgres local na porta ${port} (dados em ${dataDir}, removidos no fim); fuso da sessão: ${SESSION_TZ}`);
  const admin = await connect({ timeoutMs: 300000 });
  const ver = (await admin.query('show server_version')).rows[0].server_version;
  line(`Versão do servidor: ${ver}`);

  header('baseline local compartilhada + helpers');
  currentFile = 'baseline';
  try {
    await admin.query('begin');
    await admin.query(fs.readFileSync(BASELINE, 'utf8'));
    await admin.query('commit');
    record({ ok: true, label: '../local/supabase_baseline.sql carregada' });
  } catch (e) {
    await admin.query('rollback').catch(() => {});
    record({ ok: false, label: '../local/supabase_baseline.sql carregada', detail: describePgError(e) });
    return 1;
  }
  try {
    await admin.query('begin');
    await admin.query(fs.readFileSync(HELPERS, 'utf8'));
    await admin.query('commit');
    record({ ok: true, label: 'sql/_helpers.sql carregado' });
  } catch (e) {
    await admin.query('rollback').catch(() => {});
    record({ ok: false, label: 'sql/_helpers.sql carregado', detail: describePgError(e) });
    return 1;
  }
  // Senha aleatória por execução para o authenticator (só para este banco).
  await admin.query(`alter role authenticator password '${apiPassword}'`);
  currentFile = '';

  const mainFiles = listTests(SQL_DIR).filter(matchesFilter);
  if (HARNESS_ONLY) {
    for (const f of mainFiles.filter((f) => path.basename(f).startsWith('00_'))) await runSqlFile(admin, f);
    await admin.end();
    return summary();
  }

  const migrated = await migrationPhase(admin);
  if (!migrated) {
    line('');
    line('As migrations não aplicaram; os demais testes dependem delas e não foram executados.');
    await admin.end();
    return summary(true);
  }

  // Suíte padrão.
  for (const f of mainFiles) await runSqlFile(admin, f);

  // Papéis novos: no estado integrado o schema aceita todos; se não aceitar,
  // é falha real (a migration de integração não aplicou o que devia).
  const newRoleFiles = listTests(path.join(SQL_DIR, 'new_roles')).filter(matchesFilter);
  if (newRoleFiles.length) {
    const accepted = (
      await admin.query('select r, tests.schema_accepts_role(r) as ok from unnest($1::text[]) r', [NEW_ROLES])
    ).rows;
    const rejected = accepted.filter((r) => !r.ok).map((r) => r.r);
    header('sql/new_roles/ (papéis novos aceitos pelo schema integrado)');
    currentFile = 'new_roles';
    record({
      ok: rejected.length === 0,
      label: `profiles_role_check aceita ${NEW_ROLES.join(', ')}`,
      detail: rejected.length ? `rejeitados: ${rejected.join(', ')}` : null,
      kind: 'setup',
    });
    currentFile = '';
    if (rejected.length === 0) {
      for (const f of newRoleFiles) await runSqlFile(admin, f);
    }
  }

  // Pendências globais (falha esperada).
  for (const f of listTests(path.join(SQL_DIR, 'global')).filter(matchesFilter)) {
    await runSqlFile(admin, f, { expectedFailure: true });
  }

  // Concorrência real.
  if (!SKIP_CONCURRENCY && (FILTER == null || 'concurrency.test.mjs'.includes(FILTER))) {
    header('concurrency.test.mjs (autocommit, conexões separadas, READ COMMITTED)');
    currentFile = 'concurrency.test.mjs';
    try {
      const mod = await import(pathToFileURL(CONCURRENCY).href);
      await mod.default({
        admin,
        connectAdmin: () => connect({ timeoutMs: 120000 }),
        connectApi: async (uid) => {
          const c = await connect({ user: 'authenticator', password: apiPassword, timeoutMs: 120000 });
          await c.query(`select set_config('request.jwt.claims', $1, false)`, [
            JSON.stringify({ sub: uid, role: 'authenticated', aud: 'authenticated' }),
          ]);
          await c.query('set role authenticated');
          return c;
        },
        check: (ok, label, detail) => record({ ok: Boolean(ok), label, detail: ok ? null : detail, as: 'authenticated' }),
        truth: (ok, label, detail) => record({ ok: Boolean(ok), label, detail: ok ? null : detail, as: 'postgres' }),
        note: (text) => line(`  -- ${text}`),
      });
    } catch (e) {
      record({ ok: false, label: 'concurrency.test.mjs interrompido', detail: `${describePgError(e)}\n${e.stack ?? ''}`, kind: 'setup' });
    }
    currentFile = '';
  }

  await thirdApplication(admin);

  await admin.end();
  return summary();
}

function summary(aborted = false) {
  line('');
  line('== Resumo');
  const total = stats.ok + stats.fail + stats.expected;
  line(
    `${total} asserção(ões): ${stats.ok} ok, ${stats.fail} falha(s), ` +
      `${stats.expected} falha(s) esperada(s) (pendência global), ${stats.skipped} arquivo(s) pulado(s), ` +
      `${stats.warnings.length} aviso(s)`,
  );
  for (const w of stats.warnings) line(`AVISO: ${w}`);
  if (failures.length) {
    line('Falhas:');
    for (const f of failures) line(`  - ${short(f, 500)}`);
  }
  if (aborted) line('Execução interrompida antes do fim.');
  return stats.fail > 0 || aborted ? 1 : 0;
}

let code = 1;
try {
  code = await main();
} catch (e) {
  line('');
  line(`ERRO no runner: ${describePgError(e)}`);
  if (e?.stack) line(e.stack);
  if (pgLog.length) line(pgLog.slice(-30).join(''));
  code = 1;
} finally {
  await shutdown();
}
process.exit(code);
