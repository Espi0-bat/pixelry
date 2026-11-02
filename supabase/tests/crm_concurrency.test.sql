-- Concorrência de crm_create_opportunity: duas transações, mesma chave.
--
-- Só no ambiente local (run-crm-rls.sh sem --linked): usa dblink para abrir
-- duas conexões de verdade e grava dados, num banco descartável. Recebe a
-- string de conexão do próprio banco na variável psql :conninfo.
--
-- A ordem é determinística, sem depender de tempo: a conexão c1 cria e
-- segura a transação aberta; a c2 manda a mesma chave de forma assíncrona;
-- o teste espera até a c2 aparecer bloqueada em pg_stat_activity; só então a
-- c1 termina (commit ou rollback) e o resultado da c2 é lido.

\set ON_ERROR_STOP on
create extension if not exists dblink;

create temp table crm_t (
  n        integer generated always as identity,
  test     text not null,
  expected text not null,
  actual   text
);

create temp table crm_ids (cenario text, conexao text, id text, erro text);

create function pg_temp.chk(p_test text, p_expected text, p_actual text)
returns void
language sql
as $$
  insert into crm_t (test, expected, actual) values (p_test, p_expected, p_actual)
$$;

-- Abre uma conexão remota como a pessoa, igual ao PostgREST: papel e claims
-- valendo só dentro da transação.
create function pg_temp.open_as(p_conn text, p_conninfo text, p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform dblink_connect(p_conn, p_conninfo);
  perform dblink_exec(p_conn, format('set application_name = %L', 'crm_conc_' || p_conn));
  perform dblink_exec(p_conn, 'begin');
  perform dblink_exec(p_conn, 'set local role authenticated');
  perform dblink_exec(p_conn, format(
    'set local request.jwt.claims = %L',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text
  ));
end;
$$;

-- Espera (até 10 s) a conexão aparecer bloqueada esperando um lock.
create function pg_temp.wait_lock(p_conn text)
returns text
language plpgsql
as $$
declare
  v_event text;
begin
  for i in 1..200 loop
    perform pg_stat_clear_snapshot();
    select a.wait_event into v_event
    from pg_stat_activity a
    where a.application_name = 'crm_conc_' || p_conn
      and a.wait_event_type = 'Lock';
    if found then
      return v_event;
    end if;
    perform pg_sleep(0.05);
  end loop;
  return 'não bloqueou';
end;
$$;

create function pg_temp.create_sql(p_request uuid)
returns text
language sql
as $$
  select format(
    'select public.crm_create_opportunity(p_request_id => %L, p_title => %L, '
    'p_account_name => %L, p_contact_name => %L)::text',
    p_request, 'CONC Lead', 'CONC Conta', 'CONC Contato'
  )
$$;

-- Lê o resultado assíncrono da c2: o id, ou a mensagem de erro.
create function pg_temp.collect(p_cenario text, p_conn text)
returns void
language plpgsql
as $$
declare
  v_id text;
begin
  select t.id into v_id from dblink_get_result(p_conn, false) as t(id text);
  -- Esvazia a fila de resultados para a conexão poder ser reutilizada.
  perform * from dblink_get_result(p_conn, false) as t(id text);
  insert into crm_ids values (
    p_cenario, p_conn, v_id,
    case when v_id is null then dblink_error_message(p_conn) end
  );
end;
$$;

-- ── Pessoa de teste (gravada: as conexões remotas precisam enxergá-la) ─────
insert into auth.users (id, email, aud, role, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000000b1', 'crm-conc-sdr@example.invalid',
   'authenticated', 'authenticated', '{"full_name":"Concorrência SDR"}');
update public.profiles set role = 'sdr' where id = '00000000-0000-4000-8000-0000000000b1';

-- ── Cenário 1: a primeira grava; a segunda devolve o mesmo lead ─────────────
select pg_temp.open_as('c1', :'conninfo', '00000000-0000-4000-8000-0000000000b1');
select pg_temp.open_as('c2', :'conninfo', '00000000-0000-4000-8000-0000000000b1');

insert into crm_ids
select 'commit', 'c1', t.id, null
from dblink('c1', pg_temp.create_sql('00000000-0000-4000-8000-00000000cc01')) as t(id text);

select dblink_send_query('c2', pg_temp.create_sql('00000000-0000-4000-8000-00000000cc01'));
select pg_temp.chk('com a mesma chave, a segunda transação espera a primeira (advisory lock)', 'advisory',
  pg_temp.wait_lock('c2'));

select dblink_exec('c1', 'commit');
select pg_temp.collect('commit', 'c2');
select dblink_exec('c2', 'commit');

select pg_temp.chk('a segunda chamada termina sem erro', '',
  coalesce((select erro from crm_ids where cenario = 'commit' and conexao = 'c2'), ''));
select pg_temp.chk('as duas chamadas devolvem a mesma oportunidade', 'true',
  (select (c1.id is not null and c1.id = c2.id)::text
   from crm_ids c1, crm_ids c2
   where c1.cenario = 'commit' and c1.conexao = 'c1'
     and c2.cenario = 'commit' and c2.conexao = 'c2'));
select pg_temp.chk('nada duplicado: 1 oportunidade, 1 conta, 1 contato', '1/1/1',
  (select count(*) from public.crm_opportunities where client_request_id = '00000000-0000-4000-8000-00000000cc01')
  || '/' || (select count(*) from public.crm_accounts where client_request_id = '00000000-0000-4000-8000-00000000cc01')
  || '/' || (select count(*) from public.crm_contacts where client_request_id = '00000000-0000-4000-8000-00000000cc01'));

-- ── Cenário 2: a primeira desfaz; a segunda cria (nenhum lead se perde) ─────
select dblink_exec('c1', 'begin');
select dblink_exec('c1', 'set local role authenticated');
select dblink_exec('c1', format('set local request.jwt.claims = %L',
  json_build_object('sub', '00000000-0000-4000-8000-0000000000b1', 'role', 'authenticated')::text));
select dblink_exec('c2', 'begin');
select dblink_exec('c2', 'set local role authenticated');
select dblink_exec('c2', format('set local request.jwt.claims = %L',
  json_build_object('sub', '00000000-0000-4000-8000-0000000000b1', 'role', 'authenticated')::text));

insert into crm_ids
select 'rollback', 'c1', t.id, null
from dblink('c1', pg_temp.create_sql('00000000-0000-4000-8000-00000000cc02')) as t(id text);

select dblink_send_query('c2', pg_temp.create_sql('00000000-0000-4000-8000-00000000cc02'));
select pg_temp.chk('a segunda espera também quando a primeira vai desfazer', 'advisory',
  pg_temp.wait_lock('c2'));

select dblink_exec('c1', 'rollback');
select pg_temp.collect('rollback', 'c2');
select dblink_exec('c2', 'commit');

select pg_temp.chk('com a primeira desfeita, a segunda cria o lead', 'true',
  (select (c2.id is not null and c2.erro is null and c2.id <> c1.id)::text
   from crm_ids c1, crm_ids c2
   where c1.cenario = 'rollback' and c1.conexao = 'c1'
     and c2.cenario = 'rollback' and c2.conexao = 'c2'));
select pg_temp.chk('e ele existe uma vez só', '1/1/1',
  (select count(*) from public.crm_opportunities where client_request_id = '00000000-0000-4000-8000-00000000cc02')
  || '/' || (select count(*) from public.crm_accounts where client_request_id = '00000000-0000-4000-8000-00000000cc02')
  || '/' || (select count(*) from public.crm_contacts where client_request_id = '00000000-0000-4000-8000-00000000cc02'));

-- ── Cenário 3: atividade com a mesma chave em paralelo ──────────────────────
-- Inclusão direta na tabela: a segunda recebe 23505 e o app trata como
-- "já gravada" (SupabaseCrmRepository.saveActivity). Aqui se confirma que a
-- trava é o índice único e que não há duplicata.
select dblink_exec('c1', 'begin');
select dblink_exec('c1', 'set local role authenticated');
select dblink_exec('c1', format('set local request.jwt.claims = %L',
  json_build_object('sub', '00000000-0000-4000-8000-0000000000b1', 'role', 'authenticated')::text));
select dblink_exec('c2', 'begin');
select dblink_exec('c2', 'set local role authenticated');
select dblink_exec('c2', format('set local request.jwt.claims = %L',
  json_build_object('sub', '00000000-0000-4000-8000-0000000000b1', 'role', 'authenticated')::text));

create temp table crm_activity_sql as
select format(
  'insert into public.crm_activities (opportunity_id, type, summary, client_request_id) '
  'values (%L, %L, %L, %L) returning id::text',
  (select id from crm_ids where cenario = 'commit' and conexao = 'c1'),
  'call', 'CONC ligação', '00000000-0000-4000-8000-00000000cc03'
) as sql;

insert into crm_ids
select 'atividade', 'c1', t.id, null
from crm_activity_sql s, dblink('c1', s.sql) as t(id text);

select dblink_send_query('c2', sql) from crm_activity_sql;
select pg_temp.chk('a segunda inclusão da atividade espera no índice único', 'transactionid',
  pg_temp.wait_lock('c2'));

select dblink_exec('c1', 'commit');
select pg_temp.collect('atividade', 'c2');
select dblink_exec('c2', 'rollback');

select pg_temp.chk('a segunda inclusão é recusada pelo índice de idempotência', 'true',
  (select (erro like '%crm_activities_request_uniq%')::text
   from crm_ids where cenario = 'atividade' and conexao = 'c2'));
select pg_temp.chk('a atividade existe uma vez só', '1',
  (select count(*)::text from public.crm_activities
   where client_request_id = '00000000-0000-4000-8000-00000000cc03'));

select dblink_disconnect('c1');
select dblink_disconnect('c2');

-- ── Resultado ───────────────────────────────────────────────────────────────
select
  'CRMTEST' as marcador,
  n,
  case when actual is not distinct from expected then 'PASSOU' else 'FALHOU' end as resultado,
  test,
  expected,
  actual
from crm_t
order by (actual is not distinct from expected), n;
