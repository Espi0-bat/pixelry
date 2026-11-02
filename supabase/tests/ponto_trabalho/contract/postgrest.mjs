// ─────────────────────────────────────────────────────────────────────────────
// Emulador mínimo do PostgREST (v12, o do Supabase) para o replay do contrato.
//
// Traduz um pedido HTTP capturado do app Dart (método, caminho, query, corpo,
// cabeçalhos) na MESMA forma de SQL que o PostgREST gera e executa como o papel
// real (authenticator → SET LOCAL ROLE authenticated/anon, request.jwt.claims),
// numa transação por pedido, como o PostgREST faz:
//   - RPC  POST /rest/v1/rpc/<fn>: resolve a função pelo NOME e pelas CHAVES do
//     corpo (como o cache de schema do PostgREST: toda chave tem de ser um
//     parâmetro, todo parâmetro sem default tem de vir) e chama
//     public.<fn>(p_x := pgrst_body.p_x, …) a partir de
//     json_to_record($1) AS _(p_x <tipo do parâmetro>, …). Nome de parâmetro
//     errado → PGRST202; valor que não converte para o tipo → o erro do
//     Postgres (22P02, 22007…), exatamente como no PostgREST.
//   - GET  /rest/v1/<tabela>?select=…&<filtros>&order=…: SELECT com os filtros
//     (eq, neq, gt, gte, lt, lte, is, in, com not.), as ordens (asc/desc,
//     nullsfirst/nullslast) e o embedding 1-N/N-1 pela FK, com a ordem do
//     recurso embutido (<embed>.order). Transação READ ONLY.
//   - POST /rest/v1/<tabela> (insert) e PATCH (update com os filtros): colunas
//     = chaves do corpo, valores convertidos por json_to_recordset/json_to_record
//     com os tipos das colunas, RETURNING * para o Prefer return=representation.
//     Coluna sem grant de INSERT/UPDATE falha como falharia de verdade (42501).
//   - Accept: application/vnd.pgrst.object+json → exatamente 1 linha, senão
//     PGRST116 (406) e a transação é desfeita.
// Recurso que o app não usa e o emulador não conhece vira erro do EMULADOR
// (nunca um "passou" silencioso).
// ─────────────────────────────────────────────────────────────────────────────

export const OBJECT_ACCEPT = 'application/vnd.pgrst.object+json';

/** Erro do próprio emulador (pedido com recurso que ele não sabe traduzir). */
export class EmulatorError extends Error {}

const ident = (name) => '"' + String(name).replace(/"/g, '""') + '"';

// ── Cache de schema (como o do PostgREST, só de public) ─────────────────────
export async function loadSchemaCache(admin) {
  const rels = await admin.query(`
    select c.relname as name, c.relkind as kind,
           coalesce(json_agg(json_build_object('name', a.attname, 'type', format_type(a.atttypid, a.atttypmod),
                                               'generated', a.attgenerated <> '')
                             order by a.attnum) filter (where a.attnum is not null), '[]')::text as columns
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      left join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
     where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
     group by c.relname, c.relkind`);
  const fks = await admin.query(`
    select con.conname as name, src.relname as from_table, dst.relname as to_table,
           (select json_agg(a.attname order by k.i) from unnest(con.conkey) with ordinality k(n, i)
              join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.n)::text as from_cols,
           (select json_agg(a.attname order by k.i) from unnest(con.confkey) with ordinality k(n, i)
              join pg_attribute a on a.attrelid = con.confrelid and a.attnum = k.n)::text as to_cols
      from pg_constraint con
      join pg_class src on src.oid = con.conrelid
      join pg_namespace sn on sn.oid = src.relnamespace
      join pg_class dst on dst.oid = con.confrelid
      join pg_namespace dn on dn.oid = dst.relnamespace
     where con.contype = 'f' and sn.nspname = 'public' and dn.nspname = 'public'`);
  const fns = await admin.query(`
    select p.oid::bigint as oid, p.proname as name, p.pronargdefaults as ndefaults,
           p.proretset as retset, format_type(p.prorettype, null) as rettype,
           (select t.typtype from pg_type t where t.oid = p.prorettype)::text as rettyptype,
           p.provolatile::text as volatility,
           coalesce((
             select json_agg(json_build_object('name', x.name, 'type', format_type(x.typ, null)) order by x.ord)
               from unnest(coalesce(p.proallargtypes, p.proargtypes::oid[]),
                           coalesce(p.proargmodes, array_fill('i'::"char", array[p.pronargs])),
                           coalesce(p.proargnames, array_fill(''::text, array[cardinality(coalesce(p.proallargtypes, p.proargtypes::oid[]))])))
                    with ordinality as x(typ, mode, name, ord)
              where x.mode in ('i', 'b', 'v')), '[]')::text as args
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.prokind = 'f'`);
  const tables = new Map();
  for (const r of rels.rows) {
    tables.set(r.name, { name: r.name, kind: r.kind, columns: JSON.parse(r.columns) });
  }
  return {
    tables,
    fks: fks.rows.map((r) => ({ ...r, from_cols: JSON.parse(r.from_cols), to_cols: JSON.parse(r.to_cols) })),
    functions: fns.rows.map((r) => ({ ...r, oid: Number(r.oid), args: JSON.parse(r.args) })),
  };
}

// ── Parsing da query string ─────────────────────────────────────────────────
/** `*,time_breaks(*)` → [{kind:'star'}, {kind:'embed', name, items:[…]}]. */
export function parseSelect(text) {
  const out = [];
  let depth = 0;
  let cur = '';
  const parts = [];
  for (const ch of text) {
    if (ch === '(') depth += 1;
    if (ch === ')') depth -= 1;
    if (ch === ',' && depth === 0) {
      parts.push(cur);
      cur = '';
    } else cur += ch;
  }
  if (depth !== 0) throw new EmulatorError(`select com parênteses desbalanceados: ${text}`);
  if (cur !== '') parts.push(cur);
  for (const raw of parts) {
    const p = raw.trim();
    if (p === '') throw new EmulatorError(`select com item vazio: ${text}`);
    if (p === '*') {
      out.push({ kind: 'star' });
      continue;
    }
    const m = /^([A-Za-z_][A-Za-z0-9_]*)\((.*)\)$/s.exec(p);
    if (m) {
      out.push({ kind: 'embed', name: m[1], items: parseSelect(m[2]) });
      continue;
    }
    if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(p)) {
      out.push({ kind: 'col', name: p });
      continue;
    }
    // alias:col, col::cast, json->path, !hint… — o app não usa.
    throw new EmulatorError(`item de select não suportado pelo emulador: ${p}`);
  }
  return out;
}

/** `priority_rank.asc.nullslast,created_at.desc` → [{col, dir, nulls}]. */
export function parseOrder(text) {
  return text.split(',').map((term) => {
    const bits = term.trim().split('.');
    const col = bits.shift();
    let dir = null;
    let nulls = null;
    for (const b of bits) {
      if (b === 'asc' || b === 'desc') dir = b;
      else if (b === 'nullsfirst' || b === 'nullslast') nulls = b;
      else throw new EmulatorError(`modificador de order desconhecido: ${term}`);
    }
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(col ?? '')) throw new EmulatorError(`coluna de order inválida: ${term}`);
    return { col, dir, nulls };
  });
}

/** Lista de `in.(…)`: itens separados por vírgula; aspas duplas com \ de escape. */
export function parseInList(text) {
  if (!text.startsWith('(') || !text.endsWith(')')) throw new EmulatorError(`in sem parênteses: ${text}`);
  const body = text.slice(1, -1);
  const items = [];
  let i = 0;
  if (body === '') return items;
  while (i <= body.length) {
    let item = '';
    if (body[i] === '"') {
      i += 1;
      while (i < body.length && body[i] !== '"') {
        if (body[i] === '\\' && i + 1 < body.length) i += 1;
        item += body[i];
        i += 1;
      }
      if (body[i] !== '"') throw new EmulatorError(`aspas não fechadas em in: ${text}`);
      i += 1;
    } else {
      while (i < body.length && body[i] !== ',') {
        item += body[i];
        i += 1;
      }
    }
    items.push(item);
    if (i >= body.length) break;
    if (body[i] !== ',') throw new EmulatorError(`separador inesperado em in: ${text}`);
    i += 1;
  }
  return items;
}

const OPS = { eq: '=', neq: '<>', gt: '>', gte: '>=', lt: '<', lte: '<=' };

/** `gte.2026-10-26` / `not.is.null` / `in.("a","b")` → {negate, op, value}. */
export function parseFilter(raw) {
  let rest = raw;
  let negate = false;
  if (rest.startsWith('not.')) {
    negate = true;
    rest = rest.slice(4);
  }
  const dot = rest.indexOf('.');
  if (dot < 0) throw new EmulatorError(`filtro sem operador: ${raw}`);
  const op = rest.slice(0, dot);
  const value = rest.slice(dot + 1);
  if (op in OPS) return { negate, op, value };
  if (op === 'is') {
    if (!['null', 'true', 'false', 'unknown', 'not_null'].includes(value)) {
      throw new EmulatorError(`valor de is desconhecido: ${raw}`);
    }
    return { negate, op, value };
  }
  if (op === 'in') return { negate, op, value: parseInList(value) };
  throw new EmulatorError(`operador não suportado pelo emulador: ${op} (${raw})`);
}

const RESERVED = new Set(['select', 'order', 'limit', 'offset', 'on_conflict', 'columns', 'and', 'or']);

/** Separa a query em select, ordens, filtros (do recurso e dos embutidos). */
export function parseQuery(query) {
  const out = { select: null, order: [], filters: [], embedOrder: new Map(), embedFilters: new Map() };
  for (const [key, values] of Object.entries(query ?? {})) {
    for (const value of values) {
      if (key === 'select') {
        if (out.select != null) throw new EmulatorError('select repetido');
        out.select = parseSelect(value);
      } else if (key === 'order') {
        out.order.push(...parseOrder(value));
      } else if (RESERVED.has(key)) {
        throw new EmulatorError(`parâmetro ${key} não suportado pelo emulador`);
      } else if (key.includes('.')) {
        const [embed, ...restParts] = key.split('.');
        const rest = restParts.join('.');
        if (rest === 'order') {
          const list = out.embedOrder.get(embed) ?? [];
          list.push(...parseOrder(value));
          out.embedOrder.set(embed, list);
        } else if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(rest)) {
          const list = out.embedFilters.get(embed) ?? [];
          list.push({ col: rest, ...parseFilter(value) });
          out.embedFilters.set(embed, list);
        } else {
          throw new EmulatorError(`parâmetro de embutido não suportado: ${key}`);
        }
      } else {
        out.filters.push({ col: key, ...parseFilter(value) });
      }
    }
  }
  return out;
}

// ── Montagem do SQL ─────────────────────────────────────────────────────────
function column(cache, table, col) {
  const t = cache.tables.get(table);
  if (!t) throw Object.assign(new Error(`relation "public.${table}" does not exist`), { pgrst: { status: 404, code: '42P01' } });
  const c = t.columns.find((x) => x.name === col);
  if (!c) {
    throw Object.assign(new Error(`column ${table}.${col} does not exist`), { pgrst: { status: 400, code: '42703' } });
  }
  return c;
}

/** Relação para `select=…,<embed>(…)` a partir de `table` (como o PostgREST). */
export function findRelationship(cache, table, embed) {
  const o2m = cache.fks.filter((f) => f.from_table === embed && f.to_table === table);
  const m2o = cache.fks.filter((f) => f.from_table === table && f.to_table === embed);
  const all = [...o2m.map((f) => ({ card: 'o2m', fk: f })), ...m2o.map((f) => ({ card: 'm2o', fk: f }))];
  if (all.length === 0) {
    throw Object.assign(new Error(`Could not find a relationship between '${table}' and '${embed}' in the schema cache`), {
      pgrst: { status: 400, code: 'PGRST200' },
    });
  }
  if (all.length > 1) {
    throw Object.assign(new Error(`Could not embed because more than one relationship was found for '${table}' and '${embed}'`), {
      pgrst: { status: 300, code: 'PGRST201', details: all.map((r) => r.fk.name).join(', ') },
    });
  }
  return all[0];
}

class Params {
  constructor() {
    this.values = [];
  }
  add(v) {
    this.values.push(v);
    return `$${this.values.length}`;
  }
}

function filterSql(cache, table, alias, f, params) {
  column(cache, table, f.col);
  const lhs = `${alias}.${ident(f.col)}`;
  let expr;
  if (f.op === 'is') {
    const v = { null: 'null', not_null: 'not null', true: 'true', false: 'false', unknown: 'unknown' }[f.value];
    expr = `${lhs} is ${v}`;
  } else if (f.op === 'in') {
    // Valores sem tipo: o Postgres converte para o tipo da coluna (como o
    // literal "unknown" do PostgREST); valor inválido dá o erro de conversão.
    expr = `${lhs} = any (${params.add(f.value)})`;
  } else {
    expr = `${lhs} ${OPS[f.op]} ${params.add(f.value)}`;
  }
  return f.negate ? `not (${expr})` : expr;
}

function orderSql(cache, table, alias, list) {
  if (!list.length) return '';
  return (
    ' order by ' +
    list
      .map((o) => {
        column(cache, table, o.col);
        return `${alias}.${ident(o.col)}${o.dir ? ' ' + o.dir : ''}${o.nulls ? (o.nulls === 'nullsfirst' ? ' nulls first' : ' nulls last') : ''}`;
      })
      .join(',')
  );
}

let aliasCounter = 0;

function selectItemsSql(cache, table, alias, items, parsed, params) {
  const out = [];
  for (const it of items) {
    if (it.kind === 'star') out.push(`${alias}.*`);
    else if (it.kind === 'col') {
      column(cache, table, it.name);
      out.push(`${alias}.${ident(it.name)}`);
    } else {
      const rel = findRelationship(cache, table, it.name);
      aliasCounter += 1;
      const src = ident(`${it.name}_${aliasCounter}`);
      const agg = ident(`${table}_${it.name}_${aliasCounter}`);
      const inner = selectItemsSql(cache, it.name, src, it.items, { embedOrder: new Map(), embedFilters: new Map() }, params);
      const conds =
        rel.card === 'o2m'
          ? rel.fk.from_cols.map((c, i) => `${src}.${ident(c)} = ${alias}.${ident(rel.fk.to_cols[i])}`)
          : rel.fk.to_cols.map((c, i) => `${src}.${ident(c)} = ${alias}.${ident(rel.fk.from_cols[i])}`);
      for (const f of parsed.embedFilters.get(it.name) ?? []) conds.push(filterSql(cache, it.name, src, f, params));
      const order = orderSql(cache, it.name, src, parsed.embedOrder.get(it.name) ?? []);
      const sub = `select ${inner.join(', ')} from public.${ident(it.name)} as ${src} where ${conds.join(' and ')}${order}`;
      if (rel.card === 'o2m') {
        out.push(`coalesce((select json_agg(${agg}) from (${sub}) as ${agg}), '[]'::json) as ${ident(it.name)}`);
      } else {
        out.push(`(select row_to_json(${agg}) from (${sub}) as ${agg}) as ${ident(it.name)}`);
      }
    }
  }
  return out;
}

/** Resolução de função como o cache de schema do PostgREST. */
export function resolveFunction(cache, name, keys) {
  const candidates = cache.functions.filter((f) => f.name === name);
  const matches = candidates.filter((f) => {
    const names = f.args.map((a) => a.name);
    const required = f.args.slice(0, f.args.length - f.ndefaults).map((a) => a.name);
    return keys.every((k) => names.includes(k)) && required.every((r) => keys.includes(r));
  });
  if (matches.length === 1) return matches[0];
  if (matches.length === 0) {
    throw Object.assign(
      new Error(`Could not find the function public.${name}(${[...keys].sort().join(', ')}) in the schema cache`),
      {
        pgrst: {
          status: 404,
          code: 'PGRST202',
          hint: candidates.length
            ? `Perhaps you meant to call the function public.${name}(${candidates[0].args.map((a) => a.name).join(', ')})`
            : null,
        },
      },
    );
  }
  throw Object.assign(new Error(`Could not choose the best candidate function between: ${matches.map((m) => m.name).join(', ')}`), {
    pgrst: { status: 300, code: 'PGRST203' },
  });
}

/**
 * Traduz o pedido em { sql, params, readOnly, objectAccept, status, kind }.
 * Lança EmulatorError (recurso desconhecido) ou erro com `pgrst` (o erro que o
 * PostgREST daria antes de chegar ao banco: PGRST200/201/202, 42703…).
 */
export function translate(cache, req) {
  const m = /^\/rest\/v1\/(rpc\/)?([A-Za-z_][A-Za-z0-9_]*)$/.exec(req.path);
  if (!m) throw new EmulatorError(`caminho não reconhecido: ${req.path}`);
  const headers = req.headers ?? {};
  const objectAccept = headers.accept === OBJECT_ACCEPT;
  const params = new Params();

  if (m[1]) {
    if (req.method !== 'POST') throw new EmulatorError(`RPC por ${req.method} não suportado pelo emulador`);
    if (Object.keys(req.query ?? {}).length) throw new EmulatorError('RPC com query string não suportado pelo emulador');
    const body = req.body ?? {};
    if (typeof body !== 'object' || Array.isArray(body)) throw new EmulatorError('RPC com corpo que não é objeto JSON');
    const keys = Object.keys(body);
    const fn = resolveFunction(cache, m[2], keys);
    const keyArgs = fn.args.filter((a) => keys.includes(a.name));
    const call = `public.${ident(fn.name)}(${keyArgs.map((a) => `${ident(a.name)} := pgrst_body.${ident(a.name)}`).join(', ')})`;
    const from = keyArgs.length
      ? ` from (select ${params.add(JSON.stringify(body))}::json as json_data) as pgrst_payload,` +
        ` lateral (select * from json_to_record(pgrst_payload.json_data) as _(${keyArgs.map((a) => `${ident(a.name)} ${a.type}`).join(', ')})) as pgrst_body`
      : '';
    let sql;
    if (fn.retset) {
      sql =
        `select coalesce(json_agg(_postgrest_t), '[]')::text as body, count(_postgrest_t)::int as n from (` +
        (keyArgs.length ? `select pgrst_call.*${from}, lateral ${call} as pgrst_call` : `select pgrst_call.* from ${call} as pgrst_call`) +
        `) as _postgrest_t`;
    } else {
      sql = `select to_json(pgrst_call.pgrst_scalar)::text as body, 1 as n from (select ${call} as pgrst_scalar${from}) as pgrst_call`;
    }
    // O PostgREST chama função não VOLATILE em transação somente leitura.
    return { kind: 'rpc', fn, sql, params: params.values, readOnly: fn.volatility !== 'v', objectAccept, status: 200, scalar: !fn.retset };
  }

  const table = m[2];
  if (!cache.tables.has(table)) {
    throw Object.assign(new Error(`relation "public.${table}" does not exist`), { pgrst: { status: 404, code: '42P01' } });
  }
  const parsed = parseQuery(req.query);
  const alias = ident(table);
  const where = parsed.filters.map((f) => filterSql(cache, table, alias, f, params));
  const whereSql = where.length ? ` where ${where.join(' and ')}` : '';

  if (req.method === 'GET') {
    const items = selectItemsSql(cache, table, alias, parsed.select ?? [{ kind: 'star' }], parsed, params);
    const order = orderSql(cache, table, alias, parsed.order);
    const sql =
      `select coalesce(json_agg(_postgrest_t), '[]')::text as body, count(_postgrest_t)::int as n from (` +
      `select ${items.join(', ')} from public.${alias}${whereSql}${order}) as _postgrest_t`;
    return { kind: 'read', table, sql, params: params.values, readOnly: true, objectAccept, status: 200 };
  }

  if (req.method === 'POST' || req.method === 'PATCH') {
    if (parsed.order.length) throw new EmulatorError('order em escrita não suportado pelo emulador');
    const rows = Array.isArray(req.body) ? req.body : [req.body];
    if (!rows.length || rows.some((r) => r == null || typeof r !== 'object' || Array.isArray(r))) {
      throw new EmulatorError('corpo de escrita precisa ser objeto (ou lista de objetos)');
    }
    const keys = [...new Set(rows.flatMap((r) => Object.keys(r)))];
    if (!keys.length) throw new EmulatorError('escrita sem colunas');
    const cols = keys.map((k) => column(cache, table, k));
    const typed = cols.map((c) => `${ident(c.name)} ${c.type}`).join(', ');
    // postgrest-dart manda Prefer: return=representation sempre que há .select().
    const prefer = headers.prefer ?? (parsed.select ? 'return=representation' : 'return=minimal');
    const representation = /return=representation/.test(prefer);
    let mutation;
    if (req.method === 'POST') {
      if (parsed.filters.length) throw new EmulatorError('filtro em insert não suportado');
      mutation =
        `insert into public.${alias} (${keys.map(ident).join(', ')}) ` +
        `select ${keys.map((k) => `pgrst_body.${ident(k)}`).join(', ')} ` +
        `from json_to_recordset(${params.add(JSON.stringify(rows))}::json) as pgrst_body(${typed}) ` +
        `returning ${alias}.*`;
    } else {
      if (Array.isArray(req.body)) throw new EmulatorError('PATCH com lista não suportado');
      mutation =
        `update public.${alias} set ${keys.map((k) => `${ident(k)} = pgrst_body.${ident(k)}`).join(', ')} ` +
        `from (select * from json_to_record(${params.add(JSON.stringify(req.body))}::json) as _(${typed})) as pgrst_body` +
        `${whereSql} returning ${alias}.*`;
    }
    const items = representation
      ? selectItemsSql(cache, table, alias, parsed.select ?? [{ kind: 'star' }], parsed, params)
      : [`1 as _`];
    const sql =
      `with pgrst_source as (${mutation}) ` +
      `select coalesce(json_agg(_postgrest_t), '[]')::text as body, count(_postgrest_t)::int as n ` +
      `from (select ${items.join(', ')} from pgrst_source as ${alias}) as _postgrest_t`;
    return {
      kind: req.method === 'POST' ? 'insert' : 'update',
      table,
      sql,
      params: params.values,
      readOnly: false,
      objectAccept,
      representation,
      status: req.method === 'POST' ? 201 : representation ? 200 : 204,
    };
  }
  throw new EmulatorError(`método não suportado: ${req.method}`);
}

// ── Status HTTP dos erros (tabela do PostgREST v12) ─────────────────────────
export function httpStatusFor(code, isAnon) {
  if (!code) return 500;
  if (code === '42501') return isAnon ? 401 : 403;
  if (code === 'PGRST116') return 406;
  if (code === 'PGRST202' || code === '42883' || code === '42P01') return 404;
  if (code === 'PGRST200' || code === 'PGRST100') return 400;
  if (code === 'PGRST201' || code === 'PGRST203') return 300;
  if (code === '23505' || code === '23503') return 409;
  if (code === '25006') return 405;
  if (code === '42P17' || code === '57014') return 500;
  if (code.startsWith('08') || code.startsWith('53')) return 503;
  if (code.startsWith('XX')) return 500;
  return 400; // P0001, 23514, 22P02, 42703, …
}

/**
 * Executa o pedido como o PostgREST: uma transação, papel trocado com
 * set_config('role', …, true), claims do JWT em request.jwt.claims.
 * `actor` = { role: 'authenticated'|'anon', uid?: string }.
 * Devolve { status, body } (JSON já decodificado) ou { status, error }.
 */
export async function execute(api, cache, req, actor) {
  let plan;
  try {
    plan = translate(cache, req);
  } catch (e) {
    if (e instanceof EmulatorError) throw e;
    if (e.pgrst) {
      return {
        status: e.pgrst.status,
        error: { code: e.pgrst.code, message: e.message, details: e.pgrst.details ?? null, hint: e.pgrst.hint ?? null },
      };
    }
    throw e;
  }
  const isAnon = actor.role === 'anon';
  const claims = isAnon ? { role: 'anon' } : { sub: actor.uid, role: 'authenticated', aud: 'authenticated' };
  await api.query(`begin isolation level read committed${plan.readOnly ? ' read only' : ''}`);
  try {
    await api.query(
      `select set_config('role', $1, true), set_config('request.jwt.claims', $2, true),
              set_config('request.method', $3, true), set_config('request.path', $4, true)`,
      [actor.role, JSON.stringify(claims), req.method, req.path.replace(/^\/rest\/v1/, '')],
    );
    const r = await api.query(plan.sql, plan.params);
    const row = r.rows[0];
    const body = row.body == null ? null : JSON.parse(row.body);
    if (plan.objectAccept && plan.kind !== 'rpc') {
      if (row.n !== 1) {
        await api.query('rollback');
        return {
          status: 406,
          plan,
          error: {
            code: 'PGRST116',
            message: 'JSON object requested, multiple (or no) rows returned',
            details: `The result contains ${row.n} rows`,
            hint: null,
          },
        };
      }
      await api.query('commit');
      return { status: plan.status, plan, body: body[0] };
    }
    await api.query('commit');
    if (plan.kind !== 'rpc' && !plan.representation && plan.kind !== 'read') return { status: plan.status, plan, body: null };
    return { status: plan.status, plan, body };
  } catch (e) {
    await api.query('rollback').catch(() => {});
    if (!e.code) throw e;
    return {
      status: httpStatusFor(e.code, isAnon),
      plan,
      error: { code: e.code, message: e.message, details: e.detail ?? null, hint: e.hint ?? null },
    };
  }
}
