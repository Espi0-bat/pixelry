\set ON_ERROR_STOP on
-- Suíte SQL do financeiro: permissões, RLS, regras dos lançamentos, auditoria
-- e compatibilidade com invoices.
--
-- Rode SÓ por supabase/tests/finance/run.sh, num Postgres local descartável
-- ou em homologação. NUNCA em produção (nem "dentro de transação com
-- rollback": produção não é ambiente de teste).
--
-- Garantias:
--   * tudo roda numa transação que termina em ROLLBACK: pessoas, cobranças,
--     lançamentos e auditoria de teste nascem e morrem aqui;
--   * recusa rodar sem pixelry.finance_test_harness = on (o run.sh liga via
--     PGOPTIONS); o \set acima também faz o SQL Editor recusar o arquivo;
--   * ids e e-mails aleatórios (finance-test-<uuid>@example.invalid): nada
--     colide com dados existentes em homologação.
--
-- Identidade: pg_temp.as_actor(kind, uid) zera TODO o estado a cada caso
-- (reset role; request.jwt.claims; request.jwt.claim.*;
-- pixelry.finance_change_reason = '') e só então faz SET LOCAL ROLE. O SET
-- ROLE fica fora do bloco begin/exception (pg_temp.attempt/val), porque o
-- rollback do subbloco desfaria o SET. Nenhum INSERT usa RETURNING sob RLS.
--
-- Cada caso grava (id, ok, detalhe) em pg_temp.finance_t. No fim: o resumo
-- (último SELECT) e um DO que falha se algum caso falhou, se um id repetiu ou
-- se o total de casos não for o esperado (caso que não rodou não passa).

begin;

-- ── Trava do harness ────────────────────────────────────────────────────────
do $$
begin
  if coalesce(current_setting('pixelry.finance_test_harness', true), '') <> 'on' then
    raise exception 'finance_rls.test.sql: rode por supabase/tests/finance/run.sh (pixelry.finance_test_harness=on ausente). Nunca em produção.'
      using errcode = '42501';
  end if;
end $$;

do $$
begin
  if current_setting('server_version_num')::integer >= 170000 then
    perform set_config('transaction_timeout', '300s', true);
  end if;
end $$;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

-- ── Utilitários ─────────────────────────────────────────────────────────────
create temp table finance_t (
  seq     integer not null,
  case_id text    not null,
  ok      boolean not null,
  detail  text
);
grant all on table pg_temp.finance_t to public;

create temp table finance_u (
  name text primary key,
  id   uuid not null
);
grant all on table pg_temp.finance_u to public;

-- Troca de identidade. Zera claims e motivo; o SET LOCAL ROLE é a última coisa.
create function pg_temp.as_actor(p_kind text, p_uid uuid default null)
returns void
language plpgsql
as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
  perform set_config('request.jwt.claim.email', '', true);
  perform set_config('request.jwt.claim', '', true);
  perform set_config('pixelry.finance_change_reason', '', true);

  if p_kind = 'postgres' then
    perform set_config('request.jwt.claims', '', true);
  elsif p_kind = 'anon' then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    execute 'set local role anon';
  elsif p_kind = 'service_role' then
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    execute 'set local role service_role';
  elsif p_kind = 'authenticated' then
    if p_uid is null then
      raise exception 'as_actor: authenticated exige uid';
    end if;
    perform set_config('request.jwt.claims',
      json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
  else
    raise exception 'as_actor: tipo desconhecido %', p_kind;
  end if;
end;
$$;

-- Registra um caso. NULL conta como falha.
create function pg_temp.chk(p_case text, p_ok boolean, p_detail text default null)
returns void
language plpgsql
as $$
begin
  if p_case is null or p_case !~ '^[a-z0-9_]+$' then
    raise exception 'id de caso inválido: %', p_case;
  end if;
  insert into pg_temp.finance_t (seq, case_id, ok, detail)
  values ((select coalesce(max(t.seq), 0) + 1 from pg_temp.finance_t t),
          p_case, coalesce(p_ok, false), p_detail);
end;
$$;

-- Executa SQL com a identidade atual. 'ok:<linhas>' ou 'err:<sqlstate>:<mensagem>'.
create function pg_temp.attempt(p_sql text)
returns text
language plpgsql
as $$
declare
  v_rows bigint;
begin
  begin
    execute p_sql;
    get diagnostics v_rows = row_count;
    return 'ok:' || v_rows;
  exception when others then
    return 'err:' || sqlstate || ':' || sqlerrm;
  end;
end;
$$;

-- Primeiro valor do SQL, como texto ('<null>' se nulo), ou 'err:<sqlstate>:<mensagem>'.
create function pg_temp.val(p_sql text)
returns text
language plpgsql
as $$
declare
  v_out text;
begin
  begin
    execute p_sql into v_out;
    return coalesce(v_out, '<null>');
  exception when others then
    return 'err:' || sqlstate || ':' || sqlerrm;
  end;
end;
$$;

-- sqlstate de um resultado de attempt/val ('ok:<n>' passa direto).
create function pg_temp.code(p_result text)
returns text
language sql
immutable
as $$
  select case when p_result like 'err:%' then substr(p_result, 5, 5) else p_result end
$$;

-- VOLATILE de propósito. Como STABLE, o planner chamava u() ao estimar a
-- seletividade de `where p.id = pg_temp.u('x')` num UPDATE/SELECT, usando o
-- snapshot do começo do comando DO: ela não via a fixture gravada por
-- remember() nesse mesmo DO e falhava com "fixture desconhecida". Função
-- VOLATILE nunca é pré-avaliada pelo planner e lê um snapshot atual. O caso
-- harness_u_sees_fixture_from_same_command, abaixo, impede a regressão.
create function pg_temp.u(p_name text)
returns uuid
language plpgsql
volatile
as $$
declare
  v_id uuid;
begin
  select x.id into v_id from pg_temp.finance_u x where x.name = p_name;
  if v_id is null then
    raise exception 'fixture desconhecida: %', p_name;
  end if;
  return v_id;
end;
$$;

create function pg_temp.remember(p_name text, p_id uuid)
returns void
language plpgsql
as $$
begin
  if p_id is null then
    raise exception 'fixture % sem id', p_name;
  end if;
  insert into pg_temp.finance_u (name, id) values (p_name, p_id);
end;
$$;

create function pg_temp.today()
returns date
language sql
stable
as $$
  select (now() at time zone 'America/Sao_Paulo')::date
$$;

-- level_for(role, g) para g em (NULL, none, read, manage, bogus).
create function pg_temp.level_row(p_role text)
returns text
language sql
as $$
  select concat_ws(',',
    finance_private.level_for(p_role, null),
    finance_private.level_for(p_role, 'none'),
    finance_private.level_for(p_role, 'read'),
    finance_private.level_for(p_role, 'manage'),
    finance_private.level_for(p_role, 'bogus'))
$$;

-- finance_my_access() da identidade atual, como texto canônico.
create function pg_temp.access_text()
returns text
language sql
as $$
  select concat_ws('|', f.level, f.can_read::text, f.can_manage::text, f.is_owner::text,
                   coalesce(f.profile_role, 'null'))
  from public.finance_my_access() f
$$;

-- status|source_status|settled_on de um id no ledger completo, ou 'absent'.
create function pg_temp.ledger_text(p_id uuid)
returns text
language sql
as $$
  select coalesce((
    select concat_ws('|', l.status, coalesce(l.source_status, 'null'), coalesce(l.settled_on::text, 'null'))
    from public.finance_ledger(null, null) l
    where l.id = p_id
  ), 'absent')
$$;

grant execute on function pg_temp.as_actor(text, uuid)  to public;
grant execute on function pg_temp.chk(text, boolean, text) to public;
grant execute on function pg_temp.attempt(text)          to public;
grant execute on function pg_temp.val(text)              to public;
grant execute on function pg_temp.code(text)             to public;
grant execute on function pg_temp.u(text)                to public;
grant execute on function pg_temp.remember(text, uuid)   to public;
grant execute on function pg_temp.today()                to public;
grant execute on function pg_temp.access_text()          to public;
grant execute on function pg_temp.ledger_text(uuid)      to public;

-- ════════════════════════════════════════════════════════════════════════════
-- Autoteste do harness
-- Grava uma fixture e a lê por pg_temp.u() num UPDATE do MESMO comando DO,
-- exatamente como o bloco de pessoas faz. Com u() STABLE isto falha no planner
-- (snapshot do começo do comando). O UPDATE é SQL estático, direto neste
-- bloco, de propósito: chamado via pg_temp.attempt() numa expressão simples,
-- o PL/pgSQL tira um snapshot novo antes de planejar e o defeito não aparece.
-- O sub-bloco isola o erro para que o caso fique registrado como FALHOU.
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_id  uuid := gen_random_uuid();
  v_res text;
  v_vol char;
begin
  perform pg_temp.as_actor('postgres');
  create temp table finance_selftest (id uuid primary key, touched boolean not null default false);
  insert into pg_temp.finance_selftest (id) values (v_id);
  perform pg_temp.remember('selftest_same_command', v_id);
  begin
    update pg_temp.finance_selftest t set touched = true
    where t.id = pg_temp.u('selftest_same_command');
    v_res := 'ok:1';
  exception when others then
    v_res := 'err:' || sqlstate || ':' || sqlerrm;
  end;
  select p.provolatile into v_vol
  from pg_catalog.pg_proc p
  where p.oid = 'pg_temp.u(text)'::regprocedure;
  perform pg_temp.chk('harness_u_sees_fixture_from_same_command',
    v_res = 'ok:1' and v_vol = 'v',
    format('update=%s provolatile=%s (esperado ok:1 e v)', v_res, v_vol));
  drop table pg_temp.finance_selftest;
  -- Sem isto a suíte morreria mais adiante, no bloco de pessoas, com um
  -- "fixture desconhecida" sem explicação. Melhor parar aqui, com a causa.
  if not (v_res = 'ok:1' and v_vol = 'v') then
    raise exception 'autoteste do harness falhou: pg_temp.u() precisa ser VOLATILE para ler fixtures gravadas no mesmo comando (update=%, provolatile=%)',
      v_res, v_vol;
  end if;
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- Fixtures: pessoas
-- O perfil nasce pelo gatilho de auth.users (role client); o papel é ajustado
-- como postgres (guard_profile_role permite).
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_name text;
  v_id   uuid;
begin
  perform pg_temp.as_actor('postgres');
  foreach v_name in array array[
    'owner', 'mgr_none', 'mgr_read', 'mgr_manage', 'emp_none', 'emp_read', 'emp_cycle',
    'creator', 'cli_a', 'cli_b', 'cli_granted', 'cli_gone'
  ] loop
    v_id := gen_random_uuid();
    insert into auth.users (id, email, raw_user_meta_data)
    values (v_id, 'finance-test-' || v_id::text || '@example.invalid',
            jsonb_build_object('full_name', 'Teste ' || v_name));
    perform pg_temp.remember(v_name, v_id);
  end loop;
  -- Sessão autenticada sem perfil.
  perform pg_temp.remember('ghost', gen_random_uuid());

  update public.profiles p set role = 'super_admin' where p.id = pg_temp.u('owner');
  update public.profiles p set role = 'manager'
   where p.id in (pg_temp.u('mgr_none'), pg_temp.u('mgr_read'), pg_temp.u('mgr_manage'));
  update public.profiles p set role = 'employee'
   where p.id in (pg_temp.u('emp_none'), pg_temp.u('emp_read'), pg_temp.u('emp_cycle'), pg_temp.u('creator'));
  update public.profiles p set role = 'client', company_name = 'Empresa Teste A'
   where p.id = pg_temp.u('cli_a');
  update public.profiles p set role = 'client'
   where p.id in (pg_temp.u('cli_b'), pg_temp.u('cli_granted'), pg_temp.u('cli_gone'));
end $$;

do $$
declare
  v_n bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n
  from public.profiles p
  join pg_temp.finance_u x on x.id = p.id
  where p.email = 'finance-test-' || p.id::text || '@example.invalid';
  perform pg_temp.chk('fixture_profiles_from_trigger', v_n = 12, 'perfis: ' || v_n);
end $$;

-- Concessões pelo caminho real (dono via RPC) e uma linha gravada direto para
-- um cliente (não pode valer).
do $$
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  perform public.finance_set_access(pg_temp.u('mgr_read'),   'read',   'Teste: leitura do gestor');
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  perform public.finance_set_access(pg_temp.u('mgr_manage'), 'manage', 'Teste: gestão do gestor');
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  perform public.finance_set_access(pg_temp.u('emp_read'),   'read',   'Teste: leitura do funcionário');
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  perform public.finance_set_access(pg_temp.u('creator'),    'manage', 'Teste: autor de lançamentos');
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  insert into public.finance_access_grants (user_id, level, reason)
  values (pg_temp.u('cli_granted'), 'manage', 'Teste: concessão gravada para cliente');
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- A. Privilégios no catálogo (pegam revoke esquecido)
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_total bigint;
  v_anon  bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*), count(*) filter (where has_function_privilege('anon', p.oid, 'EXECUTE'))
    into v_total, v_anon
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'finance\_%';
  perform pg_temp.chk('rpcs_not_executable_by_anon', v_total = 14 and v_anon = 0,
    format('rpcs=%s anon=%s', v_total, v_anon));
end $$;

do $$
declare
  v_total bigint;
  v_auth  bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*), count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE'))
    into v_total, v_auth
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'finance\_%';
  perform pg_temp.chk('rpcs_executable_by_authenticated', v_total = 14 and v_auth = 14,
    format('rpcs=%s authenticated=%s', v_total, v_auth));
end $$;

do $$
declare
  v_total bigint;
  v_open  bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*),
         count(*) filter (where has_function_privilege('anon', p.oid, 'EXECUTE')
                             or has_function_privilege('public', p.oid, 'EXECUTE'))
    into v_total, v_open
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'finance_private';
  perform pg_temp.chk('private_functions_closed_to_anon_and_public', v_total > 0 and v_open = 0,
    format('funções=%s abertas=%s', v_total, v_open));
end $$;

do $$
declare
  v_total bigint;
  v_ok    bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*),
         count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE')
                            and has_function_privilege('service_role', p.oid, 'EXECUTE'))
    into v_total, v_ok
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'finance_private'
    and p.proname in ('is_owner', 'access_level', 'can_read', 'can_manage');
  perform pg_temp.chk('policy_helpers_executable', v_total = 4 and v_ok = 4,
    format('helpers=%s com execute=%s', v_total, v_ok));
end $$;

do $$
declare
  v_total bigint;
  v_auth  bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*), count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE'))
    into v_total, v_auth
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'finance_private'
    and p.proname not in ('is_owner', 'access_level', 'can_read', 'can_manage');
  perform pg_temp.chk('private_helpers_closed_to_authenticated', v_total >= 20 and v_auth = 0,
    format('funções=%s authenticated=%s', v_total, v_auth));
end $$;

do $$
declare
  v_total bigint;
  v_auth  bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*), count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE'))
    into v_total, v_auth
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'finance_private'
    and p.prorettype = 'pg_catalog.trigger'::pg_catalog.regtype;
  -- touch, block_delete, audit_log_guard, audit_row, audit_invoice e
  -- guard_profile_insert_role.
  perform pg_temp.chk('trigger_functions_closed', v_total = 6 and v_auth = 0,
    format('gatilhos=%s authenticated=%s', v_total, v_auth));
end $$;

do $$
declare
  v_tables bigint;
  v_anon   bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(t.rel),
         count(*) filter (where has_table_privilege('anon', t.rel,
           'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'))
    into v_tables, v_anon
  from (values (to_regclass('public.finance_access_grants')), (to_regclass('public.finance_categories')),
               (to_regclass('public.finance_entries')), (to_regclass('public.finance_audit_log'))) as t(rel);
  perform pg_temp.chk('tables_closed_to_anon', v_tables = 4 and v_anon = 0,
    format('tabelas=%s anon=%s', v_tables, v_anon));
end $$;

do $$
declare
  v_tables bigint;
  v_select bigint;
  v_write  bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(t.rel),
         count(*) filter (where has_table_privilege('authenticated', t.rel, 'SELECT')),
         count(*) filter (where has_table_privilege('authenticated', t.rel,
           'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'))
    into v_tables, v_select, v_write
  from (values (to_regclass('public.finance_access_grants')), (to_regclass('public.finance_categories')),
               (to_regclass('public.finance_entries')), (to_regclass('public.finance_audit_log'))) as t(rel);
  perform pg_temp.chk('tables_authenticated_select_only', v_tables = 4 and v_select = 4 and v_write = 0,
    format('tabelas=%s select=%s escrita=%s', v_tables, v_select, v_write));
end $$;

do $$
declare
  v_tables bigint;
  v_any    bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(t.rel),
         count(*) filter (where has_table_privilege('service_role', t.rel,
           'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'))
    into v_tables, v_any
  from (values (to_regclass('public.finance_access_grants')), (to_regclass('public.finance_categories')),
               (to_regclass('public.finance_entries')), (to_regclass('public.finance_audit_log'))) as t(rel);
  perform pg_temp.chk('tables_closed_to_service_role', v_tables = 4 and v_any = 0,
    format('tabelas=%s service_role=%s', v_tables, v_any));
end $$;

do $$
declare
  v_seq  regclass;
  v_open boolean;
begin
  perform pg_temp.as_actor('postgres');
  v_seq := to_regclass('public.finance_audit_log_id_seq');
  v_open := has_sequence_privilege('anon', v_seq, 'USAGE, SELECT, UPDATE')
         or has_sequence_privilege('authenticated', v_seq, 'USAGE, SELECT, UPDATE')
         or has_sequence_privilege('service_role', v_seq, 'USAGE, SELECT, UPDATE');
  perform pg_temp.chk('audit_sequence_closed', v_seq is not null and not v_open,
    format('seq=%s aberta=%s', v_seq, v_open));
end $$;

do $$
declare
  v_tbl  regclass;
  v_open boolean;
begin
  perform pg_temp.as_actor('postgres');
  v_tbl := to_regclass('finance_private.module_info');
  v_open := has_table_privilege('anon', v_tbl, 'SELECT, INSERT, UPDATE, DELETE')
         or has_table_privilege('authenticated', v_tbl, 'SELECT, INSERT, UPDATE, DELETE')
         or has_table_privilege('service_role', v_tbl, 'SELECT, INSERT, UPDATE, DELETE');
  perform pg_temp.chk('module_info_closed', v_tbl is not null and not v_open,
    format('tabela=%s aberta=%s', v_tbl, v_open));
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.chk('private_schema_usage',
    not has_schema_privilege('anon', 'finance_private', 'USAGE')
    and has_schema_privilege('authenticated', 'finance_private', 'USAGE')
    and has_schema_privilege('service_role', 'finance_private', 'USAGE'));
end $$;

do $$
declare
  v_n bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('finance_access_grants', 'finance_categories', 'finance_entries', 'finance_audit_log')
    and c.relrowsecurity;
  perform pg_temp.chk('rls_enabled_on_finance_tables', v_n = 4, 'tabelas com RLS: ' || v_n);
end $$;

do $$
declare
  v_n bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n
  from pg_catalog.pg_trigger t
  where t.tgrelid = 'public.invoices'::regclass
    and t.tgname = 'finance_audit_invoice_trg'
    and t.tgenabled = 'O'
    and not t.tgisinternal;
  perform pg_temp.chk('invoice_audit_trigger_installed', v_n = 1, 'gatilhos: ' || v_n);
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- B. Acesso e isolamento
-- ════════════════════════════════════════════════════════════════════════════

-- Matriz de level_for (papéis futuros só aqui; e2e usa os papéis do CHECK atual).
-- Ordem das concessões: NULL, none, read, manage, bogus.
do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.chk('level_for_super_admin',
    pg_temp.level_row('super_admin') = 'manage,manage,manage,manage,manage', pg_temp.level_row('super_admin'));
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.chk('level_for_partner',
    pg_temp.level_row('partner') = 'none,none,read,manage,none', pg_temp.level_row('partner'));
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.chk('level_for_manager',
    pg_temp.level_row('manager') = 'none,none,read,manage,none', pg_temp.level_row('manager'));
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.chk('level_for_sales_trial',
    pg_temp.level_row('sales_trial') = 'none,none,read,manage,none', pg_temp.level_row('sales_trial'));
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.chk('level_for_sdr',
    pg_temp.level_row('sdr') = 'none,none,read,manage,none', pg_temp.level_row('sdr'));
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.chk('level_for_employee_dev',
    pg_temp.level_row('employee_dev') = 'none,none,read,manage,none', pg_temp.level_row('employee_dev'));
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.chk('level_for_employee',
    pg_temp.level_row('employee') = 'none,none,read,manage,none', pg_temp.level_row('employee'));
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.chk('level_for_client',
    pg_temp.level_row('client') = 'none,none,none,none,none', pg_temp.level_row('client'));
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.chk('level_for_unknown_role',
    pg_temp.level_row('diretor') = 'none,none,none,none,none'
    and pg_temp.level_row('Super_Admin') = 'none,none,none,none,none',
    pg_temp.level_row('diretor') || ' / ' || pg_temp.level_row('Super_Admin'));
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.chk('level_for_null_role',
    pg_temp.level_row(null) = 'none,none,none,none,none', pg_temp.level_row(null));
end $$;

-- finance_my_access
do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.val('select pg_temp.access_text()');
  perform pg_temp.chk('my_access_super_admin', v = 'manage|true|true|true|super_admin', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v := pg_temp.val('select pg_temp.access_text()');
  perform pg_temp.chk('my_access_manager_without_grant', v = 'none|false|false|false|manager', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.val('select pg_temp.access_text()');
  perform pg_temp.chk('my_access_manager_read', v = 'read|true|false|false|manager', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.val('select pg_temp.access_text()');
  perform pg_temp.chk('my_access_manager_manage', v = 'manage|true|true|false|manager', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('emp_none'));
  v := pg_temp.val('select pg_temp.access_text()');
  perform pg_temp.chk('my_access_employee_without_grant', v = 'none|false|false|false|employee', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('emp_read'));
  v := pg_temp.val('select pg_temp.access_text()');
  perform pg_temp.chk('my_access_employee_with_grant', v = 'read|true|false|false|employee', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('cli_granted'));
  v := pg_temp.val('select pg_temp.access_text()');
  perform pg_temp.chk('my_access_client_with_grant_row_is_none', v = 'none|false|false|false|client', v);
end $$;

do $$
declare
  v_text text;
  v_rows text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('ghost'));
  v_text := pg_temp.val('select pg_temp.access_text()');
  v_rows := pg_temp.val('select count(*) from public.finance_my_access()');
  perform pg_temp.chk('my_access_without_profile_one_row',
    v_text = 'none|false|false|false|null' and v_rows = '1', v_text || ' linhas=' || v_rows);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('anon');
  v := pg_temp.attempt('select * from public.finance_my_access()');
  perform pg_temp.chk('my_access_anon_no_execute', pg_temp.code(v) = '42501', v);
end $$;

-- finance_ledger para quem não lê
do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v := pg_temp.attempt('select * from public.finance_ledger(null, null)');
  perform pg_temp.chk('ledger_denied_without_grant', v = 'err:42501:Sem acesso ao financeiro.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('cli_granted'));
  v := pg_temp.attempt('select * from public.finance_ledger(null, null)');
  perform pg_temp.chk('ledger_denied_client', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('anon');
  v := pg_temp.attempt('select * from public.finance_ledger(null, null)');
  perform pg_temp.chk('ledger_anon_no_execute', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v := pg_temp.attempt('select * from public.finance_overview_meta()');
  perform pg_temp.chk('overview_meta_denied_without_grant', pg_temp.code(v) = '42501', v);
end $$;

-- finance_set_access: só o dono, com validações
do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_access(%L::uuid, 'read', 'Tentativa de gestor')$q$, pg_temp.u('emp_none')));
  perform pg_temp.chk('set_access_denied_to_manager',
    v = 'err:42501:Só um super admin pode alterar o acesso ao financeiro.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('emp_read'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_access(%L::uuid, 'manage', 'Tentativa de leitor')$q$, pg_temp.u('emp_read')));
  perform pg_temp.chk('set_access_denied_to_reader_self', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_access(%L::uuid, 'bogus', 'Motivo de teste')$q$, pg_temp.u('emp_none')));
  perform pg_temp.chk('set_access_invalid_level', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_access(%L::uuid, 'read', '  abc  ')$q$, pg_temp.u('emp_none')));
  perform pg_temp.chk('set_access_short_reason', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_access(%L::uuid, 'read', 'Motivo de teste')$q$, pg_temp.u('ghost')));
  perform pg_temp.chk('set_access_unknown_person', v = 'err:P0002:Pessoa não encontrada.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_access(%L::uuid, 'read', 'Motivo de teste')$q$, pg_temp.u('owner')));
  perform pg_temp.chk('set_access_super_admin_target',
    v = 'err:22023:Super admin já tem acesso completo.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_access(%L::uuid, 'read', 'Motivo de teste')$q$, pg_temp.u('cli_a')));
  perform pg_temp.chk('set_access_client_target',
    v = 'err:22023:Este papel não pode receber acesso ao financeiro.', v);
end $$;

-- Ciclo de concessão: granted → changed → removed, auditado com motivo.
do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_access(%L::uuid, 'read', 'Teste: ciclo 1 leitura')$q$, pg_temp.u('emp_cycle')));
  perform pg_temp.chk('smoke_set_access_grant', v = 'ok:1', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_access(%L::uuid, 'manage', 'Teste: ciclo 2 gestão')$q$, pg_temp.u('emp_cycle')));
  perform pg_temp.chk('set_access_change', v = 'ok:1', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_access(%L::uuid, 'none', 'Teste: ciclo 3 retirada')$q$, pg_temp.u('emp_cycle')));
  perform pg_temp.chk('set_access_remove', v = 'ok:1', v);
end $$;

do $$
declare
  v_events  text;
  v_reasons text;
  v_actors  bigint;
begin
  perform pg_temp.as_actor('postgres');
  select string_agg(a.event, ',' order by a.id),
         string_agg(coalesce(a.reason, '<null>'), ',' order by a.id),
         count(*) filter (where a.actor_id is distinct from pg_temp.u('owner') or a.actor_role <> 'authenticated')
    into v_events, v_reasons, v_actors
  from public.finance_audit_log a
  where a.entity_type = 'finance_access_grant' and a.entity_id = pg_temp.u('emp_cycle');
  perform pg_temp.chk('grant_lifecycle_audited',
    v_events = 'access_granted,access_changed,access_removed'
    and v_reasons = 'Teste: ciclo 1 leitura,Teste: ciclo 2 gestão,Teste: ciclo 3 retirada'
    and v_actors = 0,
    format('eventos=%s motivos=%s outros_atores=%s', v_events, v_reasons, v_actors));
end $$;

do $$
declare
  v_level  text;
  v_by     uuid;
  v_access text;
begin
  perform pg_temp.as_actor('postgres');
  select g.level, g.granted_by into v_level, v_by
  from public.finance_access_grants g where g.user_id = pg_temp.u('emp_cycle');
  perform pg_temp.as_actor('authenticated', pg_temp.u('emp_cycle'));
  v_access := pg_temp.val('select pg_temp.access_text()');
  perform pg_temp.chk('access_removed_takes_effect',
    v_level = 'none' and v_by = pg_temp.u('owner') and v_access = 'none|false|false|false|employee',
    format('level=%s granted_by_ok=%s acesso=%s', v_level, v_by = pg_temp.u('owner'), v_access));
end $$;

-- 'Sem acesso' para quem nunca teve linha: a auditoria diz access_removed
-- (negativa explícita), não access_granted. E o motivo não fica para trás
-- na transação depois da RPC.
do $$
declare
  v_id     uuid;
  v        text;
  v_guc    text;
  v_event  text;
  v_action text;
  v_level  text;
begin
  perform pg_temp.as_actor('postgres');
  v_id := gen_random_uuid();
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_id, 'finance-test-' || v_id::text || '@example.invalid',
          jsonb_build_object('full_name', 'Teste acesso negado'));
  update public.profiles p set role = 'employee' where p.id = v_id;

  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_access(%L::uuid, 'none', 'Teste: negativa explícita de acesso')$q$, v_id));
  v_guc := coalesce(current_setting('pixelry.finance_change_reason', true), '<null>');

  perform pg_temp.as_actor('postgres');
  select a.event, a.action, a.new_values ->> 'level' into v_event, v_action, v_level
  from public.finance_audit_log a
  where a.entity_type = 'finance_access_grant' and a.entity_id = v_id;
  perform pg_temp.chk('set_access_none_without_row_audited_removed',
    v = 'ok:1' and v_event = 'access_removed' and v_action = 'insert' and v_level = 'none' and v_guc = '',
    format('%s evento=%s action=%s level=%s motivo_residual=%s', v, v_event, v_action, v_level, v_guc));
end $$;

-- finance_access_list: só o dono; internos e super_admin, nunca clientes.
do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt('select * from public.finance_access_list()');
  perform pg_temp.chk('access_list_denied_to_manager', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare
  v_owner   text;
  v_read    text;
  v_none    text;
  v_clients bigint;
  v_reason  text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  select l.level into v_owner from public.finance_access_list() l where l.user_id = pg_temp.u('owner');
  select l.level, l.reason into v_read, v_reason from public.finance_access_list() l where l.user_id = pg_temp.u('mgr_read');
  select l.level into v_none from public.finance_access_list() l where l.user_id = pg_temp.u('emp_none');
  select count(*) into v_clients from public.finance_access_list() l
   where l.user_id in (pg_temp.u('cli_a'), pg_temp.u('cli_b'), pg_temp.u('cli_granted'));
  perform pg_temp.chk('smoke_access_list',
    v_owner = 'manage' and v_read = 'read' and v_none = 'none' and v_clients = 0
    and v_reason = 'Teste: leitura do gestor',
    format('owner=%s read=%s none=%s clientes=%s motivo=%s', v_owner, v_read, v_none, v_clients, v_reason));
end $$;

-- Ninguém vira dono do financeiro recriando um profile: pela API (manager com
-- "Admin full access"), profile novo só nasce como client. O profile é apagado
-- como postgres, simulando o DELETE que a policy do manager permite.
do $$
declare
  v_id    uuid;
  v_super text;
  v_emp   text;
  v_n     bigint;
begin
  perform pg_temp.as_actor('postgres');
  v_id := gen_random_uuid();
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_id, 'finance-test-' || v_id::text || '@example.invalid',
          jsonb_build_object('full_name', 'Teste perfil recriado'));
  perform pg_temp.remember('pf_recreated', v_id);
  delete from public.profiles p where p.id = v_id;

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v_super := pg_temp.attempt(format(
    $q$insert into public.profiles (id, full_name, email, role) values (%L::uuid, 'Teste perfil recriado', %L, 'super_admin')$q$,
    v_id, 'finance-test-' || v_id::text || '@example.invalid'));
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v_emp := pg_temp.attempt(format(
    $q$insert into public.profiles (id, full_name, email, role) values (%L::uuid, 'Teste perfil recriado', %L, 'employee')$q$,
    v_id, 'finance-test-' || v_id::text || '@example.invalid'));

  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.profiles p where p.id = v_id;
  perform pg_temp.chk('manager_cannot_insert_privileged_profile',
    pg_temp.code(v_super) = '42501' and pg_temp.code(v_emp) = '42501' and v_n = 0,
    format('super_admin=%s / employee=%s / perfis=%s', v_super, v_emp, v_n));
end $$;

-- O caminho do create-employee (service_role, upsert com role) continua.
do $$
declare
  v      text;
  v_role text;
begin
  perform pg_temp.as_actor('service_role');
  v := pg_temp.attempt(format(
    $q$insert into public.profiles (id, full_name, email, role) values (%L::uuid, 'Teste perfil recriado', %L, 'employee')
       on conflict (id) do update set full_name = excluded.full_name, email = excluded.email, role = excluded.role$q$,
    pg_temp.u('pf_recreated'), 'finance-test-' || pg_temp.u('pf_recreated')::text || '@example.invalid'));
  perform pg_temp.as_actor('postgres');
  select p.role into v_role from public.profiles p where p.id = pg_temp.u('pf_recreated');
  perform pg_temp.chk('service_role_inserts_internal_profile', v = 'ok:1' and v_role = 'employee',
    format('%s papel=%s', v, v_role));
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- C. Categorias e lançamentos (criação e validações)
-- ════════════════════════════════════════════════════════════════════════════
do $$
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('cat_income',
    public.finance_create_category('Teste receitas ' || left(gen_random_uuid()::text, 8), 'income'));
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('cat_expense',
    public.finance_create_category('Teste despesas ' || left(gen_random_uuid()::text, 8), 'expense'));
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('cat_old',
    public.finance_create_category('Teste antiga ' || left(gen_random_uuid()::text, 8)));
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('cat_cycle',
    public.finance_create_category('Teste ciclo ' || left(gen_random_uuid()::text, 8), 'both'));
end $$;

do $$
declare
  v_applies text;
  v_by      uuid;
  v_event   text;
begin
  perform pg_temp.as_actor('postgres');
  select c.applies_to, c.created_by into v_applies, v_by
  from public.finance_categories c where c.id = pg_temp.u('cat_income');
  select a.event into v_event from public.finance_audit_log a
  where a.entity_type = 'finance_category' and a.entity_id = pg_temp.u('cat_income');
  perform pg_temp.chk('smoke_create_category',
    v_applies = 'income' and v_by = pg_temp.u('mgr_manage') and v_event = 'created',
    format('applies_to=%s autor_ok=%s evento=%s', v_applies, v_by = pg_temp.u('mgr_manage'), v_event));
end $$;

do $$
declare
  v_name text;
  v      text;
begin
  perform pg_temp.as_actor('postgres');
  select c.name into v_name from public.finance_categories c where c.id = pg_temp.u('cat_income');
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format($q$select public.finance_create_category(%L, 'both')$q$, '  ' || upper(v_name) || ' '));
  perform pg_temp.chk('create_category_duplicate',
    v = 'err:23505:Já existe uma categoria com esse nome.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt($q$select public.finance_create_category(' x ', 'both')$q$);
  perform pg_temp.chk('create_category_invalid_name', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt($q$select public.finance_create_category('Teste tipo ruim', 'transfer')$q$);
  perform pg_temp.chk('create_category_invalid_scope', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_category_archived(%L::uuid, true, 'Teste: categoria antiga')$q$, pg_temp.u('cat_old')));
  perform pg_temp.chk('smoke_set_category_archived', v = 'ok:1', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_category_archived(%L::uuid, true, 'Teste: arquivar ciclo')$q$, pg_temp.u('cat_cycle')));
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := v || ' / ' || pg_temp.attempt(format(
    $q$select public.finance_set_category_archived(%L::uuid, false, 'Teste: reativar ciclo')$q$, pg_temp.u('cat_cycle')));
  perform pg_temp.chk('category_archive_unarchive_calls', v = 'ok:1 / ok:1', v);
end $$;

do $$
declare
  v_events  text;
  v_reasons text;
  v_now     timestamptz;
begin
  perform pg_temp.as_actor('postgres');
  select string_agg(a.event, ',' order by a.id), string_agg(coalesce(a.reason, '<null>'), ',' order by a.id)
    into v_events, v_reasons
  from public.finance_audit_log a
  where a.entity_type = 'finance_category' and a.entity_id = pg_temp.u('cat_cycle');
  select c.archived_at into v_now from public.finance_categories c where c.id = pg_temp.u('cat_cycle');
  perform pg_temp.chk('category_archive_audited',
    v_events = 'created,archived,unarchived'
    and v_reasons = '<null>,Teste: arquivar ciclo,Teste: reativar ciclo'
    and v_now is null,
    format('eventos=%s motivos=%s archived_at=%s', v_events, v_reasons, v_now));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_category_archived(%L::uuid, true, 'curt')$q$, pg_temp.u('cat_cycle')));
  perform pg_temp.chk('category_archive_short_reason', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_category_archived(%L::uuid, true, 'Teste: inexistente')$q$, gen_random_uuid()));
  perform pg_temp.chk('category_archive_not_found', pg_temp.code(v) = 'P0002', v);
end $$;

-- Lançamentos de trabalho (criados pelo gestor com manage).
do $$
declare
  t date := pg_temp.today();
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.remember('k_exp_settled', gen_random_uuid());

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_exp_settled', public.finance_create_entry(
    p_direction         => 'expense',
    p_description       => '  Teste aluguel  ',
    p_amount_cents      => 150000,
    p_status            => 'settled',
    p_settled_on        => t - 2,
    p_category_id       => pg_temp.u('cat_expense'),
    p_counterparty_name => 'Imobiliária Teste',
    p_idempotency_key   => 'finance-test-' || pg_temp.u('k_exp_settled')::text));

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_inc_pending', public.finance_create_entry(
    p_direction    => 'income',
    p_description  => 'Teste consultoria',
    p_amount_cents => 250000,
    p_status       => 'pending',
    p_due_date     => t + 10,
    p_category_id  => pg_temp.u('cat_income'),
    p_client_id    => pg_temp.u('cli_a')));

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_inc_settled', public.finance_create_entry(
    p_direction    => 'income',
    p_description  => 'Teste projeto',
    p_amount_cents => 100000,
    p_status       => 'settled',
    p_settled_on   => t - 5,
    p_client_id    => pg_temp.u('cli_b')));

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_rev_partial', public.finance_create_entry(
    p_direction    => 'income',
    p_description  => 'Teste serviço avulso',
    p_amount_cents => 2000,
    p_status       => 'settled',
    p_settled_on   => t - 3));

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_to_correct', public.finance_create_entry(
    p_direction    => 'expense',
    p_description  => 'Teste correção',
    p_amount_cents => 5000,
    p_status       => 'pending',
    p_due_date     => t + 5));

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_reopen', public.finance_create_entry(
    p_direction    => 'income',
    p_description  => 'Teste reabrir',
    p_amount_cents => 3000,
    p_status       => 'settled',
    p_settled_on   => t - 1));

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_to_settle', public.finance_create_entry(
    p_direction    => 'expense',
    p_description  => 'Teste liquidar',
    p_amount_cents => 7000,
    p_status       => 'pending',
    p_due_date     => t - 1));

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_to_cancel', public.finance_create_entry(
    p_direction    => 'expense',
    p_description  => 'Teste cancelar',
    p_amount_cents => 9000,
    p_status       => 'forecast',
    p_due_date     => t + 3));

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_cent', public.finance_create_entry(
    p_direction    => 'expense',
    p_description  => 'Teste um centavo',
    p_amount_cents => 1,
    p_status       => 'settled',
    p_settled_on   => t));

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_ten', public.finance_create_entry(
    p_direction    => 'income',
    p_description  => 'Teste dez centavos',
    p_amount_cents => 10,
    p_status       => 'settled',
    p_settled_on   => t));

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_twenty', public.finance_create_entry(
    p_direction    => 'income',
    p_description  => 'Teste vinte centavos',
    p_amount_cents => 20,
    p_status       => 'settled',
    p_settled_on   => t));
end $$;

do $$
declare
  v_desc   text;
  v_amount numeric;
  v_status text;
  v_kind   text;
  v_cur    text;
  v_by     uuid;
begin
  perform pg_temp.as_actor('postgres');
  select e.description, e.amount, e.status, e.entry_kind, e.currency, e.created_by
    into v_desc, v_amount, v_status, v_kind, v_cur, v_by
  from public.finance_entries e where e.id = pg_temp.u('e_exp_settled');
  perform pg_temp.chk('smoke_create_entry',
    v_desc = 'Teste aluguel' and v_amount = 1500.00 and v_status = 'settled' and v_kind = 'regular'
    and v_cur = 'BRL' and v_by = pg_temp.u('mgr_manage'),
    format('desc=%s amount=%s status=%s kind=%s cur=%s', v_desc, v_amount, v_status, v_kind, v_cur));
end $$;

do $$
declare
  v_n      bigint;
  v_action text;
  v_actor  uuid;
  v_role   text;
  v_reason text;
  v_cents  text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'finance_entry' and a.entity_id = pg_temp.u('e_exp_settled');
  select a.action, a.actor_id, a.actor_role, a.reason, a.new_values ->> 'amount_cents'
    into v_action, v_actor, v_role, v_reason, v_cents
  from public.finance_audit_log a
  where a.entity_type = 'finance_entry' and a.entity_id = pg_temp.u('e_exp_settled') and a.event = 'created';
  perform pg_temp.chk('create_entry_audited_created',
    v_n = 1 and v_action = 'insert' and v_actor = pg_temp.u('mgr_manage') and v_role = 'authenticated'
    and v_reason is null and v_cents = '150000',
    format('n=%s action=%s role=%s reason=%s cents=%s', v_n, v_action, v_role, v_reason, v_cents));
end $$;

do $$
declare
  v   text;
  v_n bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.val(format(
    $q$select public.finance_create_entry('expense', 'Teste aluguel', 150000, 'settled',
         p_settled_on => %L::date, p_idempotency_key => %L)::text$q$,
    pg_temp.today() - 2, 'finance-test-' || pg_temp.u('k_exp_settled')::text));
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.finance_entries e
  where e.idempotency_key = 'finance-test-' || pg_temp.u('k_exp_settled')::text;
  perform pg_temp.chk('create_entry_idempotent_same_id',
    v = pg_temp.u('e_exp_settled')::text and v_n = 1, format('id=%s linhas=%s', v, v_n));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste aluguel', 150001, 'settled',
         p_settled_on => %L::date, p_idempotency_key => %L)$q$,
    pg_temp.today() - 2, 'finance-test-' || pg_temp.u('k_exp_settled')::text));
  perform pg_temp.chk('create_entry_idempotent_conflict',
    v = 'err:23505:Esta chave de envio já foi usada com outros dados.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste zero', 0, 'pending', %L::date)$q$, pg_temp.today() + 1));
  perform pg_temp.chk('create_entry_zero_amount', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste negativo', -500, 'pending', %L::date)$q$, pg_temp.today() + 1));
  perform pg_temp.chk('create_entry_negative_amount', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste limite', 100000000000000, 'pending', %L::date)$q$,
    pg_temp.today() + 1));
  perform pg_temp.chk('create_entry_amount_above_limit', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt($q$select public.finance_create_entry('expense', 'Teste sem vencimento', 1000, 'pending')$q$);
  perform pg_temp.chk('create_entry_open_without_due', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt($q$select public.finance_create_entry('expense', 'Teste pago sem data', 1000, 'settled')$q$);
  perform pg_temp.chk('create_entry_settled_without_date', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste futuro', 1000, 'settled', p_settled_on => %L::date)$q$,
    pg_temp.today() + 1));
  perform pg_temp.chk('create_entry_future_settlement',
    v = 'err:22023:A data de pagamento não pode ser futura.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste aberto pago', 1000, 'pending', %L::date, %L::date)$q$,
    pg_temp.today() + 1, pg_temp.today()));
  perform pg_temp.chk('create_entry_open_with_settled_on', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste cancelado direto', 1000, 'cancelled', %L::date)$q$,
    pg_temp.today() + 1));
  perform pg_temp.chk('create_entry_status_cancelled_refused', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('transfer', 'Teste direção', 1000, 'pending', %L::date)$q$,
    pg_temp.today() + 1));
  perform pg_temp.chk('create_entry_invalid_direction', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', ' x ', 1000, 'pending', %L::date)$q$, pg_temp.today() + 1));
  perform pg_temp.chk('create_entry_short_description', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste chave curta', 1000, 'pending', %L::date,
         p_idempotency_key => 'abc')$q$, pg_temp.today() + 1));
  perform pg_temp.chk('create_entry_short_idempotency_key', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste categoria arquivada', 1000, 'pending', %L::date,
         p_category_id => %L::uuid)$q$, pg_temp.today() + 1, pg_temp.u('cat_old')));
  perform pg_temp.chk('create_entry_archived_category', v = 'err:22023:Esta categoria está arquivada.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste categoria de receita', 1000, 'pending', %L::date,
         p_category_id => %L::uuid)$q$, pg_temp.today() + 1, pg_temp.u('cat_income')));
  perform pg_temp.chk('create_entry_wrong_direction_category',
    v = 'err:22023:Esta categoria não vale para este tipo de lançamento.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste categoria inexistente', 1000, 'pending', %L::date,
         p_category_id => %L::uuid)$q$, pg_temp.today() + 1, gen_random_uuid()));
  perform pg_temp.chk('create_entry_unknown_category', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('income', 'Teste cliente funcionário', 1000, 'pending', %L::date,
         p_client_id => %L::uuid)$q$, pg_temp.today() + 1, pg_temp.u('emp_none')));
  perform pg_temp.chk('create_entry_client_not_client',
    v = 'err:22023:O cliente informado não é um cliente cadastrado.', v);
end $$;

do $$
declare
  v_client uuid;
  v_name   text;
begin
  perform pg_temp.as_actor('postgres');
  select e.client_id, e.counterparty_name into v_client, v_name
  from public.finance_entries e where e.id = pg_temp.u('e_inc_pending');
  perform pg_temp.chk('create_entry_client_name_snapshot',
    v_client = pg_temp.u('cli_a') and v_name = 'Empresa Teste A', 'contraparte=' || coalesce(v_name, '<null>'));
end $$;

-- O cliente é conferido mesmo quando a contraparte vem preenchida (não-cliente
-- e uuid que nem é profile → 22023, nunca o erro cru de FK).
do $$
declare
  v_emp  text;
  v_none text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v_emp := pg_temp.attempt(format(
    $q$select public.finance_create_entry('income', 'Teste cliente funcionário', 1000, 'pending', %L::date,
         p_client_id => %L::uuid, p_counterparty_name => 'Fornecedor Teste')$q$,
    pg_temp.today() + 1, pg_temp.u('emp_none')));
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v_none := pg_temp.attempt(format(
    $q$select public.finance_create_entry('income', 'Teste cliente inexistente', 1000, 'pending', %L::date,
         p_client_id => %L::uuid, p_counterparty_name => 'Fornecedor Teste')$q$,
    pg_temp.today() + 1, gen_random_uuid()));
  perform pg_temp.chk('create_entry_client_checked_with_counterparty',
    v_emp = 'err:22023:O cliente informado não é um cliente cadastrado.'
    and v_none = 'err:22023:O cliente informado não é um cliente cadastrado.',
    v_emp || ' / ' || v_none);
end $$;

-- Cliente sem empresa nem nome: o snapshot é 'Cliente sem nome', nunca o
-- e-mail (quem só lê o financeiro não vê e-mail de cliente).
do $$
declare
  v_id    uuid;
  v_entry uuid;
  v_name  text;
  v_seen  text;
begin
  perform pg_temp.as_actor('postgres');
  v_id := gen_random_uuid();
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_id, 'finance-test-' || v_id::text || '@example.invalid', '{}'::jsonb);
  update public.profiles p set role = 'client', full_name = null, company_name = null where p.id = v_id;

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v_entry := public.finance_create_entry(
    p_direction    => 'income',
    p_description  => 'Teste cliente sem nome',
    p_amount_cents => 4500,
    p_status       => 'pending',
    p_due_date     => pg_temp.today() + 4,
    p_client_id    => v_id);

  perform pg_temp.as_actor('postgres');
  select e.counterparty_name into v_name from public.finance_entries e where e.id = v_entry;
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select l.counterparty_name into v_seen from public.finance_ledger(null, null) l where l.id = v_entry;
  perform pg_temp.chk('client_without_name_snapshot_has_no_email',
    v_name = 'Cliente sem nome' and v_seen = 'Cliente sem nome',
    format('gravado=%s visto=%s', coalesce(v_name, '<null>'), coalesce(v_seen, '<null>')));
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- D. RLS e escrita direta
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_total bigint;
  v_seen  text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.finance_entries;
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v_seen := pg_temp.val('select count(*) from public.finance_entries');
  perform pg_temp.chk('entries_hidden_without_grant', v_total > 0 and v_seen = '0',
    format('total=%s visto=%s', v_total, v_seen));
end $$;

do $$
declare
  v_total bigint;
  v_seen  text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.finance_entries;
  perform pg_temp.as_actor('authenticated', pg_temp.u('cli_granted'));
  v_seen := pg_temp.val('select count(*) from public.finance_entries');
  perform pg_temp.chk('entries_hidden_from_client_with_grant_row', v_total > 0 and v_seen = '0',
    format('total=%s visto=%s', v_total, v_seen));
end $$;

do $$
declare
  v_total bigint;
  v_seen  text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.finance_audit_log;
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v_seen := pg_temp.val('select count(*) from public.finance_audit_log');
  perform pg_temp.chk('audit_hidden_without_grant', v_total > 0 and v_seen = '0',
    format('total=%s visto=%s', v_total, v_seen));
end $$;

do $$
declare
  v_total bigint;
  v_seen  text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.finance_categories;
  perform pg_temp.as_actor('authenticated', pg_temp.u('emp_none'));
  v_seen := pg_temp.val('select count(*) from public.finance_categories');
  perform pg_temp.chk('categories_hidden_without_grant', v_total > 0 and v_seen = '0',
    format('total=%s visto=%s', v_total, v_seen));
end $$;

do $$
declare
  v_total   bigint;
  v_entries text;
  v_cats    text;
  v_ctotal  bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.finance_entries;
  select count(*) into v_ctotal from public.finance_categories;
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v_entries := pg_temp.val('select count(*) from public.finance_entries');
  v_cats := pg_temp.val('select count(*) from public.finance_categories');
  perform pg_temp.chk('reader_sees_entries_and_categories',
    v_total > 0 and v_entries = v_total::text and v_cats = v_ctotal::text,
    format('entries %s/%s categorias %s/%s', v_entries, v_total, v_cats, v_ctotal));
end $$;

do $$
declare
  v_total bigint;
  v_all   text;
  v_own   text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.finance_access_grants;
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v_all := pg_temp.val('select count(*) from public.finance_access_grants');
  v_own := pg_temp.val(format('select count(*) from public.finance_access_grants g where g.user_id = %L::uuid',
                              pg_temp.u('mgr_read')));
  perform pg_temp.chk('grants_user_sees_only_own_row', v_total >= 5 and v_all = '1' and v_own = '1',
    format('total=%s visto=%s proprio=%s', v_total, v_all, v_own));
end $$;

do $$
declare
  v_total bigint;
  v_seen  text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.finance_access_grants;
  perform pg_temp.as_actor('authenticated', pg_temp.u('emp_none'));
  v_seen := pg_temp.val('select count(*) from public.finance_access_grants');
  perform pg_temp.chk('grants_user_without_row_sees_none', v_total > 0 and v_seen = '0',
    format('total=%s visto=%s', v_total, v_seen));
end $$;

do $$
declare
  v_total bigint;
  v_seen  text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.finance_access_grants;
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v_seen := pg_temp.val('select count(*) from public.finance_access_grants');
  perform pg_temp.chk('grants_owner_sees_all', v_total >= 5 and v_seen = v_total::text,
    format('total=%s visto=%s', v_total, v_seen));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('anon');
  v := pg_temp.attempt('select count(*) from public.finance_access_grants');
  perform pg_temp.chk('grants_anon_no_select', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('anon');
  v := pg_temp.attempt('select count(*) from public.finance_entries');
  perform pg_temp.chk('entries_anon_no_select', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('anon');
  v := pg_temp.attempt('select count(*) from public.finance_audit_log');
  perform pg_temp.chk('audit_anon_no_select', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('anon');
  v := pg_temp.attempt('select count(*) from public.finance_categories');
  perform pg_temp.chk('categories_anon_no_select', pg_temp.code(v) = '42501', v);
end $$;

-- Auditoria de concessão: visível ao dono e ao alvo; invisível a outro leitor.
do $$
declare
  v_total bigint;
  v_seen  text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.finance_audit_log a
  where a.entity_type = 'finance_access_grant' and a.entity_id = pg_temp.u('mgr_read');
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v_seen := pg_temp.val(format(
    $q$select count(*) from public.finance_audit_log a
        where a.entity_type = 'finance_access_grant' and a.entity_id = %L::uuid$q$, pg_temp.u('mgr_read')));
  perform pg_temp.chk('grant_audit_visible_to_owner', v_total > 0 and v_seen = v_total::text,
    format('total=%s visto=%s', v_total, v_seen));
end $$;

do $$
declare
  v_total bigint;
  v_seen  text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.finance_audit_log a
  where a.entity_type = 'finance_access_grant' and a.entity_id = pg_temp.u('mgr_read');
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v_seen := pg_temp.val(format(
    $q$select count(*) from public.finance_audit_log a
        where a.entity_type = 'finance_access_grant' and a.entity_id = %L::uuid$q$, pg_temp.u('mgr_read')));
  perform pg_temp.chk('grant_audit_visible_to_target', v_total > 0 and v_seen = v_total::text,
    format('total=%s visto=%s', v_total, v_seen));
end $$;

do $$
declare
  v_total   bigint;
  v_other   text;
  v_entries text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.finance_audit_log a
  where a.entity_type = 'finance_access_grant' and a.entity_id = pg_temp.u('mgr_read');
  perform pg_temp.as_actor('authenticated', pg_temp.u('emp_read'));
  v_other := pg_temp.val(format(
    $q$select count(*) from public.finance_audit_log a
        where a.entity_type = 'finance_access_grant' and a.entity_id = %L::uuid$q$, pg_temp.u('mgr_read')));
  -- Prova de que o leitor lê a auditoria (o 0 acima não é falta de acesso geral).
  v_entries := pg_temp.val($q$select count(*) from public.finance_audit_log a where a.entity_type = 'finance_entry'$q$);
  perform pg_temp.chk('grant_audit_hidden_from_other_reader',
    v_total > 0 and v_other = '0' and v_entries <> '0' and v_entries not like 'err:%',
    format('total=%s outro=%s lançamentos=%s', v_total, v_other, v_entries));
end $$;

-- service_role não escreve nas tabelas do financeiro.
do $$
declare v text;
begin
  perform pg_temp.as_actor('service_role');
  v := pg_temp.attempt(format(
    $q$insert into public.finance_audit_log (entity_type, entity_id, action, event, actor_role)
       values ('invoice', %L::uuid, 'insert', 'created', 'service_role')$q$, gen_random_uuid()));
  perform pg_temp.chk('service_role_cannot_insert_audit', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('service_role');
  v := pg_temp.attempt(format(
    $q$insert into public.finance_access_grants (user_id, level, reason)
       values (%L::uuid, 'manage', 'Tentativa da Edge Function')$q$, pg_temp.u('emp_none')));
  perform pg_temp.chk('service_role_cannot_insert_grants', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('service_role');
  v := pg_temp.attempt(format(
    $q$insert into public.finance_entries (direction, description, amount, status, due_date)
       values ('expense', 'Tentativa da Edge Function', 10.00, 'pending', %L::date)$q$, pg_temp.today() + 1));
  perform pg_temp.chk('service_role_cannot_insert_entries', pg_temp.code(v) = '42501', v);
end $$;

-- manage escreve só por RPC.
do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$insert into public.finance_entries (direction, description, amount, status, due_date)
       values ('expense', 'Tentativa direta', 10.00, 'pending', %L::date)$q$, pg_temp.today() + 1));
  perform pg_temp.chk('manage_cannot_insert_entries_directly', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$update public.finance_entries set notes = 'Tentativa direta' where id = %L::uuid$q$, pg_temp.u('e_to_correct')));
  perform pg_temp.chk('manage_cannot_update_entries_directly', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt($q$insert into public.finance_categories (name) values ('Tentativa direta')$q$);
  perform pg_temp.chk('manage_cannot_insert_categories_directly', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.attempt(format(
    $q$update public.finance_access_grants set level = 'manage' where user_id = %L::uuid$q$, pg_temp.u('mgr_read')));
  perform pg_temp.chk('owner_cannot_update_grants_directly', pg_temp.code(v) = '42501', v);
end $$;

-- read não chama RPC de escrita.
do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.attempt(format(
    $q$select public.finance_create_entry('expense', 'Teste leitor', 100, 'pending', %L::date)$q$, pg_temp.today() + 1));
  perform pg_temp.chk('read_cannot_create_entry', v = 'err:42501:Sem permissão para alterar o financeiro.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.attempt(format(
    $q$select public.finance_cancel_entry(%L::uuid, 'Tentativa do leitor')$q$, pg_temp.u('e_to_correct')));
  perform pg_temp.chk('read_cannot_cancel_entry', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.attempt($q$select public.finance_create_category('Teste do leitor', 'both')$q$);
  perform pg_temp.chk('read_cannot_create_category', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.attempt('select * from public.finance_clients()');
  perform pg_temp.chk('read_cannot_list_clients', pg_temp.code(v) = '42501', v);
end $$;

-- Cada RPC de escrita tem o próprio assert: read não corrige, não liquida, não
-- estorna e não arquiva (e a linha fica como estava).
do $$
declare
  v      text;
  v_desc text;
  v_now  text;
begin
  perform pg_temp.as_actor('postgres');
  select e.description into v_desc from public.finance_entries e where e.id = pg_temp.u('e_to_correct');
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"description":"Teste do leitor"}'::jsonb, 'Tentativa do leitor')$q$,
    pg_temp.u('e_to_correct')));
  perform pg_temp.as_actor('postgres');
  select e.description into v_now from public.finance_entries e where e.id = pg_temp.u('e_to_correct');
  perform pg_temp.chk('read_cannot_correct_entry',
    v = 'err:42501:Sem permissão para alterar o financeiro.' and v_now = v_desc,
    format('%s descrição=%s', v, v_now));
end $$;

do $$
declare
  v        text;
  v_status text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.attempt(format(
    $q$select public.finance_settle_entry(%L::uuid, %L::date, 'Tentativa do leitor')$q$,
    pg_temp.u('e_to_settle'), pg_temp.today()));
  perform pg_temp.as_actor('postgres');
  select e.status into v_status from public.finance_entries e where e.id = pg_temp.u('e_to_settle');
  perform pg_temp.chk('read_cannot_settle_entry',
    v = 'err:42501:Sem permissão para alterar o financeiro.' and v_status = 'pending',
    format('%s status=%s', v, v_status));
end $$;

do $$
declare
  v   text;
  v_n bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.attempt(format(
    $q$select public.finance_reverse_entry(%L::uuid, %L::date, 'Tentativa do leitor')$q$,
    pg_temp.u('e_exp_settled'), pg_temp.today()));
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.finance_entries e where e.reversal_of = pg_temp.u('e_exp_settled');
  perform pg_temp.chk('read_cannot_reverse_entry',
    v = 'err:42501:Sem permissão para alterar o financeiro.' and v_n = 0,
    format('%s estornos=%s', v, v_n));
end $$;

do $$
declare
  v          text;
  v_archived timestamptz;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.attempt(format(
    $q$select public.finance_set_category_archived(%L::uuid, true, 'Tentativa do leitor')$q$, pg_temp.u('cat_cycle')));
  perform pg_temp.as_actor('postgres');
  select c.archived_at into v_archived from public.finance_categories c where c.id = pg_temp.u('cat_cycle');
  perform pg_temp.chk('read_cannot_archive_category',
    v = 'err:42501:Sem permissão para alterar o financeiro.' and v_archived is null,
    format('%s archived_at=%s', v, v_archived));
end $$;

-- Quem não lê (manager sem concessão, cliente com linha de concessão, sessão
-- sem perfil) não lê histórico nem metadados e não altera nada.
do $$
declare
  v_hist   text;
  v_meta   text;
  v_settle text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v_hist := pg_temp.attempt(format(
    $q$select * from public.finance_entry_history('manual', %L::uuid)$q$, pg_temp.u('e_to_correct')));
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v_meta := pg_temp.attempt('select * from public.finance_overview_meta()');
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v_settle := pg_temp.attempt(format(
    $q$select public.finance_settle_entry(%L::uuid, %L::date)$q$, pg_temp.u('e_to_settle'), pg_temp.today()));
  perform pg_temp.chk('no_grant_denied_history_meta_and_writes',
    v_hist = 'err:42501:Sem acesso ao financeiro.'
    and v_meta = 'err:42501:Sem acesso ao financeiro.'
    and v_settle = 'err:42501:Sem permissão para alterar o financeiro.',
    v_hist || ' / ' || v_meta || ' / ' || v_settle);
end $$;

do $$
declare
  v_hist   text;
  v_meta   text;
  v_settle text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('cli_granted'));
  v_hist := pg_temp.attempt(format(
    $q$select * from public.finance_entry_history('manual', %L::uuid)$q$, pg_temp.u('e_to_correct')));
  perform pg_temp.as_actor('authenticated', pg_temp.u('cli_granted'));
  v_meta := pg_temp.attempt('select * from public.finance_overview_meta()');
  perform pg_temp.as_actor('authenticated', pg_temp.u('cli_granted'));
  v_settle := pg_temp.attempt(format(
    $q$select public.finance_settle_entry(%L::uuid, %L::date)$q$, pg_temp.u('e_to_settle'), pg_temp.today()));
  perform pg_temp.chk('client_with_grant_row_denied_history_meta_and_writes',
    v_hist = 'err:42501:Sem acesso ao financeiro.'
    and v_meta = 'err:42501:Sem acesso ao financeiro.'
    and v_settle = 'err:42501:Sem permissão para alterar o financeiro.',
    v_hist || ' / ' || v_meta || ' / ' || v_settle);
end $$;

do $$
declare
  v_hist   text;
  v_meta   text;
  v_settle text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('ghost'));
  v_hist := pg_temp.attempt(format(
    $q$select * from public.finance_entry_history('manual', %L::uuid)$q$, pg_temp.u('e_to_correct')));
  perform pg_temp.as_actor('authenticated', pg_temp.u('ghost'));
  v_meta := pg_temp.attempt('select * from public.finance_overview_meta()');
  perform pg_temp.as_actor('authenticated', pg_temp.u('ghost'));
  v_settle := pg_temp.attempt(format(
    $q$select public.finance_settle_entry(%L::uuid, %L::date)$q$, pg_temp.u('e_to_settle'), pg_temp.today()));
  perform pg_temp.chk('no_profile_denied_history_meta_and_writes',
    v_hist = 'err:42501:Sem acesso ao financeiro.'
    and v_meta = 'err:42501:Sem acesso ao financeiro.'
    and v_settle = 'err:42501:Sem permissão para alterar o financeiro.',
    v_hist || ' / ' || v_meta || ' / ' || v_settle);
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- E. Correção, liquidação, cancelamento e estorno
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"notes":"Teste"}'::jsonb, '   ')$q$, pg_temp.u('e_to_correct')));
  perform pg_temp.chk('correct_without_reason', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"foo":1}'::jsonb, 'Motivo de teste')$q$, pg_temp.u('e_to_correct')));
  perform pg_temp.chk('correct_unknown_key', v = 'err:22023:Campo não pode ser corrigido: foo', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"direction":"income"}'::jsonb, 'Motivo de teste')$q$,
    pg_temp.u('e_to_correct')));
  perform pg_temp.chk('correct_direction_key_refused',
    v = 'err:22023:Campo não pode ser corrigido: direction', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"due_date":"2026-02-30"}'::jsonb, 'Motivo de teste')$q$,
    pg_temp.u('e_to_correct')));
  perform pg_temp.chk('correct_invalid_date', v = 'err:22023:Data inválida em due_date.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"due_date":"01/12/2026"}'::jsonb, 'Motivo de teste')$q$,
    pg_temp.u('e_to_correct')));
  perform pg_temp.chk('correct_date_wrong_format', v = 'err:22023:Data inválida em due_date.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"amount_cents":"100"}'::jsonb, 'Motivo de teste')$q$,
    pg_temp.u('e_to_correct')));
  perform pg_temp.chk('correct_amount_cents_string', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"amount_cents":100.5}'::jsonb, 'Motivo de teste')$q$,
    pg_temp.u('e_to_correct')));
  perform pg_temp.chk('correct_amount_cents_fraction', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{}'::jsonb, 'Motivo de teste')$q$, pg_temp.u('e_to_correct')));
  perform pg_temp.chk('correct_empty_changes', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"status":"cancelled"}'::jsonb, 'Motivo de teste')$q$,
    pg_temp.u('e_to_correct')));
  perform pg_temp.chk('correct_status_cancelled_refused', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"notes":"x"}'::jsonb, 'Motivo de teste')$q$, gen_random_uuid()));
  perform pg_temp.chk('correct_not_found', pg_temp.code(v) = 'P0002', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, %L::jsonb, 'Motivo de teste')$q$,
    pg_temp.u('e_exp_settled'), jsonb_build_object('settled_on', (pg_temp.today() + 1)::text)));
  perform pg_temp.chk('correct_future_settled_on', v = 'err:22023:A data de pagamento não pode ser futura.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, %L::jsonb, 'Motivo de teste')$q$,
    pg_temp.u('e_reopen'), jsonb_build_object('status', 'pending', 'due_date', (pg_temp.today() + 3)::text)));
  perform pg_temp.chk('correct_reopen_without_clearing_settled_on',
    v = 'err:22023:Remova a data de pagamento ao reabrir o lançamento.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, %L::jsonb, 'Motivo de teste')$q$,
    pg_temp.u('e_to_correct'), jsonb_build_object('client_id', pg_temp.u('emp_none')::text)));
  perform pg_temp.chk('correct_client_not_client', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid,
         '{"description":"  Teste correção ajustada ","amount_cents":6550}'::jsonb, 'Ajuste de teste do valor')$q$,
    pg_temp.u('e_to_correct')));
  perform pg_temp.chk('smoke_correct_entry', v = 'ok:1', v);
end $$;

do $$
declare
  v_n       bigint;
  v_reason  text;
  v_fields  text[];
  v_old     text;
  v_new     text;
  v_actor   uuid;
  v_amount  numeric;
  v_desc    text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'finance_entry' and a.entity_id = pg_temp.u('e_to_correct') and a.event = 'corrected';
  select a.reason, a.changed_fields, a.old_values ->> 'amount_cents', a.new_values ->> 'amount_cents', a.actor_id
    into v_reason, v_fields, v_old, v_new, v_actor
  from public.finance_audit_log a
  where a.entity_type = 'finance_entry' and a.entity_id = pg_temp.u('e_to_correct') and a.event = 'corrected';
  select e.amount, e.description into v_amount, v_desc from public.finance_entries e where e.id = pg_temp.u('e_to_correct');
  perform pg_temp.chk('correct_entry_audited_corrected',
    v_n = 1 and v_reason = 'Ajuste de teste do valor' and v_fields = array['amount', 'description']
    and v_old = '5000' and v_new = '6550' and v_actor = pg_temp.u('mgr_manage')
    and v_amount = 65.50 and v_desc = 'Teste correção ajustada',
    format('n=%s motivo=%s campos=%s %s→%s amount=%s desc=%s', v_n, v_reason, v_fields, v_old, v_new, v_amount, v_desc));
end $$;

do $$
declare
  v      text;
  v_n    bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid,
         '{"description":"Teste correção ajustada","amount_cents":6550}'::jsonb, 'Repetição sem mudança')$q$,
    pg_temp.u('e_to_correct')));
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'finance_entry' and a.entity_id = pg_temp.u('e_to_correct') and a.event <> 'created';
  perform pg_temp.chk('correct_no_change_is_noop', v = 'ok:1' and v_n = 1, format('%s auditorias=%s', v, v_n));
end $$;

do $$
declare
  v        text;
  v_status text;
  v_settle date;
  v_due    date;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, %L::jsonb, 'Teste: reabrir lançamento')$q$,
    pg_temp.u('e_reopen'),
    jsonb_build_object('status', 'pending', 'due_date', (pg_temp.today() + 3)::text, 'settled_on', null)));
  perform pg_temp.as_actor('postgres');
  select e.status, e.settled_on, e.due_date into v_status, v_settle, v_due
  from public.finance_entries e where e.id = pg_temp.u('e_reopen');
  perform pg_temp.chk('correct_reopen_ok',
    v = 'ok:1' and v_status = 'pending' and v_settle is null and v_due = pg_temp.today() + 3,
    format('%s status=%s settled_on=%s', v, v_status, v_settle));
end $$;

-- Liquidação
do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_settle_entry(%L::uuid, %L::date)$q$, pg_temp.u('e_to_settle'), pg_temp.today() + 1));
  perform pg_temp.chk('settle_future_date', v = 'err:22023:A data de pagamento não pode ser futura.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_settle_entry(%L::uuid, null)$q$, pg_temp.u('e_to_settle')));
  perform pg_temp.chk('settle_without_date', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_settle_entry(%L::uuid, %L::date)$q$, pg_temp.u('e_to_settle'), pg_temp.today()));
  perform pg_temp.chk('smoke_settle_entry', v = 'ok:1', v);
end $$;

do $$
declare
  v_event  text;
  v_reason text;
  v_status text;
  v_on     date;
begin
  perform pg_temp.as_actor('postgres');
  select a.event, a.reason into v_event, v_reason from public.finance_audit_log a
  where a.entity_type = 'finance_entry' and a.entity_id = pg_temp.u('e_to_settle') and a.action = 'update';
  select e.status, e.settled_on into v_status, v_on from public.finance_entries e where e.id = pg_temp.u('e_to_settle');
  perform pg_temp.chk('settle_audited_settled',
    v_event = 'settled' and v_reason is null and v_status = 'settled' and v_on = pg_temp.today(),
    format('evento=%s motivo=%s status=%s em=%s', v_event, v_reason, v_status, v_on));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_settle_entry(%L::uuid, %L::date)$q$, pg_temp.u('e_to_settle'), pg_temp.today()));
  perform pg_temp.chk('settle_already_settled', pg_temp.code(v) = '22023', v);
end $$;

-- Cancelamento
do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_cancel_entry(%L::uuid, 'abc')$q$, pg_temp.u('e_to_cancel')));
  perform pg_temp.chk('cancel_short_reason', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_cancel_entry(%L::uuid, 'Lançamento duplicado de teste')$q$, pg_temp.u('e_to_cancel')));
  perform pg_temp.chk('smoke_cancel_entry', v = 'ok:1', v);
end $$;

do $$
declare
  v_event  text;
  v_reason text;
  v_status text;
  v_by     uuid;
  v_at     timestamptz;
  v_cr     text;
begin
  perform pg_temp.as_actor('postgres');
  select a.event, a.reason into v_event, v_reason from public.finance_audit_log a
  where a.entity_type = 'finance_entry' and a.entity_id = pg_temp.u('e_to_cancel') and a.action = 'update';
  select e.status, e.cancelled_by, e.cancelled_at, e.cancel_reason into v_status, v_by, v_at, v_cr
  from public.finance_entries e where e.id = pg_temp.u('e_to_cancel');
  perform pg_temp.chk('cancel_audited_cancelled',
    v_event = 'cancelled' and v_reason = 'Lançamento duplicado de teste' and v_status = 'cancelled'
    and v_by = pg_temp.u('mgr_manage') and v_at is not null and v_cr = 'Lançamento duplicado de teste',
    format('evento=%s motivo=%s status=%s', v_event, v_reason, v_status));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"notes":"depois de cancelar"}'::jsonb, 'Motivo de teste')$q$,
    pg_temp.u('e_to_cancel')));
  perform pg_temp.chk('cancelled_is_final_correct', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_settle_entry(%L::uuid, %L::date)$q$, pg_temp.u('e_to_cancel'), pg_temp.today()));
  perform pg_temp.chk('cancelled_is_final_settle', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_cancel_entry(%L::uuid, 'Cancelar de novo')$q$, pg_temp.u('e_to_cancel')));
  perform pg_temp.chk('cancelled_is_final_cancel_again', v = 'err:22023:Este lançamento já está cancelado.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt(format(
    $q$update public.finance_entries set description = 'Mudado por fora' where id = %L::uuid$q$, pg_temp.u('e_to_cancel')));
  perform pg_temp.chk('cancelled_is_final_direct_update',
    v = 'err:22023:Lançamento cancelado não pode ser alterado.', v);
end $$;

-- Estorno
do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_reverse_entry(%L::uuid, %L::date, 'Teste: antes do pagamento')$q$,
    pg_temp.u('e_inc_settled'), pg_temp.today() - 6));
  perform pg_temp.chk('reverse_before_original_date', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_reverse_entry(%L::uuid, %L::date, 'Teste: estorno futuro')$q$,
    pg_temp.u('e_inc_settled'), pg_temp.today() + 1));
  perform pg_temp.chk('reverse_future_date', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_reverse_entry(%L::uuid, %L::date, 'Teste: estorno de aberto')$q$,
    pg_temp.u('e_inc_pending'), pg_temp.today()));
  perform pg_temp.chk('reverse_open_entry_refused', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_reverse_entry(%L::uuid, %L::date, 'Teste: estorno maior', 2001)$q$,
    pg_temp.u('e_rev_partial'), pg_temp.today()));
  perform pg_temp.chk('reverse_above_original_refused', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.val(format(
    $q$select public.finance_reverse_entry(%L::uuid, %L::date, 'Cliente pediu reembolso')::text$q$,
    pg_temp.u('e_inc_settled'), pg_temp.today() - 1));
  perform pg_temp.chk('smoke_reverse_entry', v ~ '^[0-9a-f-]{36}$', v);
  if v ~ '^[0-9a-f-]{36}$' then
    perform pg_temp.remember('e_reversal', v::uuid);
  end if;
end $$;

do $$
declare
  v_kind   text;
  v_dir    text;
  v_of     uuid;
  v_status text;
  v_on     date;
  v_amount numeric;
  v_desc   text;
  v_notes  text;
  v_orig   text;
  v_event  text;
  v_reason text;
begin
  perform pg_temp.as_actor('postgres');
  select e.entry_kind, e.direction, e.reversal_of, e.status, e.settled_on, e.amount, e.description, e.notes
    into v_kind, v_dir, v_of, v_status, v_on, v_amount, v_desc, v_notes
  from public.finance_entries e where e.id = pg_temp.u('e_reversal');
  select e.status into v_orig from public.finance_entries e where e.id = pg_temp.u('e_inc_settled');
  select a.event, a.reason into v_event, v_reason from public.finance_audit_log a
  where a.entity_type = 'finance_entry' and a.entity_id = pg_temp.u('e_reversal');
  perform pg_temp.chk('reverse_creates_reversal_row',
    v_kind = 'reversal' and v_dir = 'income' and v_of = pg_temp.u('e_inc_settled') and v_status = 'settled'
    and v_on = pg_temp.today() - 1 and v_amount = 1000.00 and v_desc = 'Estorno: Teste projeto'
    and v_notes = 'Cliente pediu reembolso' and v_orig = 'settled'
    and v_event = 'reversal_created' and v_reason = 'Cliente pediu reembolso',
    format('kind=%s dir=%s status=%s amount=%s desc=%s original=%s evento=%s', v_kind, v_dir, v_status,
           v_amount, v_desc, v_orig, v_event));
end $$;

do $$
declare
  v_by      uuid;
  v_of      uuid;
  v_kind    text;
  v_cents   bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select l.reversed_by_id into v_by from public.finance_ledger(null, null) l where l.id = pg_temp.u('e_inc_settled');
  select l.reversal_of, l.entry_kind, l.amount_cents into v_of, v_kind, v_cents
  from public.finance_ledger(null, null) l where l.id = pg_temp.u('e_reversal');
  perform pg_temp.chk('ledger_reversed_by_id',
    v_by = pg_temp.u('e_reversal') and v_of = pg_temp.u('e_inc_settled') and v_kind = 'reversal' and v_cents = 100000,
    format('reversed_by_ok=%s reversal_of_ok=%s kind=%s cents=%s', v_by = pg_temp.u('e_reversal'),
           v_of = pg_temp.u('e_inc_settled'), v_kind, v_cents));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_reverse_entry(%L::uuid, %L::date, 'Teste: segundo estorno')$q$,
    pg_temp.u('e_inc_settled'), pg_temp.today()));
  perform pg_temp.chk('reverse_second_refused', v = 'err:22023:Este lançamento já tem um estorno ativo.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_reverse_entry(%L::uuid, %L::date, 'Teste: estorno de estorno')$q$,
    pg_temp.u('e_reversal'), pg_temp.today()));
  perform pg_temp.chk('reverse_of_reversal_refused', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_cancel_entry(%L::uuid, 'Teste: cancelar original')$q$, pg_temp.u('e_inc_settled')));
  perform pg_temp.chk('cancel_original_with_active_reversal', v = 'err:22023:Cancele o estorno antes.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"amount_cents":50000}'::jsonb, 'Teste: valor abaixo do estorno')$q$,
    pg_temp.u('e_inc_settled')));
  perform pg_temp.chk('correct_amount_below_reversal_refused', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_correct_entry(%L::uuid, '{"amount_cents":500}'::jsonb, 'Teste: mudar valor do estorno')$q$,
    pg_temp.u('e_reversal')));
  perform pg_temp.chk('correct_reversal_amount_refused', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare
  v       text;
  v_cents bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.val(format(
    $q$select public.finance_reverse_entry(%L::uuid, %L::date, 'Teste: estorno parcial', 500)::text$q$,
    pg_temp.u('e_rev_partial'), pg_temp.today()));
  perform pg_temp.as_actor('postgres');
  select round(e.amount * 100)::bigint into v_cents
  from public.finance_entries e where e.reversal_of = pg_temp.u('e_rev_partial') and e.status <> 'cancelled';
  perform pg_temp.chk('reverse_partial_ok', v ~ '^[0-9a-f-]{36}$' and v_cents = 500, format('%s cents=%s', v, v_cents));
end $$;

do $$
declare
  v      text;
  v_id   uuid;
  v_by   uuid;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.attempt(format(
    $q$select public.finance_cancel_entry(%L::uuid, 'Teste: desfazer o estorno')$q$, pg_temp.u('e_reversal')));
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select l.id, l.reversed_by_id into v_id, v_by
  from public.finance_ledger(null, null) l where l.id = pg_temp.u('e_inc_settled');
  perform pg_temp.chk('cancel_reversal_clears_link',
    v = 'ok:1' and v_id = pg_temp.u('e_inc_settled') and v_by is null,
    format('%s linha=%s reversed_by=%s', v, v_id is not null, v_by));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v := pg_temp.val(format(
    $q$select public.finance_reverse_entry(%L::uuid, %L::date, 'Teste: novo estorno')::text$q$,
    pg_temp.u('e_inc_settled'), pg_temp.today()));
  perform pg_temp.chk('reverse_again_after_cancelled_reversal', v ~ '^[0-9a-f-]{36}$', v);
end $$;

-- Depois de cada mutação o motivo volta a '': outro DML na mesma transação
-- (ex.: mutação GraphQL em lote que também mexa em invoices) não o herda.
do $$
declare
  t     date := pg_temp.today();
  v_id  uuid;
  v_rev uuid;
  v_cat uuid;
  v_out text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  v_id := public.finance_create_entry('income', 'Teste motivo residual', 4200, 'pending', t + 2);
  perform public.finance_correct_entry(v_id, '{"notes":"Teste"}'::jsonb, 'Teste: motivo da correção');
  v_out := 'correct=' || coalesce(current_setting('pixelry.finance_change_reason', true), '<null>');
  perform public.finance_settle_entry(v_id, t, 'Teste: motivo da liquidação');
  v_out := v_out || '|settle=' || coalesce(current_setting('pixelry.finance_change_reason', true), '<null>');
  v_rev := public.finance_reverse_entry(v_id, t, 'Teste: motivo do estorno');
  v_out := v_out || '|reverse=' || coalesce(current_setting('pixelry.finance_change_reason', true), '<null>');
  perform public.finance_cancel_entry(v_rev, 'Teste: motivo do cancelamento');
  v_out := v_out || '|cancel=' || coalesce(current_setting('pixelry.finance_change_reason', true), '<null>');
  v_cat := public.finance_create_category('Teste motivo ' || left(gen_random_uuid()::text, 8));
  perform public.finance_set_category_archived(v_cat, true, 'Teste: motivo do arquivamento');
  v_out := v_out || '|archive=' || coalesce(current_setting('pixelry.finance_change_reason', true), '<null>');
  perform pg_temp.chk('mutation_rpcs_clear_reason_after_dml',
    v_out = 'correct=|settle=|reverse=|cancel=|archive=', v_out);
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- F. Nada é apagado; campos imutáveis; auditoria imutável
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt(format('delete from public.finance_entries where id = %L::uuid', pg_temp.u('e_exp_settled')));
  perform pg_temp.chk('delete_entries_refused_postgres',
    v = 'err:42501:Lançamentos financeiros não são apagados; cancele ou estorne com motivo.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt('truncate public.finance_entries');
  perform pg_temp.chk('truncate_entries_refused_postgres', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt(format('delete from public.finance_categories where id = %L::uuid', pg_temp.u('cat_old')));
  perform pg_temp.chk('delete_categories_refused_postgres', v = 'err:42501:Categorias não são apagadas; arquive.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  -- CASCADE porque finance_entries referencia finance_categories (sem ele o
  -- Postgres recusa antes do gatilho, com 0A000). O CASCADE puxa também o
  -- gatilho de finance_entries; a mensagem exata prova que foi o de
  -- categorias (a tabela nomeada vem primeiro na lista do TRUNCATE).
  v := pg_temp.attempt('truncate public.finance_categories cascade');
  perform pg_temp.chk('truncate_categories_refused_postgres',
    v = 'err:42501:Categorias não são apagadas; arquive.', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt(format(
    $q$update public.finance_entries set direction = 'income' where id = %L::uuid$q$, pg_temp.u('e_exp_settled')));
  perform pg_temp.chk('update_direction_refused', v = 'err:22023:Campo não pode ser alterado: direction', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt(format(
    $q$update public.finance_entries set idempotency_key = 'outra-chave-123' where id = %L::uuid$q$,
    pg_temp.u('e_exp_settled')));
  perform pg_temp.chk('update_idempotency_key_refused', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt(format(
    $q$update public.finance_categories set created_by = %L::uuid where id = %L::uuid$q$,
    gen_random_uuid(), pg_temp.u('cat_income')));
  perform pg_temp.chk('update_category_created_by_refused', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt(format(
    $q$insert into public.finance_audit_log (entity_type, entity_id, action, event, actor_role)
       values ('finance_entry', %L::uuid, 'update', 'corrected', 'postgres')$q$, pg_temp.u('e_exp_settled')));
  perform pg_temp.chk('audit_insert_refused_postgres', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt(format(
    $q$update public.finance_audit_log set reason = 'forjado'
        where id = (select max(a.id) from public.finance_audit_log a where a.entity_id = %L::uuid)$q$,
    pg_temp.u('e_exp_settled')));
  perform pg_temp.chk('audit_update_refused_postgres', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt(format(
    $q$delete from public.finance_audit_log
        where id = (select max(a.id) from public.finance_audit_log a where a.entity_id = %L::uuid)$q$,
    pg_temp.u('e_exp_settled')));
  perform pg_temp.chk('audit_delete_refused_postgres', pg_temp.code(v) = '42501', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt('truncate public.finance_audit_log');
  perform pg_temp.chk('audit_truncate_refused_postgres', pg_temp.code(v) = '42501', v);
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- G. Dinheiro exato
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_type  text;
  v_prec  integer;
  v_scale integer;
begin
  perform pg_temp.as_actor('postgres');
  select c.data_type, c.numeric_precision, c.numeric_scale into v_type, v_prec, v_scale
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'finance_entries' and c.column_name = 'amount';
  perform pg_temp.chk('amount_column_is_numeric_14_2', v_type = 'numeric' and v_prec = 14 and v_scale = 2,
    format('%s(%s,%s)', v_type, v_prec, v_scale));
end $$;

do $$
declare
  v_cents  bigint;
  v_amount numeric;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select l.amount_cents into v_cents from public.finance_ledger(null, null) l where l.id = pg_temp.u('e_cent');
  perform pg_temp.as_actor('postgres');
  select e.amount into v_amount from public.finance_entries e where e.id = pg_temp.u('e_cent');
  perform pg_temp.chk('one_cent_exact', v_cents = 1 and v_amount = 0.01, format('cents=%s amount=%s', v_cents, v_amount));
end $$;

do $$
declare
  v_cents  bigint;
  v_rows   bigint;
  v_amount numeric;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select sum(l.amount_cents), count(*) into v_cents, v_rows
  from public.finance_ledger(null, null) l where l.id in (pg_temp.u('e_ten'), pg_temp.u('e_twenty'));
  perform pg_temp.as_actor('postgres');
  select sum(e.amount) into v_amount from public.finance_entries e
  where e.id in (pg_temp.u('e_ten'), pg_temp.u('e_twenty'));
  perform pg_temp.chk('ten_plus_twenty_cents_exact', v_rows = 2 and v_cents = 30 and v_amount = 0.30,
    format('linhas=%s cents=%s amount=%s', v_rows, v_cents, v_amount));
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- H. Invoices e compatibilidade com create-invoice, payment-webhook e dashboard
-- ════════════════════════════════════════════════════════════════════════════

-- Uma invoice por status (inseridas como postgres, para cli_b).
do $$
declare
  v_cli uuid;
  t     date := pg_temp.today();
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.remember('inv_pending', gen_random_uuid());
  perform pg_temp.remember('inv_overdue', gen_random_uuid());
  perform pg_temp.remember('inv_paid', gen_random_uuid());
  perform pg_temp.remember('inv_paid_no_date', gen_random_uuid());
  perform pg_temp.remember('inv_cancelled', gen_random_uuid());
  perform pg_temp.remember('inv_cancelled_paid_at', gen_random_uuid());
  perform pg_temp.remember('inv_pending_paid_at', gen_random_uuid());
  perform pg_temp.remember('inv_error', gen_random_uuid());
  perform pg_temp.remember('inv_null', gen_random_uuid());
  v_cli := pg_temp.u('cli_b');

  insert into public.invoices (id, client_id, amount, description, due_date, status, paid_at) values
    (pg_temp.u('inv_pending'),           v_cli,  100.00, 'Teste cobrança pendente',          t + 5, 'pending',   null),
    (pg_temp.u('inv_overdue'),           v_cli,  101.00, 'Teste cobrança vencida',           t - 5, 'overdue',   null),
    (pg_temp.u('inv_paid'),              v_cli, 1234.56, 'Teste cobrança paga',              t - 3, 'paid',      '2026-11-02 01:30:00+00'),
    (pg_temp.u('inv_paid_no_date'),      v_cli,  103.00, 'Teste paga sem data',              null,  'paid',      null),
    (pg_temp.u('inv_cancelled'),         v_cli,  104.00, 'Teste cancelada',                  null,  'cancelled', null),
    (pg_temp.u('inv_cancelled_paid_at'), v_cli,  105.00, 'Teste cancelada com pagamento',    null,  'cancelled', '2026-10-20 15:00:00+00'),
    (pg_temp.u('inv_pending_paid_at'),   v_cli,  106.00, 'Teste pendente com pagamento',     null,  'pending',   '2026-10-21 15:00:00+00'),
    (pg_temp.u('inv_error'),             v_cli,  107.00, 'Teste erro técnico',               null,  'error',     null),
    (pg_temp.u('inv_null'),              v_cli,  108.00, 'Teste sem status',                 null,  null,        null);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.ledger_text(pg_temp.u('inv_pending'));
  perform pg_temp.chk('invoice_status_pending', v = 'pending|pending|null', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.ledger_text(pg_temp.u('inv_overdue'));
  perform pg_temp.chk('invoice_status_overdue', v = 'pending|overdue|null', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.ledger_text(pg_temp.u('inv_paid'));
  perform pg_temp.chk('invoice_status_paid', v = 'settled|paid|2026-11-01', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.ledger_text(pg_temp.u('inv_paid_no_date'));
  perform pg_temp.chk('invoice_status_paid_without_paid_at', v = 'settled|paid|null', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.ledger_text(pg_temp.u('inv_cancelled'));
  perform pg_temp.chk('invoice_status_cancelled', v = 'cancelled|cancelled|null', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.ledger_text(pg_temp.u('inv_cancelled_paid_at'));
  perform pg_temp.chk('invoice_status_cancelled_with_paid_at', v = 'invalid|cancelled|2026-10-20', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.ledger_text(pg_temp.u('inv_pending_paid_at'));
  perform pg_temp.chk('invoice_status_pending_with_paid_at', v = 'invalid|pending|2026-10-21', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.ledger_text(pg_temp.u('inv_error'));
  perform pg_temp.chk('invoice_status_error', v = 'invalid|error|null', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.ledger_text(pg_temp.u('inv_null'));
  perform pg_temp.chk('invoice_status_null', v = 'invalid|null|null', v);
end $$;

do $$
declare
  v_on    date;
  v_at    timestamptz;
  v_cents bigint;
  v_name  text;
  v_src   text;
  v_dir   text;
  v_del   boolean;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select l.settled_on, l.settled_at, l.amount_cents, l.counterparty_name, l.source, l.direction, l.is_deleted_at_source
    into v_on, v_at, v_cents, v_name, v_src, v_dir, v_del
  from public.finance_ledger(null, null) l where l.id = pg_temp.u('inv_paid');
  perform pg_temp.chk('invoice_settled_on_sao_paulo',
    v_on = date '2026-11-01' and v_at = timestamptz '2026-11-02 01:30:00+00' and v_cents = 123456
    and v_name = 'Teste cli_b' and v_src = 'invoice' and v_dir = 'income' and not v_del,
    format('settled_on=%s cents=%s nome=%s', v_on, v_cents, v_name));
end $$;

do $$
declare
  v_event text;
  v_role  text;
  v_actor uuid;
  v_n     bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_null');
  select a.event, a.actor_role, a.actor_id into v_event, v_role, v_actor from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_pending');
  perform pg_temp.chk('invoice_insert_audited_created',
    v_event = 'created' and v_role = session_user::text and v_actor is null and v_n = 1,
    format('evento=%s papel=%s status_null_auditado=%s', v_event, v_role, v_n));
end $$;

-- Fluxo create-invoice (service_role): draft → pending; draft não audita.
do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.remember('inv_flow', gen_random_uuid());
  perform pg_temp.remember('inv_flow_pref', gen_random_uuid());
  perform pg_temp.as_actor('service_role');
  v := pg_temp.attempt(format(
    $q$insert into public.invoices (id, client_id, amount, description, due_date, status, idempotency_key)
       values (%L::uuid, %L::uuid, 99.90, 'Teste fluxo create-invoice', %L::date, 'draft', %L)$q$,
    pg_temp.u('inv_flow'), pg_temp.u('cli_a'), pg_temp.today() + 7, 'finance-test-' || pg_temp.u('inv_flow')::text));
  perform pg_temp.chk('invoice_draft_insert_ok', v = 'ok:1', v);
end $$;

do $$
declare
  v_n      bigint;
  v_exists bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_exists from public.invoices i where i.id = pg_temp.u('inv_flow') and i.status = 'draft';
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_flow');
  perform pg_temp.chk('invoice_draft_insert_not_audited', v_exists = 1 and v_n = 0,
    format('draft=%s auditorias=%s', v_exists, v_n));
end $$;

do $$
declare
  v   text;
  v_n bigint;
begin
  perform pg_temp.as_actor('service_role');
  v := pg_temp.attempt(format(
    $q$update public.invoices set description = 'Teste fluxo create-invoice (ajuste)' where id = %L::uuid$q$,
    pg_temp.u('inv_flow')));
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_flow');
  perform pg_temp.chk('invoice_draft_update_not_audited', v = 'ok:1' and v_n = 0, format('%s auditorias=%s', v, v_n));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.ledger_text(pg_temp.u('inv_flow'));
  perform pg_temp.chk('invoice_draft_not_in_ledger', v = 'absent', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('service_role');
  v := pg_temp.attempt(format(
    $q$update public.invoices
          set status = 'pending', mp_preference_id = %L, payment_url = 'https://example.invalid/pay',
              qr_code = null, qr_code_text = null, updated_at = now()
        where id = %L::uuid$q$,
    'finance-test-pref-' || pg_temp.u('inv_flow_pref')::text, pg_temp.u('inv_flow')));
  perform pg_temp.chk('invoice_finalize_ok', v = 'ok:1', v);
end $$;

do $$
declare
  v_n      bigint;
  v_event  text;
  v_actor  uuid;
  v_role   text;
  v_reason text;
  v_old    text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_flow');
  select a.event, a.actor_id, a.actor_role, a.reason, a.old_values ->> 'status'
    into v_event, v_actor, v_role, v_reason, v_old
  from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_flow');
  perform pg_temp.chk('invoice_issue_audited_issued',
    v_n = 1 and v_event = 'issued' and v_actor is null and v_role = 'service_role' and v_reason is null
    and v_old = 'draft',
    format('n=%s evento=%s papel=%s motivo=%s antigo=%s', v_n, v_event, v_role, v_reason, v_old));
end $$;

do $$
declare
  v_link boolean;
  v_text text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  select l.has_payment_link into v_link from public.finance_ledger(null, null) l where l.id = pg_temp.u('inv_flow');
  v_text := pg_temp.ledger_text(pg_temp.u('inv_flow'));
  perform pg_temp.chk('invoice_issued_in_ledger', v_link and v_text = 'pending|pending|null',
    format('link=%s %s', v_link, v_text));
end $$;

do $$
declare
  v   text;
  v_n bigint;
begin
  perform pg_temp.as_actor('service_role');
  v := pg_temp.attempt(format(
    $q$update public.invoices set payment_url = 'https://example.invalid/pay2', qr_code = 'qr-teste', updated_at = now()
        where id = %L::uuid$q$, pg_temp.u('inv_flow')));
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_flow');
  perform pg_temp.chk('invoice_metadata_change_not_audited', v = 'ok:1' and v_n = 1, format('%s auditorias=%s', v, v_n));
end $$;

-- Webhook: update guardado por status, como em payment-webhook.
do $$
declare v text;
begin
  perform pg_temp.as_actor('service_role');
  v := pg_temp.attempt(format(
    $q$update public.invoices set status = 'paid', paid_at = now(), updated_at = now()
        where mp_preference_id = %L and status = 'pending'$q$,
    'finance-test-pref-' || pg_temp.u('inv_flow_pref')::text));
  perform pg_temp.chk('invoice_webhook_update_one_row', v = 'ok:1', v);
end $$;

do $$
declare
  v_event  text;
  v_role   text;
  v_actor  uuid;
  v_fields text[];
begin
  perform pg_temp.as_actor('postgres');
  select a.event, a.actor_role, a.actor_id, a.changed_fields into v_event, v_role, v_actor, v_fields
  from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_flow') and a.event = 'paid';
  perform pg_temp.chk('invoice_webhook_audited_paid',
    v_event = 'paid' and v_role = 'service_role' and v_actor is null and v_fields = array['paid_at', 'status'],
    format('evento=%s papel=%s campos=%s', v_event, v_role, v_fields));
end $$;

-- Rascunho apagado pelo create-invoice (rollbackDraft) não audita.
do $$
declare
  v   text;
  v_n bigint;
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.remember('inv_draft_del', gen_random_uuid());
  perform pg_temp.as_actor('service_role');
  v := pg_temp.attempt(format(
    $q$insert into public.invoices (id, client_id, amount, description, status)
       values (%L::uuid, %L::uuid, 55.00, 'Teste rascunho descartado', 'draft')$q$,
    pg_temp.u('inv_draft_del'), pg_temp.u('cli_a')));
  perform pg_temp.as_actor('service_role');
  v := v || ' / ' || pg_temp.attempt(format(
    $q$delete from public.invoices where id = %L::uuid and status = 'draft'$q$, pg_temp.u('inv_draft_del')));
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_draft_del');
  perform pg_temp.chk('invoice_draft_delete_not_audited', v = 'ok:1 / ok:1' and v_n = 0,
    format('%s auditorias=%s', v, v_n));
end $$;

-- Cancelamento pelo dashboard (manager com JWT, sem concessão financeira).
do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.remember('inv_dash', gen_random_uuid());
  insert into public.invoices (id, client_id, amount, description, due_date, status)
  values (pg_temp.u('inv_dash'), pg_temp.u('cli_a'), 210.00, 'Teste cancelamento no dashboard',
          pg_temp.today() + 4, 'pending');
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v := pg_temp.attempt(format(
    $q$update public.invoices set status = 'cancelled' where id = %L::uuid$q$, pg_temp.u('inv_dash')));
  perform pg_temp.chk('invoice_dashboard_cancel_one_row', v = 'ok:1', v);
end $$;

do $$
declare
  v_event  text;
  v_actor  uuid;
  v_role   text;
  v_reason text;
begin
  perform pg_temp.as_actor('postgres');
  select a.event, a.actor_id, a.actor_role, a.reason into v_event, v_actor, v_role, v_reason
  from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_dash') and a.action = 'update';
  perform pg_temp.chk('invoice_dashboard_cancel_audited',
    v_event = 'cancelled' and v_actor = pg_temp.u('mgr_none') and v_role = 'authenticated' and v_reason is null,
    format('evento=%s papel=%s motivo=%s', v_event, v_role, v_reason));
end $$;

-- Leitura de invoices fora do módulo continua igual.
do $$
declare
  v_total bigint;
  v_seen  text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_total from public.invoices i where i.client_id = pg_temp.u('cli_b');
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v_seen := pg_temp.val(format('select count(*) from public.invoices i where i.client_id = %L::uuid', pg_temp.u('cli_b')));
  perform pg_temp.chk('manager_without_grant_reads_invoices', v_total >= 9 and v_seen = v_total::text,
    format('total=%s visto=%s', v_total, v_seen));
end $$;

do $$
declare
  v_own    bigint;
  v_other  bigint;
  v_seen   text;
  v_seen_b text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_own from public.invoices i where i.client_id = pg_temp.u('cli_a');
  select count(*) into v_other from public.invoices i where i.client_id = pg_temp.u('cli_b');
  perform pg_temp.as_actor('authenticated', pg_temp.u('cli_a'));
  v_seen := pg_temp.val('select count(*) from public.invoices');
  v_seen_b := pg_temp.val(format('select count(*) from public.invoices i where i.client_id = %L::uuid', pg_temp.u('cli_b')));
  perform pg_temp.chk('client_reads_only_own_invoices',
    v_own > 0 and v_other > 0 and v_seen = v_own::text and v_seen_b = '0',
    format('proprias=%s/%s de_outro=%s (existem %s)', v_seen, v_own, v_seen_b, v_other));
end $$;

-- Auditoria forçada a falhar: webhook e dashboard continuam funcionando.
do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.remember('inv_fail_hook', gen_random_uuid());
  perform pg_temp.remember('inv_fail_pref', gen_random_uuid());
  perform pg_temp.remember('inv_fail_dash', gen_random_uuid());
  insert into public.invoices (id, client_id, amount, description, due_date, status, mp_preference_id) values
    (pg_temp.u('inv_fail_hook'), pg_temp.u('cli_a'), 300.00, 'Teste webhook com auditoria quebrada',
     pg_temp.today() + 2, 'pending', 'finance-test-pref-' || pg_temp.u('inv_fail_pref')::text),
    (pg_temp.u('inv_fail_dash'), pg_temp.u('cli_a'), 301.00, 'Teste dashboard com auditoria quebrada',
     pg_temp.today() + 2, 'pending', null);
  alter table public.finance_audit_log add constraint finance_test_fail check (false) not valid;
end $$;

do $$
declare
  v        text;
  v_status text;
  v_paid   timestamptz;
  v_n      bigint;
begin
  perform pg_temp.as_actor('service_role');
  v := pg_temp.attempt(format(
    $q$update public.invoices set status = 'paid', paid_at = now(), updated_at = now()
        where mp_preference_id = %L and status = 'pending'$q$,
    'finance-test-pref-' || pg_temp.u('inv_fail_pref')::text));
  perform pg_temp.as_actor('postgres');
  select i.status, i.paid_at into v_status, v_paid from public.invoices i where i.id = pg_temp.u('inv_fail_hook');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_fail_hook');
  perform pg_temp.chk('audit_failure_webhook_still_updates',
    v = 'ok:1' and v_status = 'paid' and v_paid is not null and v_n = 1,
    format('%s status=%s auditorias=%s', v, v_status, v_n));
end $$;

do $$
declare
  v        text;
  v_status text;
  v_n      bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_none'));
  v := pg_temp.attempt(format(
    $q$update public.invoices set status = 'cancelled' where id = %L::uuid$q$, pg_temp.u('inv_fail_dash')));
  perform pg_temp.as_actor('postgres');
  select i.status into v_status from public.invoices i where i.id = pg_temp.u('inv_fail_dash');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_fail_dash');
  perform pg_temp.chk('audit_failure_dashboard_cancel_still_updates',
    v = 'ok:1' and v_status = 'cancelled' and v_n = 1,
    format('%s status=%s auditorias=%s', v, v_status, v_n));
end $$;

do $$
begin
  perform pg_temp.as_actor('postgres');
  alter table public.finance_audit_log drop constraint finance_test_fail;
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- I. Exclusões em cascata (cliente e autor)
-- ════════════════════════════════════════════════════════════════════════════
do $$
begin
  perform pg_temp.as_actor('postgres');
  perform pg_temp.remember('inv_gone_paid', gen_random_uuid());
  perform pg_temp.remember('inv_gone_pending', gen_random_uuid());
  insert into public.invoices (id, client_id, amount, description, due_date, status, paid_at, mp_preference_id, payment_url)
  values
    (pg_temp.u('inv_gone_paid'), pg_temp.u('cli_gone'), 450.00, 'Teste paga de cliente apagado', null, 'paid',
     now() - interval '1 day', 'finance-test-pref-' || pg_temp.u('inv_gone_paid')::text, 'https://example.invalid/pay'),
    (pg_temp.u('inv_gone_pending'), pg_temp.u('cli_gone'), 75.00, 'Teste pendente de cliente apagado',
     pg_temp.today() + 5, 'pending', null, null, null);

  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_gone_link', public.finance_create_entry(
    p_direction    => 'income',
    p_description  => 'Teste receita de cliente apagado',
    p_amount_cents => 33000,
    p_status       => 'pending',
    p_due_date     => pg_temp.today() + 20,
    p_client_id    => pg_temp.u('cli_gone')));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt(format('delete from auth.users where id = %L::uuid', pg_temp.u('cli_gone')));
  perform pg_temp.chk('client_user_deletion_ok', v = 'ok:1', v);
end $$;

do $$
declare
  v_live   bigint;
  v_n      bigint;
  v_action text;
  v_actor  uuid;
  v_role   text;
  v_cents  text;
  v_status text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_live from public.invoices i where i.id = pg_temp.u('inv_gone_paid');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_gone_paid') and a.event = 'deleted';
  select a.action, a.actor_id, a.actor_role, a.old_values ->> 'amount_cents', a.old_values ->> 'status'
    into v_action, v_actor, v_role, v_cents, v_status
  from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_gone_paid') and a.event = 'deleted';
  perform pg_temp.chk('client_deletion_audits_deleted',
    v_live = 0 and v_n = 1 and v_action = 'delete' and v_actor is null and v_role = session_user::text
    and v_cents = '45000' and v_status = 'paid',
    format('viva=%s n=%s action=%s papel=%s cents=%s status=%s', v_live, v_n, v_action, v_role, v_cents, v_status));
end $$;

do $$
declare
  v_del    boolean;
  v_status text;
  v_src    text;
  v_name   text;
  v_cents  bigint;
  v_on     date;
  v_link   boolean;
  v_client uuid;
  v_ref    text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  select l.is_deleted_at_source, l.status, l.source_status, l.counterparty_name, l.amount_cents, l.settled_on,
         l.has_payment_link, l.client_id, l.source_reference
    into v_del, v_status, v_src, v_name, v_cents, v_on, v_link, v_client, v_ref
  from public.finance_ledger(null, null) l where l.id = pg_temp.u('inv_gone_paid');
  perform pg_temp.chk('client_deletion_paid_invoice_stays_in_ledger',
    v_del and v_status = 'settled' and v_src = 'deleted' and v_name = 'Cliente removido' and v_cents = 45000
    and v_on = ((now() - interval '1 day') at time zone 'America/Sao_Paulo')::date and not v_link
    and v_client = pg_temp.u('cli_gone') and v_ref = 'finance-test-pref-' || pg_temp.u('inv_gone_paid')::text,
    format('apagada=%s status=%s fonte=%s nome=%s cents=%s', v_del, v_status, v_src, v_name, v_cents));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  v := pg_temp.ledger_text(pg_temp.u('inv_gone_pending'));
  perform pg_temp.chk('client_deletion_pending_invoice_cancelled', v = 'cancelled|deleted|null', v);
end $$;

do $$
declare
  v_client uuid;
  v_name   text;
  v_status text;
begin
  perform pg_temp.as_actor('postgres');
  select e.client_id, e.counterparty_name, e.status into v_client, v_name, v_status
  from public.finance_entries e where e.id = pg_temp.u('e_gone_link');
  perform pg_temp.chk('client_deletion_entry_keeps_counterparty',
    v_client is null and v_name = 'Teste cli_gone' and v_status = 'pending',
    format('client_id=%s contraparte=%s', v_client, v_name));
end $$;

do $$
declare
  v_n      bigint;
  v_fields text[];
  v_role   text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*) into v_n from public.finance_audit_log a
  where a.entity_type = 'finance_entry' and a.entity_id = pg_temp.u('e_gone_link') and a.event = 'reference_cleared';
  select a.changed_fields, a.actor_role into v_fields, v_role from public.finance_audit_log a
  where a.entity_type = 'finance_entry' and a.entity_id = pg_temp.u('e_gone_link') and a.event = 'reference_cleared';
  perform pg_temp.chk('client_deletion_entry_reference_cleared',
    v_n = 1 and v_fields = array['client_id'] and v_role = session_user::text,
    format('n=%s campos=%s papel=%s', v_n, v_fields, v_role));
end $$;

-- Autor de lançamentos apagado: os lançamentos ficam.
do $$
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('creator'));
  perform pg_temp.remember('e_creator_a', public.finance_create_entry(
    p_direction    => 'expense',
    p_description  => 'Teste despesa do autor',
    p_amount_cents => 12000,
    p_status       => 'pending',
    p_due_date     => pg_temp.today() + 15));
  perform pg_temp.as_actor('authenticated', pg_temp.u('creator'));
  perform pg_temp.remember('e_creator_b', public.finance_create_entry(
    p_direction    => 'expense',
    p_description  => 'Teste despesa do autor cancelada',
    p_amount_cents => 8000,
    p_status       => 'forecast',
    p_due_date     => pg_temp.today() + 30));
  perform pg_temp.as_actor('authenticated', pg_temp.u('creator'));
  perform public.finance_cancel_entry(pg_temp.u('e_creator_b'), 'Teste: lançado por engano');
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('postgres');
  v := pg_temp.attempt(format('delete from auth.users where id = %L::uuid', pg_temp.u('creator')));
  perform pg_temp.chk('creator_user_deletion_ok', v = 'ok:1', v);
end $$;

do $$
declare
  v_n         bigint;
  v_by_ok     bigint;
  v_cancel_by uuid;
  v_status    text;
begin
  perform pg_temp.as_actor('postgres');
  select count(*), count(*) filter (where e.created_by = pg_temp.u('creator')) into v_n, v_by_ok
  from public.finance_entries e where e.id in (pg_temp.u('e_creator_a'), pg_temp.u('e_creator_b'));
  select e.cancelled_by, e.status into v_cancel_by, v_status
  from public.finance_entries e where e.id = pg_temp.u('e_creator_b');
  perform pg_temp.chk('creator_deletion_preserves_entries',
    v_n = 2 and v_by_ok = 2 and v_cancel_by = pg_temp.u('creator') and v_status = 'cancelled',
    format('linhas=%s autor_ok=%s status=%s', v_n, v_by_ok, v_status));
end $$;

do $$
declare v_name text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  select l.created_by_name into v_name from public.finance_ledger(null, null) l where l.id = pg_temp.u('e_creator_a');
  perform pg_temp.chk('creator_deletion_ledger_person_removed', v_name = 'Pessoa removida', v_name);
end $$;

do $$
declare
  v_events text;
  v_names  text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select string_agg(h.event, ',' order by h.ordinality), string_agg(distinct h.actor_name, ',')
    into v_events, v_names
  from public.finance_entry_history('manual', pg_temp.u('e_creator_b')) with ordinality as h;
  perform pg_temp.chk('creator_deletion_history_person_removed',
    v_events = 'cancelled,created' and v_names = 'Pessoa removida',
    format('eventos=%s atores=%s', v_events, v_names));
end $$;

do $$
declare
  v_event  text;
  v_action text;
begin
  perform pg_temp.as_actor('postgres');
  select a.event, a.action into v_event, v_action from public.finance_audit_log a
  where a.entity_type = 'finance_access_grant' and a.entity_id = pg_temp.u('creator') and a.action = 'delete';
  perform pg_temp.chk('creator_deletion_grant_removed_audited', v_event = 'access_removed' and v_action = 'delete',
    format('evento=%s action=%s', v_event, v_action));
end $$;

-- Duplicidade: cobrança paga apagada, recriada com o mesmo id e apagada de
-- novo. Viva, aparece só como viva; apagada duas vezes (dois eventos
-- 'deleted'), aparece uma vez só; deleted_invoice_count sobe exatamente 1.
do $$
declare
  v_before bigint;
  v_mid    bigint;
  v_after  bigint;
  v_live   text;
  v_gone   text;
  v_n_del  bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  select m.deleted_invoice_count into v_before from public.finance_overview_meta() m;

  perform pg_temp.as_actor('postgres');
  perform pg_temp.remember('inv_dup', gen_random_uuid());
  insert into public.invoices (id, client_id, amount, description, status, paid_at)
  values (pg_temp.u('inv_dup'), pg_temp.u('cli_a'), 210.00, 'Teste cobrança restaurada', 'paid',
          now() - interval '2 days');
  delete from public.invoices i where i.id = pg_temp.u('inv_dup');
  insert into public.invoices (id, client_id, amount, description, status, paid_at)
  values (pg_temp.u('inv_dup'), pg_temp.u('cli_a'), 210.00, 'Teste cobrança restaurada', 'paid',
          now() - interval '2 days');

  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  select concat_ws('|', count(*)::text, coalesce(bool_or(l.is_deleted_at_source)::text, 'null'),
                   coalesce(min(l.status), 'null'))
    into v_live
  from public.finance_ledger(null, null) l where l.id = pg_temp.u('inv_dup');
  select m.deleted_invoice_count into v_mid from public.finance_overview_meta() m;
  perform pg_temp.chk('restored_invoice_listed_once',
    v_live = '1|false|settled' and v_mid = v_before,
    format('ledger=%s apagadas %s→%s', v_live, v_before, v_mid));

  perform pg_temp.as_actor('postgres');
  delete from public.invoices i where i.id = pg_temp.u('inv_dup');
  select count(*) into v_n_del from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.entity_id = pg_temp.u('inv_dup') and a.event = 'deleted';

  perform pg_temp.as_actor('authenticated', pg_temp.u('owner'));
  select concat_ws('|', count(*)::text, coalesce(bool_or(l.is_deleted_at_source)::text, 'null'),
                   coalesce(min(l.status), 'null'))
    into v_gone
  from public.finance_ledger(null, null) l where l.id = pg_temp.u('inv_dup');
  select m.deleted_invoice_count into v_after from public.finance_overview_meta() m;
  perform pg_temp.chk('invoice_deleted_twice_listed_once',
    v_n_del = 2 and v_gone = '1|true|settled' and v_after = v_before + 1,
    format('eventos_deleted=%s ledger=%s apagadas %s→%s', v_n_del, v_gone, v_before, v_after));
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- J. Fumaça: janela do ledger, metadados, histórico, clientes
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  t date := pg_temp.today();
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_win_old_settled', public.finance_create_entry(
    p_direction => 'expense', p_description => 'Teste janela pago antigo', p_amount_cents => 1100,
    p_status => 'settled', p_settled_on => t - 500));
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_win_open_old', public.finance_create_entry(
    p_direction => 'expense', p_description => 'Teste janela aberto antigo', p_amount_cents => 1200,
    p_status => 'pending', p_due_date => t - 600));
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  perform pg_temp.remember('e_win_in', public.finance_create_entry(
    p_direction => 'expense', p_description => 'Teste janela pago dentro', p_amount_cents => 1300,
    p_status => 'settled', p_settled_on => t - 380, p_competence_date => t - 381));
end $$;

do $$
declare
  t      date := pg_temp.today();
  v_old  bigint;
  v_open bigint;
  v_in   bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select count(*) filter (where l.id = pg_temp.u('e_win_old_settled')),
         count(*) filter (where l.id = pg_temp.u('e_win_open_old')),
         count(*) filter (where l.id = pg_temp.u('e_win_in'))
    into v_old, v_open, v_in
  from public.finance_ledger(t - 400, t - 370) l;
  perform pg_temp.chk('smoke_ledger_window',
    v_old = 0 and v_open = 1 and v_in = 1,
    format('pago_fora=%s aberto_fora=%s pago_dentro=%s', v_old, v_open, v_in));
end $$;

do $$
declare
  t       date := pg_temp.today();
  v_rows  bigint;
  v_min   bigint;
  v_max   bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select count(*), min(l.total_rows), max(l.total_rows) into v_rows, v_min, v_max
  from public.finance_ledger(t - 400, t - 370) l;
  perform pg_temp.chk('ledger_window_total_rows', v_rows > 0 and v_min = v_rows and v_max = v_rows,
    format('linhas=%s total_rows=%s..%s', v_rows, v_min, v_max));
end $$;

do $$
declare
  v_rows bigint;
  v_max  bigint;
  v_tot  bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select count(*), max(l.total_rows) into v_rows, v_max from public.finance_ledger(null, null) l;
  perform pg_temp.as_actor('postgres');
  select (select count(*) from public.invoices i where i.status is distinct from 'draft')
       + (select count(*) from public.finance_entries e)
       + (select count(distinct a.entity_id) from public.finance_audit_log a
           where a.entity_type = 'invoice' and a.event = 'deleted'
             and not exists (select 1 from public.invoices li where li.id = a.entity_id))
    into v_tot;
  perform pg_temp.chk('ledger_full_counts_all_sources', v_rows = v_tot and v_max = v_tot,
    format('linhas=%s total_rows=%s esperado=%s', v_rows, v_max, v_tot));
end $$;

do $$
declare
  v_rows bigint;
  v_bad  bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  -- Ordem de saída da função (WITH ORDINALITY): reference_date desc nulls last.
  select count(*),
         count(*) filter (where (x.prev is not null and x.d is not null and x.d > x.prev)
                             or (x.prev_null and x.d is not null))
    into v_rows, v_bad
  from (
    select f.reference_date                                          as d,
           lag(f.reference_date) over (order by f.ordinality)         as prev,
           lag(f.reference_date is null) over (order by f.ordinality) as prev_null
    from public.finance_ledger(null, null) with ordinality as f
  ) x;
  perform pg_temp.chk('ledger_ordered_by_reference_date', v_rows > 10 and v_bad = 0,
    format('linhas=%s fora_de_ordem=%s', v_rows, v_bad));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.attempt(format('select * from public.finance_ledger(%L::date, null)', pg_temp.today()));
  perform pg_temp.chk('ledger_window_one_null', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.attempt(format('select * from public.finance_ledger(%L::date, %L::date)',
                              pg_temp.today(), pg_temp.today() - 1));
  perform pg_temp.chk('ledger_window_inverted', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare
  v_rows      bigint;
  v_today     date;
  v_installed timestamptz;
  v_first     date;
  v_last      timestamptz;
  v_inv       bigint;
  v_del       bigint;
  v_ent       bigint;
  v_exp       bigint;
  v_cat       bigint;
  x_inv       bigint;
  x_del       bigint;
  x_ent       bigint;
  x_exp       bigint;
  x_cat       bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select count(*) into v_rows from public.finance_overview_meta();
  select m.today, m.audit_installed_at, m.first_record_on, m.last_change_at, m.invoice_count,
         m.deleted_invoice_count, m.entry_count, m.expense_count, m.category_count
    into v_today, v_installed, v_first, v_last, v_inv, v_del, v_ent, v_exp, v_cat
  from public.finance_overview_meta() m;

  perform pg_temp.as_actor('postgres');
  select count(*) into x_inv from public.invoices i where i.status is distinct from 'draft';
  select count(distinct a.entity_id) into x_del from public.finance_audit_log a
  where a.entity_type = 'invoice' and a.event = 'deleted'
    and not exists (select 1 from public.invoices li where li.id = a.entity_id);
  select count(*) into x_ent from public.finance_entries;
  select count(*) into x_exp from public.finance_entries e where e.direction = 'expense' and e.status <> 'cancelled';
  select count(*) into x_cat from public.finance_categories c where c.archived_at is null;

  perform pg_temp.chk('smoke_overview_meta',
    v_rows = 1 and v_today = pg_temp.today() and v_installed is not null and v_last is not null
    and v_first <= pg_temp.today() - 600
    and v_inv = x_inv and v_del = x_del and v_del >= 2 and v_ent = x_ent and v_exp = x_exp and v_exp > 0
    and v_cat = x_cat,
    format('today=%s inv=%s/%s del=%s/%s ent=%s/%s exp=%s/%s cat=%s/%s first=%s',
           v_today, v_inv, x_inv, v_del, x_del, v_ent, x_ent, v_exp, x_exp, v_cat, x_cat, v_first));
end $$;

do $$
declare
  v_events text;
  v_names  text;
  v_total  bigint;
  v_n      bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select string_agg(h.event, ',' order by h.ordinality), string_agg(distinct h.actor_name, ','),
         max(h.total_rows), count(*)
    into v_events, v_names, v_total, v_n
  from public.finance_entry_history('invoice', pg_temp.u('inv_flow')) with ordinality as h;
  perform pg_temp.chk('smoke_entry_history_invoice_system',
    v_events = 'paid,issued' and v_names = 'Sistema (Mercado Pago / Edge Function)' and v_total = 2 and v_n = 2,
    format('eventos=%s atores=%s total=%s', v_events, v_names, v_total));
end $$;

do $$
declare
  v_events text;
  v_names  text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select string_agg(h.event, ',' order by h.ordinality), string_agg(distinct h.actor_name, ',')
    into v_events, v_names
  from public.finance_entry_history('invoice', pg_temp.u('inv_pending')) with ordinality as h;
  perform pg_temp.chk('entry_history_database_admin', v_events = 'created' and v_names = 'Administração do banco',
    format('eventos=%s atores=%s', v_events, v_names));
end $$;

do $$
declare
  v_event  text;
  v_name   text;
  v_reason text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  select h.event, h.actor_name, h.reason into v_event, v_name, v_reason
  from public.finance_entry_history('manual', pg_temp.u('e_to_correct')) h
  where h.event = 'corrected';
  perform pg_temp.chk('entry_history_manual_corrected',
    v_event = 'corrected' and v_name = 'Teste mgr_manage' and v_reason = 'Ajuste de teste do valor',
    format('evento=%s ator=%s motivo=%s', v_event, v_name, v_reason));
end $$;

do $$
declare v text;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_read'));
  v := pg_temp.attempt(format($q$select * from public.finance_entry_history('pix', %L::uuid)$q$, pg_temp.u('inv_flow')));
  perform pg_temp.chk('entry_history_invalid_source', pg_temp.code(v) = '22023', v);
end $$;

do $$
declare
  v_a    text;
  v_emp  bigint;
  v_gone bigint;
begin
  perform pg_temp.as_actor('authenticated', pg_temp.u('mgr_manage'));
  select c.display_name into v_a from public.finance_clients() c where c.id = pg_temp.u('cli_a');
  select count(*) into v_emp from public.finance_clients() c
  where c.id in (pg_temp.u('emp_none'), pg_temp.u('owner'), pg_temp.u('mgr_read'));
  select count(*) into v_gone from public.finance_clients() c where c.id = pg_temp.u('cli_gone');
  perform pg_temp.chk('smoke_clients', v_a = 'Empresa Teste A' and v_emp = 0 and v_gone = 0,
    format('cli_a=%s internos=%s apagado=%s', v_a, v_emp, v_gone));
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- Resumo
-- ════════════════════════════════════════════════════════════════════════════
do $$
begin
  perform pg_temp.as_actor('postgres');
end $$;

select t.seq                                        as n,
       case when t.ok then 'ok' else 'FALHOU' end   as resultado,
       t.case_id                                    as caso,
       case when t.ok then null else t.detail end   as detalhe
from pg_temp.finance_t t
order by t.seq;

select count(*) filter (where t.ok)     as passaram,
       count(*) filter (where not t.ok) as falharam,
       count(*)                         as total
from pg_temp.finance_t t;

do $$
declare
  -- Um por chamada literal de pg_temp.chk neste arquivo (o run.sh confere).
  v_expected constant integer := 232;
  v_total    bigint;
  v_failed   bigint;
  v_dups     bigint;
begin
  perform pg_temp.as_actor('postgres');
  select count(*), count(*) filter (where not t.ok), count(*) - count(distinct t.case_id)
    into v_total, v_failed, v_dups
  from pg_temp.finance_t t;

  if v_dups > 0 then
    raise exception 'finance_rls: % id(s) de caso repetido(s)', v_dups;
  end if;
  if v_total <> v_expected then
    raise exception 'finance_rls: esperados % casos, registrados % (algum caso não rodou?)', v_expected, v_total;
  end if;
  if v_failed > 0 then
    raise exception 'finance_rls: % de % caso(s) falharam', v_failed, v_total;
  end if;
  raise notice 'finance_rls: % casos, todos passaram.', v_total;
end $$;

rollback;
