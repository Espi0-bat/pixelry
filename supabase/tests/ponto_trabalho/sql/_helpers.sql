-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers dos testes do banco (schema `tests`). Só existe no banco descartável.
--
-- Como funciona:
-- - Cada asserção emite um NOTICE "PT {json}" que o run.mjs lê e imprime. O json
--   leva o papel REAL da conexão no momento da asserção (current_user), para
--   ficar visível que o caso rodou como authenticated/anon e não como postgres.
-- - Nenhuma asserção levanta erro: uma falha não interrompe o arquivo.
-- - tests.throws executa a SQL numa subtransação e SEMPRE a desfaz, tenha dado
--   erro ou não; uma asserção de erro nunca deixa efeito colateral.
-- - Valores entre comandos (ids, JSON de retorno) ficam em variáveis de sessão
--   locais à transação (set_config(..., true)), lidas com tests.var/uvar/jvar.
-- - login/logout trocam o papel com set_config('role', ...), como o PostgREST
--   faz com SET LOCAL ROLE, e gravam request.jwt.claims. As funções que trocam
--   de papel são SECURITY INVOKER (Postgres não deixa trocar de papel dentro de
--   SECURITY DEFINER).
-- - tests.admin_* são SECURITY DEFINER: leem a "verdade do banco" (sem RLS)
--   para conferir contagens exatas. Não são casos de permissão; o NOTICE mostra
--   'postgres' nelas.
--
-- Os helpers não dependem da migration do módulo: as referências a tabelas do
-- módulo só aparecem dentro das SQL que os arquivos de teste passam como texto.
-- ─────────────────────────────────────────────────────────────────────────────

drop schema if exists tests cascade;
create schema tests;
grant usage on schema tests to anon, authenticated, service_role;

-- ── Emissão ─────────────────────────────────────────────────────────────────
create or replace function tests._emit(
  p_ok boolean, p_label text, p_detail text default null, p_kind text default 'assert'
) returns boolean
language plpgsql
as $$
begin
  raise notice 'PT %', json_build_object(
    'kind',   p_kind,
    'ok',     coalesce(p_ok, false),
    'label',  p_label,
    'detail', p_detail,
    'as',     current_user::text
  )::text;
  return coalesce(p_ok, false);
end;
$$;

create or replace function tests._show(p_value text)
returns text
language sql
immutable
as $$ select coalesce(quote_literal(p_value), 'NULL') $$;

-- Título de seção (não conta como asserção).
create or replace function tests.note(p_text text)
returns void
language plpgsql
as $$
begin
  perform tests._emit(true, p_text, null, 'note');
end;
$$;

-- Marca o fim do arquivo: o runner acusa arquivo que não chegou até aqui.
create or replace function tests.done()
returns void
language plpgsql
as $$
begin
  perform tests._emit(true, 'fim do arquivo', null, 'done');
end;
$$;

-- ── Variáveis (locais à transação) ──────────────────────────────────────────
create or replace function tests.set_var(p_name text, p_value text)
returns text
language plpgsql
as $$
begin
  if p_name !~ '^[a-z][a-z0-9_]*$' then
    raise exception 'tests.set_var: nome inválido %', p_name;
  end if;
  perform set_config('pt.v_' || p_name, coalesce(p_value, ''), true);
  return p_value;
end;
$$;

create or replace function tests.var(p_name text)
returns text
language sql
stable
as $$ select nullif(current_setting('pt.v_' || p_name, true), '') $$;

create or replace function tests.uvar(p_name text)
returns uuid
language plpgsql
stable
as $$
begin
  return tests.var(p_name)::uuid;
exception when others then
  return null;
end;
$$;

create or replace function tests.jvar(p_name text)
returns jsonb
language plpgsql
stable
as $$
begin
  return tests.var(p_name)::jsonb;
exception when others then
  return null;
end;
$$;

create or replace function tests.tvar(p_name text)
returns timestamptz
language plpgsql
stable
as $$
begin
  return tests.var(p_name)::timestamptz;
exception when others then
  return null;
end;
$$;

-- Novo uuid guardado em variável (id gerado "no cliente").
create or replace function tests.new_id(p_name text)
returns uuid
language plpgsql
as $$
declare
  v uuid := gen_random_uuid();
begin
  perform tests.set_var(p_name, v::text);
  return v;
end;
$$;

-- ── Execução protegida ──────────────────────────────────────────────────────
-- Executa a SQL (primeira coluna da primeira linha) e guarda o resultado na
-- variável. Erro inesperado vira falha "preparação: <nome>" e a variável fica
-- vazia; o arquivo continua.
create or replace function tests.capture(p_name text, p_sql text)
returns text
language plpgsql
as $$
declare
  v       text;
  v_state text;
  v_msg   text;
begin
  begin
    execute p_sql into v;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    perform tests._emit(false, 'preparação: ' || p_name,
      format('erro inesperado %s: %s', v_state, v_msg), 'setup');
    v := null;
  end;
  perform tests.set_var(p_name, v);
  return v;
end;
$$;

-- Executa um passo de preparação sem guardar valor; erro vira falha.
create or replace function tests.step(p_label text, p_sql text)
returns boolean
language plpgsql
as $$
declare
  v_state text;
  v_msg   text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return tests._emit(false, 'preparação: ' || p_label,
      format('erro inesperado %s: %s', v_state, v_msg), 'setup');
  end;
  return true;
end;
$$;

-- Tenta a SQL e devolve 'ok' ou o SQLSTATE do erro, guardando na variável.
-- Diferente de tests.throws, o efeito PERMANECE quando dá certo: serve para
-- encadear passos de um ataque (ex.: apagar e depois reinserir um perfil).
create or replace function tests.attempt(p_name text, p_sql text)
returns text
language plpgsql
as $$
declare
  v_state text;
begin
  begin
    execute p_sql;
    v_state := 'ok';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
  end;
  perform tests.set_var(p_name, v_state);
  return v_state;
end;
$$;

-- ── Asserções ───────────────────────────────────────────────────────────────
create or replace function tests.ok(p_label text, p_cond boolean, p_detail text default null)
returns boolean
language plpgsql
as $$
begin
  return tests._emit(coalesce(p_cond, false), p_label,
    case when p_cond is null then 'condição NULL'
         when not p_cond then coalesce(p_detail, 'condição falsa') end);
end;
$$;

create or replace function tests.is(p_label text, p_got anyelement, p_expected anyelement)
returns boolean
language plpgsql
as $$
begin
  return tests._emit(p_got is not distinct from p_expected, p_label,
    format('obtido %s, esperado %s', tests._show(p_got::text), tests._show(p_expected::text)));
end;
$$;

create or replace function tests.eq(p_label text, p_got text, p_expected text)
returns boolean
language plpgsql
as $$
begin
  return tests._emit(p_got is not distinct from p_expected, p_label,
    format('obtido %s, esperado %s', tests._show(p_got), tests._show(p_expected)));
end;
$$;

-- A SQL devolve um valor; compara o texto com o esperado.
create or replace function tests.query_is(p_label text, p_sql text, p_expected text)
returns boolean
language plpgsql
as $$
declare
  v       text;
  v_state text;
  v_msg   text;
begin
  begin
    execute p_sql into v;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return tests._emit(false, p_label, format('erro inesperado %s: %s', v_state, v_msg));
  end;
  return tests._emit(v is not distinct from p_expected, p_label,
    format('obtido %s, esperado %s', tests._show(v), tests._show(p_expected)));
end;
$$;

create or replace function tests.query_true(p_label text, p_sql text)
returns boolean
language plpgsql
as $$
begin
  return tests.query_is(p_label, p_sql, 'true');
end;
$$;

-- Quantas linhas a SQL devolve (vista pelo papel atual, com RLS).
create or replace function tests.rows_eq(p_label text, p_sql text, p_expected bigint)
returns boolean
language plpgsql
as $$
declare
  v       bigint;
  v_state text;
  v_msg   text;
begin
  begin
    execute format('select count(*) from (%s) as tests_q', p_sql) into v;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return tests._emit(false, p_label, format('erro inesperado %s: %s', v_state, v_msg));
  end;
  return tests._emit(v = p_expected, p_label, format('obtido %s linha(s), esperado %s', v, p_expected));
end;
$$;

-- Quantas linhas o comando (INSERT/UPDATE/DELETE) afetou. O efeito permanece.
create or replace function tests.affects(p_label text, p_sql text, p_expected bigint)
returns boolean
language plpgsql
as $$
declare
  v       bigint;
  v_state text;
  v_msg   text;
begin
  begin
    execute p_sql;
    get diagnostics v = row_count;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return tests._emit(false, p_label, format('erro inesperado %s: %s', v_state, v_msg));
  end;
  return tests._emit(v = p_expected, p_label, format('afetou %s linha(s), esperado %s', v, p_expected));
end;
$$;

-- Passa se a SQL rodar sem erro. O efeito permanece.
create or replace function tests.lives(p_label text, p_sql text)
returns boolean
language plpgsql
as $$
declare
  v_state text;
  v_msg   text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return tests._emit(false, p_label, format('erro inesperado %s: %s', v_state, v_msg));
  end;
  return tests._emit(true, p_label);
end;
$$;

-- Núcleo das asserções de erro: roda a SQL e desfaz SEMPRE.
-- Devolve (sqlstate, message, constraint_name, detail); sqlstate NULL = não
-- deu erro. O detail é a frase pt-BR que o contrato (§3.3/§3.7) põe em cada
-- código de erro.
create or replace function tests._try(p_sql text,
  out o_sqlstate text, out o_message text, out o_constraint text, out o_detail text)
language plpgsql
as $$
begin
  begin
    execute p_sql;
    raise exception using errcode = 'PTX01', message = 'pt_sem_erro';
  exception when others then
    get stacked diagnostics o_sqlstate = returned_sqlstate,
                            o_message = message_text,
                            o_constraint = constraint_name,
                            o_detail = pg_exception_detail;
  end;
  if o_sqlstate = 'PTX01' then
    o_sqlstate := null;
    o_message := null;
    o_constraint := null;
    o_detail := null;
  end if;
end;
$$;

-- Espera erro com message exata (o código do contrato) e/ou SQLSTATE exato.
-- NULL num dos dois = qualquer valor.
create or replace function tests.throws(p_label text, p_sql text,
  p_message text default null, p_sqlstate text default null)
returns boolean
language plpgsql
as $$
declare
  r record;
begin
  select * into r from tests._try(p_sql);
  if r.o_sqlstate is null then
    return tests._emit(false, p_label, format('nenhum erro; esperado %s %s',
      coalesce(p_sqlstate, '*'), coalesce(p_message, '*')));
  end if;
  return tests._emit(
    (p_message is null or r.o_message = p_message)
      and (p_sqlstate is null or r.o_sqlstate = p_sqlstate),
    p_label,
    format('obtido %s "%s"; esperado %s "%s"', r.o_sqlstate, r.o_message,
      coalesce(p_sqlstate, '*'), coalesce(p_message, '*')));
end;
$$;

-- Espera erro com message, SQLSTATE e detail exatos: o código do contrato, o
-- SQLSTATE de §3.7 e a frase pt-BR de §3.7 (raise … using detail = …, §3.3).
-- p_detail_pattern NULL = detail ausente; senão é um padrão LIKE (use o texto
-- inteiro para exigir igualdade).
create or replace function tests.throws_detail(p_label text, p_sql text,
  p_message text, p_sqlstate text, p_detail_pattern text)
returns boolean
language plpgsql
as $$
declare
  r record;
begin
  select * into r from tests._try(p_sql);
  if r.o_sqlstate is null then
    return tests._emit(false, p_label, format('nenhum erro; esperado %s "%s" (detail "%s")',
      p_sqlstate, p_message, coalesce(p_detail_pattern, '')));
  end if;
  return tests._emit(
    r.o_message is not distinct from p_message
      and r.o_sqlstate is not distinct from p_sqlstate
      and case when p_detail_pattern is null then nullif(r.o_detail, '') is null
               else coalesce(r.o_detail, '') like p_detail_pattern end,
    p_label,
    format('obtido %s "%s" (detail "%s"); esperado %s "%s" (detail "%s")',
      r.o_sqlstate, r.o_message, coalesce(r.o_detail, ''),
      p_sqlstate, p_message, coalesce(p_detail_pattern, '')));
end;
$$;

-- Espera erro cuja message case com o padrão LIKE e SQLSTATE exato.
create or replace function tests.throws_like(p_label text, p_sql text,
  p_pattern text, p_sqlstate text)
returns boolean
language plpgsql
as $$
declare
  r record;
begin
  select * into r from tests._try(p_sql);
  if r.o_sqlstate is null then
    return tests._emit(false, p_label, format('nenhum erro; esperado %s "%s"', p_sqlstate, p_pattern));
  end if;
  return tests._emit(r.o_message like p_pattern and r.o_sqlstate = p_sqlstate, p_label,
    format('obtido %s "%s"; esperado %s "%s"', r.o_sqlstate, r.o_message, p_sqlstate, p_pattern));
end;
$$;

-- Espera violação de uma constraint pelo nome (CONSTRAINT_NAME do erro).
create or replace function tests.throws_constraint(p_label text, p_sql text,
  p_sqlstate text, p_constraint text)
returns boolean
language plpgsql
as $$
declare
  r record;
begin
  select * into r from tests._try(p_sql);
  if r.o_sqlstate is null then
    return tests._emit(false, p_label, format('nenhum erro; esperado %s na constraint %s', p_sqlstate, p_constraint));
  end if;
  return tests._emit(r.o_sqlstate = p_sqlstate and r.o_constraint is not distinct from p_constraint, p_label,
    format('obtido %s "%s" (constraint %s); esperado %s (constraint %s)',
      r.o_sqlstate, r.o_message, coalesce(r.o_constraint, '-'), p_sqlstate, p_constraint));
end;
$$;

-- Permissão negada pelo Postgres (grant), não pela RLS.
create or replace function tests.denied(p_label text, p_sql text)
returns boolean
language plpgsql
as $$
begin
  return tests.throws_like(p_label, p_sql, 'permission denied for %', '42501');
end;
$$;

-- Linha barrada pela RLS (WITH CHECK de INSERT/UPDATE).
create or replace function tests.rls_denied(p_label text, p_sql text)
returns boolean
language plpgsql
as $$
begin
  return tests.throws_like(p_label, p_sql, 'new row violates row-level security policy%', '42501');
end;
$$;

-- ── Verdade do banco (SECURITY DEFINER, ignora RLS) ─────────────────────────
create or replace function tests.admin_query_is(p_label text, p_sql text, p_expected text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v       text;
  v_state text;
  v_msg   text;
begin
  begin
    execute p_sql into v;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return tests._emit(false, p_label, format('erro inesperado %s: %s', v_state, v_msg));
  end;
  return tests._emit(v is not distinct from p_expected, p_label,
    format('obtido %s, esperado %s', tests._show(v), tests._show(p_expected)));
end;
$$;

create or replace function tests.admin_true(p_label text, p_sql text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  return tests.admin_query_is(p_label, p_sql, 'true');
end;
$$;

create or replace function tests.admin_rows(p_label text, p_sql text, p_expected bigint)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v       bigint;
  v_state text;
  v_msg   text;
begin
  begin
    execute format('select count(*) from (%s) as tests_q', p_sql) into v;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    return tests._emit(false, p_label, format('erro inesperado %s: %s', v_state, v_msg));
  end;
  return tests._emit(v = p_expected, p_label, format('obtido %s linha(s), esperado %s', v, p_expected));
end;
$$;

create or replace function tests.admin_capture(p_name text, p_sql text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v       text;
  v_state text;
  v_msg   text;
begin
  begin
    execute p_sql into v;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    perform tests._emit(false, 'preparação: ' || p_name,
      format('erro inesperado %s: %s', v_state, v_msg), 'setup');
    v := null;
  end;
  perform tests.set_var(p_name, v);
  return v;
end;
$$;

-- ── Usuários ────────────────────────────────────────────────────────────────
-- Cria auth.users (o handle_new_user cria o perfil 'client') e ajusta o papel.
-- p_role NULL = "desconhecido": autenticado sem linha em profiles.
-- O id fica na variável uid_<nome>.
create or replace function tests.create_user(p_name text, p_role text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, email, raw_user_meta_data)
  values (v_id, p_name || '.' || substr(v_id::text, 1, 8) || '@teste.local',
          jsonb_build_object('full_name', 'Pessoa ' || p_name));
  if p_role is null then
    delete from public.profiles where id = v_id;
  elsif p_role <> 'client' then
    update public.profiles set role = p_role where id = v_id;
  end if;
  perform tests.set_var('uid_' || p_name, v_id::text);
  return v_id;
end;
$$;

create or replace function tests.uid(p_name text)
returns uuid
language sql
stable
as $$ select tests.uvar('uid_' || p_name) $$;

create or replace function tests._email(p_uid uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$ select u.email from auth.users u where u.id = p_uid $$;

-- Entra como o usuário (papel authenticated + JWT com sub).
create or replace function tests.login(p_name text)
returns uuid
language plpgsql
as $$
declare
  v_uid uuid := tests.uid(p_name);
begin
  if v_uid is null then
    raise exception 'tests.login: usuário "%" não foi criado neste arquivo', p_name;
  end if;
  perform set_config('request.jwt.claims', json_build_object(
    'sub', v_uid, 'role', 'authenticated', 'aud', 'authenticated',
    'email', tests._email(v_uid))::text, true);
  perform set_config('role', 'authenticated', true);
  return v_uid;
end;
$$;

-- Visitante sem sessão (chave publicável sem login).
create or replace function tests.login_anon()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  perform set_config('role', 'anon', true);
end;
$$;

-- authenticated com JWT sem "sub" (auth.uid() nulo).
create or replace function tests.login_without_sub()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- service_role (Edge Functions). Só para casos de imutabilidade.
create or replace function tests.login_service()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  perform set_config('role', 'service_role', true);
end;
$$;

-- Volta ao superusuário da sessão (postgres). Só para preparação e para os
-- casos explícitos "trigger rejeita linha inválida como postgres".
create or replace function tests.logout()
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'none', true);
end;
$$;

-- ── Datas e horas de Brasília ───────────────────────────────────────────────
-- '2026-10-05 22:00' no relógio de Brasília → instante.
create or replace function tests.brt(p_wall text)
returns timestamptz
language sql
stable
as $$ select (p_wall::timestamp at time zone 'America/Sao_Paulo') $$;

create or replace function tests.today_brt()
returns date
language sql
stable
as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;

-- Meia-noite de hoje em Brasília (instante).
create or replace function tests.midnight_brt()
returns timestamptz
language sql
stable
as $$ select (tests.today_brt()::timestamp at time zone 'America/Sao_Paulo') $$;

-- Intervalo em JSON no formato de p_breaks.
create or replace function tests.brk(p_start timestamptz, p_end timestamptz)
returns jsonb
language sql
stable
as $$ select jsonb_build_object('started_at', p_start, 'ended_at', p_end) $$;

-- Lista ordenada das chaves de um objeto JSON, separadas por vírgula.
create or replace function tests.keys(p_json jsonb)
returns text
language sql
immutable
as $$
  select string_agg(k, ',' order by k collate "C")
  from jsonb_object_keys(case when jsonb_typeof(p_json) = 'object' then p_json else '{}'::jsonb end) as k
$$;

-- ── Papéis novos (§5) ───────────────────────────────────────────────────────
-- O schema atual aceita estes papéis? Testa numa subtransação desfeita.
create or replace function tests.schema_accepts_role(p_role text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform tests.create_user('sonda', p_role);
    raise exception using errcode = 'PTX02', message = 'pt_sonda_ok';
  exception
    when sqlstate 'PTX02' then return true;
    when check_violation then return false;
  end;
end;
$$;


-- ── Formato do JSON da jornada (contrato §3.4) ──────────────────────────────
-- Chaves em ordem "C", como tests.keys devolve.
create or replace function tests.k_shift()
returns text
language sql
immutable
as $$
  select 'created_at,ended_at,id,last_corrected_at,last_corrected_by,note,review_status,'
      || 'reviewed_at,reviewed_by,source,started_at,time_breaks,updated_at,user_id,'
      || 'void_reason,voided_at,voided_by,work_date'
$$;

-- Resposta de RPC: o JSON da jornada + "server_now".
create or replace function tests.k_rpc()
returns text
language sql
immutable
as $$
  select 'created_at,ended_at,id,last_corrected_at,last_corrected_by,note,review_status,'
      || 'reviewed_at,reviewed_by,server_now,source,started_at,time_breaks,updated_at,user_id,'
      || 'void_reason,voided_at,voided_by,work_date'
$$;

create or replace function tests.k_break()
returns text
language sql
immutable
as $$ select 'created_at,ended_at,id,shift_id,started_at,updated_at,user_id' $$;

-- Tamanho de um array JSON; NULL se não for array (nunca aborta).
create or replace function tests.jlen(p_json jsonb)
returns integer
language sql
immutable
as $$ select case when jsonb_typeof(p_json) = 'array' then jsonb_array_length(p_json) end $$;
