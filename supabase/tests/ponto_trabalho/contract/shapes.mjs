// ─────────────────────────────────────────────────────────────────────────────
// Formatos que o app Dart lê, espelhando os fromJson de
// lib/features/time_tracking/domain/*.dart e lib/features/work/domain/*.dart.
//
// Mais estrito que o Dart num ponto: TODA chave que o fromJson lê tem de estar
// PRESENTE na resposta real (o Dart trata chave ausente como null nos campos
// opcionais, o que esconderia uma coluna que sumiu do SQL). Formatos:
//   instante  = texto ISO 8601 com deslocamento (Z ou ±HH[:MM]) — sem ele o
//               DateTime.parse do Dart usaria o fuso do aparelho;
//   data      = 'YYYY-MM-DD' (work_date, due_date, logged_on);
//   inteiro   = número JSON inteiro (seq é bigint e o PostgREST o manda como
//               número, nunca como texto).
// ─────────────────────────────────────────────────────────────────────────────

// Mesma expressão dos dois json_fields.dart.
const OFFSET_SUFFIX = /(Z|z|[+-]\d{2}(:?\d{2})?)$/;
const ISO_INSTANT =
  /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,](\d+))?)?(Z|z|[+-]\d{2}(?::?\d{2})?)$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ── Instantes como o Dart ───────────────────────────────────────────────────
/** Microssegundos desde a época (BigInt) de um instante ISO com fuso. */
export function instantMicros(text) {
  const m = ISO_INSTANT.exec(text);
  if (!m) throw new Error(`instante fora do formato ISO com fuso: ${text}`);
  const [, y, mo, d, h, mi, s = '0', frac = '', off] = m;
  // DateTime.parse usa até 6 dígitos da fração (microssegundos).
  const micro = BigInt((frac + '000000').slice(0, 6));
  let offsetMin = 0;
  if (off !== 'Z' && off !== 'z') {
    const sign = off[0] === '-' ? -1 : 1;
    const digits = off.slice(1).replace(':', '');
    offsetMin = sign * (Number(digits.slice(0, 2)) * 60 + Number(digits.slice(2, 4) || '0'));
  }
  const ms = Date.UTC(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), Number(s));
  return BigInt(ms) * 1000n + micro - BigInt(offsetMin) * 60000000n;
}

const pad = (n, w) => String(n).padStart(w, '0');

/**
 * `instantToJson(DateTime.parse(text))` do Dart: `toUtc().toIso8601String()`
 * → "YYYY-MM-DDTHH:MM:SS.mmmZ", ou ".mmmuuuZ" quando há microssegundos.
 */
export function dartInstantToJson(text) {
  const total = instantMicros(text);
  const msTotal = total / 1000n;
  const subMs = Number(total % 1000n);
  const dt = new Date(Number(msTotal));
  const base =
    `${pad(dt.getUTCFullYear(), 4)}-${pad(dt.getUTCMonth() + 1, 2)}-${pad(dt.getUTCDate(), 2)}` +
    `T${pad(dt.getUTCHours(), 2)}:${pad(dt.getUTCMinutes(), 2)}:${pad(dt.getUTCSeconds(), 2)}` +
    `.${pad(dt.getUTCMilliseconds(), 3)}`;
  return subMs === 0 ? `${base}Z` : `${base}${pad(subMs, 3)}Z`;
}

// ── Leitores (mesmas regras dos read* do Dart, mais a presença da chave) ────
function at(path, key) {
  return path ? `${path}.${key}` : key;
}

const R = {
  str: (v) => typeof v === 'string' || 'esperado texto',
  optStr: (v) => v === null || typeof v === 'string' || 'esperado texto ou null',
  uuid: (v) => (typeof v === 'string' && UUID.test(v)) || 'esperado uuid em texto',
  optUuid: (v) => v === null || (typeof v === 'string' && UUID.test(v)) || 'esperado uuid em texto ou null',
  instant: (v) =>
    (typeof v === 'string' && OFFSET_SUFFIX.test(v) && ISO_INSTANT.test(v)) || 'esperado instante ISO 8601 com fuso',
  optInstant: (v) => v === null || R.instant(v),
  date: (v) => (typeof v === 'string' && ISO_DATE.test(v)) || "esperado data 'YYYY-MM-DD'",
  optDate: (v) => v === null || R.date(v),
  int: (v) => Number.isInteger(v) || 'esperado número inteiro',
  optInt: (v) => v === null || Number.isInteger(v) || 'esperado número inteiro ou null',
  oneOf: (values) => (v) => values.includes(v) || `esperado um de ${values.join('/')}`,
};

function checkFields(obj, path, spec, problems) {
  if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) {
    problems.push(`${path || 'resposta'}: esperado objeto JSON, veio ${JSON.stringify(obj)?.slice(0, 80)}`);
    return false;
  }
  for (const [key, rule] of Object.entries(spec)) {
    if (!(key in obj)) {
      problems.push(`${at(path, key)}: chave ausente (o Dart lê esta chave)`);
      continue;
    }
    const verdict = rule(obj[key], at(path, key), problems);
    if (verdict !== true && verdict !== undefined) {
      problems.push(`${at(path, key)}: ${verdict}; veio ${JSON.stringify(obj[key])?.slice(0, 80)}`);
    }
  }
  return true;
}

const TIME_BREAK = {
  id: R.uuid,
  shift_id: R.uuid,
  user_id: R.uuid,
  started_at: R.instant,
  ended_at: R.optInstant,
  created_at: R.instant,
  updated_at: R.instant,
};

function timeShiftSpec({ serverNow }) {
  return {
    id: R.uuid,
    user_id: R.uuid,
    started_at: R.instant,
    ended_at: R.optInstant,
    work_date: R.date,
    source: R.oneOf(['clock', 'manual']),
    note: R.optStr,
    review_status: R.oneOf(['none', 'pending', 'reviewed']),
    reviewed_at: R.optInstant,
    reviewed_by: R.optUuid,
    last_corrected_at: R.optInstant,
    last_corrected_by: R.optUuid,
    voided_at: R.optInstant,
    voided_by: R.optUuid,
    void_reason: R.optStr,
    created_at: R.instant,
    updated_at: R.instant,
    // TimeShift.fromJson recusa jornada sem a lista (o total sairia maior).
    time_breaks: (v, path, problems) => {
      if (!Array.isArray(v)) return 'esperada lista de intervalos (o contrato §3.4 nunca manda null)';
      v.forEach((b, i) => checkFields(b, `${path}[${i}]`, TIME_BREAK, problems));
      for (let i = 1; i < v.length; i += 1) {
        if (instantMicros(v[i].started_at) < instantMicros(v[i - 1].started_at)) {
          return 'intervalos fora da ordem de início (contrato §3.4: "por started_at")';
        }
      }
      return true;
    },
    ...(serverNow === 'required' ? { server_now: R.instant } : {}),
  };
}

function shift(serverNow) {
  return (v, path, problems) => {
    if (v === null) return true;
    checkFields(v, path, timeShiftSpec({ serverNow }), problems);
    if (serverNow === 'absent' && v && typeof v === 'object' && 'server_now' in v) {
      problems.push(`${at(path, 'server_now')}: só as RPCs mandam server_now; linha de tabela não deveria ter`);
    }
    return true;
  };
}

const TIME_STATUS = { open_shift: shift('optional'), server_now: R.instant };

const TIME_AUDIT = {
  id: R.uuid,
  seq: R.int,
  shift_id: R.optUuid,
  subject_user_id: R.uuid,
  actor_id: R.uuid,
  action: R.oneOf(['clock_in', 'break_start', 'break_end', 'clock_out', 'correct', 'create_manual', 'void', 'review']),
  reason: R.optStr,
  before: shift('optional'),
  after: shift('optional'),
  created_at: R.instant,
};

const KNOWN_ROLES = ['super_admin', 'partner', 'manager', 'sales_trial', 'employee_dev', 'employee', 'sdr', 'client'];
const PERSON = {
  id: R.uuid,
  full_name: R.optStr,
  // AppRole.fromDatabase transforma texto desconhecido em "unknown" (sem acesso).
  role: (v) => v === null || KNOWN_ROLES.includes(v) || 'papel que o AppRole não conhece',
};

const WORK_TASK = {
  id: R.uuid,
  title: R.str,
  description: R.optStr,
  assignee_id: R.optUuid,
  created_by: R.uuid,
  priority: R.oneOf(['low', 'medium', 'high', 'urgent']),
  status: R.oneOf(['todo', 'in_progress', 'blocked', 'in_review', 'done', 'canceled']),
  due_date: R.optDate,
  completed_at: R.optInstant,
  created_at: R.instant,
  updated_at: R.instant,
};

const WORK_LOG = {
  id: R.uuid,
  user_id: R.uuid,
  task_id: R.optUuid,
  shift_id: R.optUuid,
  summary: R.str,
  result: R.optStr,
  minutes_spent: R.optInt,
  logged_on: R.date,
  created_at: R.instant,
};

const WORK_DELIVERABLE = {
  id: R.uuid,
  task_id: R.uuid,
  work_log_id: R.optUuid,
  created_by: R.uuid,
  title: R.str,
  url: R.optStr,
  notes: R.optStr,
  created_at: R.instant,
};

const TASK_EVENT = {
  id: R.uuid,
  seq: R.int,
  task_id: R.uuid,
  actor_id: R.optUuid,
  action: R.oneOf(['created', 'updated', 'log_added', 'deliverable_added']),
  changes: (v) => v === null || (typeof v === 'object' && !Array.isArray(v)) || 'esperado objeto JSON',
  created_at: R.instant,
};

const SHIFT_REF = { id: R.uuid, started_at: R.instant, ended_at: R.optInstant, work_date: R.date };

function list(spec) {
  return (v, problems) => {
    if (!Array.isArray(v)) {
      problems.push(`resposta: esperada lista JSON, veio ${JSON.stringify(v)?.slice(0, 80)}`);
      return;
    }
    v.forEach((row, i) => checkFields(row, `[${i}]`, spec, problems));
  };
}

function one(spec) {
  return (v, problems) => checkFields(v, '', spec, problems);
}

/** Formatos por tipo de resposta. */
export const SHAPES = {
  timeStatus: one(TIME_STATUS),
  timeShiftRpc: (v, problems) => {
    checkFields(v, '', timeShiftSpec({ serverNow: 'required' }), problems);
  },
  timeShiftRows: (v, problems) => {
    if (!Array.isArray(v)) {
      problems.push('resposta: esperada lista JSON');
      return;
    }
    v.forEach((row, i) => shift('absent')(row, `[${i}]`, problems));
  },
  int: (v, problems) => {
    if (!Number.isInteger(v)) problems.push(`resposta: esperado inteiro JSON, veio ${JSON.stringify(v)}`);
  },
  timeAuditRows: list(TIME_AUDIT),
  people: list(PERSON),
  taskRows: list(WORK_TASK),
  task: one(WORK_TASK),
  logRows: list(WORK_LOG),
  log: one(WORK_LOG),
  deliverableRows: list(WORK_DELIVERABLE),
  deliverable: one(WORK_DELIVERABLE),
  eventRows: (v, problems) => {
    list(TASK_EVENT)(v, problems);
    if (!Array.isArray(v)) return;
    v.forEach((e, i) => {
      // TaskEvent.fromJson: em "updated" cada mudança é {from, to}.
      if (e.action === 'updated' && e.changes && typeof e.changes === 'object') {
        for (const [k, c] of Object.entries(e.changes)) {
          if (c === null || typeof c !== 'object' || Array.isArray(c) || !('from' in c) || !('to' in c)) {
            problems.push(`[${i}].changes.${k}: em "updated" cada mudança é {from, to}`);
          }
        }
      }
    });
  },
  shiftRefRows: list(SHIFT_REF),
};

/** Tipo de resposta pelo nome da captura (= método do repositório Dart). */
export function shapeFor(feature, captureName) {
  const method = captureName.split('.')[0];
  const time = {
    fetchStatus: 'timeStatus',
    clockIn: 'timeShiftRpc',
    startBreak: 'timeShiftRpc',
    endBreak: 'timeShiftRpc',
    clockOut: 'timeShiftRpc',
    correctShift: 'timeShiftRpc',
    createManualShift: 'timeShiftRpc',
    voidShift: 'timeShiftRpc',
    fetchShifts: 'timeShiftRows',
    fetchPendingReview: 'timeShiftRows',
    reviewShifts: 'int',
    fetchAuditTrail: 'timeAuditRows',
    fetchPeople: 'people',
  };
  const work = {
    fetchTasks: 'taskRows',
    fetchTask: 'task',
    createTask: 'task',
    updateTask: 'task',
    fetchLogs: 'logRows',
    addLog: 'log',
    fetchDeliverables: 'deliverableRows',
    addDeliverable: 'deliverable',
    fetchHistory: 'eventRows',
    fetchPeople: 'people',
    fetchRecentShifts: 'shiftRefRows',
  };
  const shape = (feature === 'time' ? time : work)[method];
  if (!shape) throw new Error(`sem formato conhecido para ${feature}:${captureName}`);
  return shape;
}

export function validateShape(shape, body) {
  const problems = [];
  SHAPES[shape](body, problems);
  return problems;
}

/** Compatibilidade estática de um valor JSON do corpo com o tipo SQL do parâmetro/coluna. */
export function jsonValueFits(value, sqlType) {
  if (value === null) return true;
  const t = sqlType.replace(/\(.*\)$/, '');
  switch (typeof value) {
    case 'string':
      if (t === 'uuid') return UUID.test(value);
      if (t === 'timestamp with time zone') return ISO_INSTANT.test(value);
      if (t === 'date') return ISO_DATE.test(value);
      return ['text', 'character varying', 'character', 'jsonb', 'json'].includes(t);
    case 'boolean':
      return t === 'boolean' || t === 'jsonb' || t === 'json';
    case 'number':
      return ['integer', 'smallint', 'bigint', 'numeric', 'real', 'double precision', 'jsonb', 'json'].includes(t) &&
        (Number.isInteger(value) || !['integer', 'smallint', 'bigint'].includes(t));
    case 'object':
      return t === 'jsonb' || t === 'json';
    default:
      return false;
  }
}
