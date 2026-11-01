-- Testes de RLS, travas e auditoria do CRM.
--
-- Não rode este arquivo sozinho: use supabase/tests/run-crm-rls.sh. Por
-- padrão ele sobe um Postgres local descartável, aplica a base local e as
-- migrations do CRM e roda este arquivo entre begin e rollback. Contra o
-- projeto linkado só com --linked e confirmação explícita.
--
-- Cada consulta roda sob o papel real (set local role authenticated + claims
-- do JWT), como o PostgREST faz. Regras do projeto respeitadas:
--   * nenhum INSERT de teste usa RETURNING (exigiria policy de SELECT);
--   * a contagem é conferida com o papel original, antes do rollback;
--   * o último comando que devolve linhas é o SELECT do resultado.

-- ── Utilitários ─────────────────────────────────────────────────────────────
create temp table crm_t (
  n        integer generated always as identity,
  test     text not null,
  expected text not null,
  actual   text
);

-- Papel com que a conexão chegou (postgres no local; o da CLI no linkado).
create temp table crm_papel_inicial as select current_user::text as papel;

-- Executa p_sql como a pessoa (ou como anon, se p_uid for nulo).
-- Devolve 'ok:<linhas afetadas>' ou 'err:<sqlstate>'.
create function pg_temp.exec_as(p_uid uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v_rows bigint;
  v_role text := case when p_uid is null then 'anon' else 'authenticated' end;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', v_role)::text, true);
  execute format('set local role %I', v_role);
  execute p_sql;
  get diagnostics v_rows = row_count;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return 'ok:' || v_rows;
exception when others then
  return 'err:' || sqlstate;
end;
$$;

-- Devolve o primeiro valor de p_sql executado como a pessoa (ou 'err:<sqlstate>').
create function pg_temp.value_as(p_uid uuid, p_sql text)
returns text
language plpgsql
as $$
declare
  v_out  text;
  v_role text := case when p_uid is null then 'anon' else 'authenticated' end;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', v_role)::text, true);
  execute format('set local role %I', v_role);
  execute p_sql into v_out;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v_out;
exception when others then
  return 'err:' || sqlstate;
end;
$$;

create function pg_temp.count_as(p_uid uuid, p_from text)
returns text
language sql
as $$
  select pg_temp.value_as(p_uid, 'select count(*) from ' || p_from)
$$;

create function pg_temp.chk(p_test text, p_expected text, p_actual text)
returns void
language sql
as $$
  insert into crm_t (test, expected, actual) values (p_test, p_expected, p_actual)
$$;

-- ── Pessoas de teste ────────────────────────────────────────────────────────
-- handle_new_user cria o perfil com role = 'client'; o papel é ajustado
-- depois com o papel original da conexão (guard_profile_role permite).
insert into auth.users (id, email, aud, role, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000000a1', 'crm-teste-admin@example.invalid',  'authenticated', 'authenticated', '{"full_name":"Teste Admin"}'),
  ('00000000-0000-4000-8000-0000000000a2', 'crm-teste-socio@example.invalid',  'authenticated', 'authenticated', '{"full_name":"Teste Sócio Probatório"}'),
  ('00000000-0000-4000-8000-0000000000a3', 'crm-teste-sdr1@example.invalid',   'authenticated', 'authenticated', '{"full_name":"Teste SDR Um"}'),
  ('00000000-0000-4000-8000-0000000000a4', 'crm-teste-sdr2@example.invalid',   'authenticated', 'authenticated', '{"full_name":"Teste SDR Dois"}'),
  ('00000000-0000-4000-8000-0000000000a5', 'crm-teste-func@example.invalid',   'authenticated', 'authenticated', '{"full_name":"Teste Funcionário"}'),
  ('00000000-0000-4000-8000-0000000000a6', 'crm-teste-cliente@example.invalid','authenticated', 'authenticated', '{"full_name":"Teste Cliente"}'),
  ('00000000-0000-4000-8000-0000000000a7', 'crm-teste-gestor@example.invalid', 'authenticated', 'authenticated', '{"full_name":"Teste Gestor"}'),
  ('00000000-0000-4000-8000-0000000000a8', 'crm-teste-dev@example.invalid',    'authenticated', 'authenticated', '{"full_name":"Teste Dev"}');

update public.profiles set role = 'super_admin'  where id = '00000000-0000-4000-8000-0000000000a1';
update public.profiles set role = 'sales_trial'  where id = '00000000-0000-4000-8000-0000000000a2';
update public.profiles set role = 'sdr'          where id = '00000000-0000-4000-8000-0000000000a3';
update public.profiles set role = 'sdr'          where id = '00000000-0000-4000-8000-0000000000a4';
update public.profiles set role = 'employee'     where id = '00000000-0000-4000-8000-0000000000a5';
-- a6 continua client
update public.profiles set role = 'manager'      where id = '00000000-0000-4000-8000-0000000000a7';
update public.profiles set role = 'employee_dev' where id = '00000000-0000-4000-8000-0000000000a8';

-- ── Dados de teste ──────────────────────────────────────────────────────────
-- Conta A: do sócio, com oportunidade do SDR1 (SDR1 vê pela oportunidade)
-- Conta B: do SDR1
-- Conta C: sem responsável, oportunidade do sócio com SDR2 como SDR
-- Contato X: sem conta, do SDR2; oportunidade 4 sem responsável
insert into public.crm_accounts (id, name, owner_id) values
  ('00000000-0000-4000-8000-00000000ac0a', 'TESTE Conta A', '00000000-0000-4000-8000-0000000000a2'),
  ('00000000-0000-4000-8000-00000000ac0b', 'TESTE Conta B', '00000000-0000-4000-8000-0000000000a3'),
  ('00000000-0000-4000-8000-00000000ac0c', 'TESTE Conta C', null);

insert into public.crm_contacts (id, account_id, full_name, owner_id) values
  ('00000000-0000-4000-8000-00000000c0a1', '00000000-0000-4000-8000-00000000ac0a', 'TESTE Contato A1', '00000000-0000-4000-8000-0000000000a2'),
  ('00000000-0000-4000-8000-00000000c0b1', '00000000-0000-4000-8000-00000000ac0b', 'TESTE Contato B1', '00000000-0000-4000-8000-0000000000a3'),
  ('00000000-0000-4000-8000-00000000c0c1', '00000000-0000-4000-8000-00000000ac0c', 'TESTE Contato C1', null),
  ('00000000-0000-4000-8000-00000000c0f1', null,                                   'TESTE Contato X',  '00000000-0000-4000-8000-0000000000a4');

insert into public.crm_opportunities (id, title, account_id, contact_id, owner_id, sdr_id, estimated_value) values
  ('00000000-0000-4000-8000-0000000000f1', 'TESTE Op 1', '00000000-0000-4000-8000-00000000ac0a', '00000000-0000-4000-8000-00000000c0a1',
   '00000000-0000-4000-8000-0000000000a3', null, 1000),
  ('00000000-0000-4000-8000-0000000000f2', 'TESTE Op 2', '00000000-0000-4000-8000-00000000ac0b', '00000000-0000-4000-8000-00000000c0b1',
   '00000000-0000-4000-8000-0000000000a3', '00000000-0000-4000-8000-0000000000a3', 2000),
  ('00000000-0000-4000-8000-0000000000f3', 'TESTE Op 3', '00000000-0000-4000-8000-00000000ac0c', '00000000-0000-4000-8000-00000000c0c1',
   '00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000a4', 3000),
  ('00000000-0000-4000-8000-0000000000f4', 'TESTE Op 4', null, '00000000-0000-4000-8000-00000000c0f1',
   null, null, null);

insert into public.crm_activities (id, opportunity_id, account_id, type, summary, created_by) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000f1', null, 'call',    'TESTE ligação op1', '00000000-0000-4000-8000-0000000000a3'),
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f3', null, 'meeting', 'TESTE reunião op3', '00000000-0000-4000-8000-0000000000a2'),
  ('00000000-0000-4000-8000-0000000000e3', null, '00000000-0000-4000-8000-00000000ac0c', 'note', 'TESTE nota conta C', '00000000-0000-4000-8000-0000000000a2');

-- ── Visibilidade ────────────────────────────────────────────────────────────
-- Totais vistos pelo papel original (sem RLS), incluindo o que já existia.
create temp table crm_totais as
select
  (select count(*) from public.crm_opportunities)::text as ops,
  (select count(*) from public.crm_accounts)::text      as contas,
  (select count(*) from public.crm_contacts)::text      as contatos,
  (select count(*) from public.crm_activities)::text    as atividades,
  (select count(*) from public.crm_stages)::text        as etapas;

-- super_admin
select pg_temp.chk('super_admin vê todas as oportunidades', ops,        pg_temp.count_as('00000000-0000-4000-8000-0000000000a1', 'public.crm_opportunities')) from crm_totais;
select pg_temp.chk('super_admin vê todas as contas',        contas,     pg_temp.count_as('00000000-0000-4000-8000-0000000000a1', 'public.crm_accounts'))      from crm_totais;
select pg_temp.chk('super_admin vê todos os contatos',      contatos,   pg_temp.count_as('00000000-0000-4000-8000-0000000000a1', 'public.crm_contacts'))      from crm_totais;
select pg_temp.chk('super_admin vê todas as atividades',    atividades, pg_temp.count_as('00000000-0000-4000-8000-0000000000a1', 'public.crm_activities'))    from crm_totais;

-- sales_trial (sócio comercial probatório): CRM completo
select pg_temp.chk('sales_trial vê todas as oportunidades', ops,        pg_temp.count_as('00000000-0000-4000-8000-0000000000a2', 'public.crm_opportunities')) from crm_totais;
select pg_temp.chk('sales_trial vê todas as contas',        contas,     pg_temp.count_as('00000000-0000-4000-8000-0000000000a2', 'public.crm_accounts'))      from crm_totais;
select pg_temp.chk('sales_trial vê todos os contatos',      contatos,   pg_temp.count_as('00000000-0000-4000-8000-0000000000a2', 'public.crm_contacts'))      from crm_totais;
select pg_temp.chk('sales_trial vê todas as atividades',    atividades, pg_temp.count_as('00000000-0000-4000-8000-0000000000a2', 'public.crm_activities'))    from crm_totais;
select pg_temp.chk('sales_trial vê as etapas',              etapas,     pg_temp.count_as('00000000-0000-4000-8000-0000000000a2', 'public.crm_stages'))        from crm_totais;

-- manager: padrão completo
select pg_temp.chk('manager vê todas as oportunidades', ops, pg_temp.count_as('00000000-0000-4000-8000-0000000000a7', 'public.crm_opportunities')) from crm_totais;

-- SDR1: Op1 e Op2; contas A (pela Op1) e B; contatos A1 e B1; atividade da Op1
select pg_temp.chk('sdr1 vê só as 2 oportunidades dele', '2', pg_temp.count_as('00000000-0000-4000-8000-0000000000a3', 'public.crm_opportunities'));
select pg_temp.chk('sdr1 vê as oportunidades certas', 'TESTE Op 1,TESTE Op 2',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3', 'select string_agg(title, '','' order by title) from public.crm_opportunities'));
select pg_temp.chk('sdr1 vê 2 contas (própria + da oportunidade)', '2', pg_temp.count_as('00000000-0000-4000-8000-0000000000a3', 'public.crm_accounts'));
select pg_temp.chk('sdr1 não vê a conta C', '0',
  pg_temp.count_as('00000000-0000-4000-8000-0000000000a3', 'public.crm_accounts where id = ''00000000-0000-4000-8000-00000000ac0c'''));
select pg_temp.chk('sdr1 vê 2 contatos', '2', pg_temp.count_as('00000000-0000-4000-8000-0000000000a3', 'public.crm_contacts'));
select pg_temp.chk('sdr1 vê 1 atividade', '1', pg_temp.count_as('00000000-0000-4000-8000-0000000000a3', 'public.crm_activities'));

-- SDR2: Op3 (como SDR); conta C (pela Op3); contatos C1 (conta) e X (dono); atividades da Op3 e da conta C
select pg_temp.chk('sdr2 vê só a oportunidade em que é SDR', '1', pg_temp.count_as('00000000-0000-4000-8000-0000000000a4', 'public.crm_opportunities'));
select pg_temp.chk('sdr2 vê 1 conta', '1', pg_temp.count_as('00000000-0000-4000-8000-0000000000a4', 'public.crm_accounts'));
select pg_temp.chk('sdr2 vê 2 contatos', '2', pg_temp.count_as('00000000-0000-4000-8000-0000000000a4', 'public.crm_contacts'));
select pg_temp.chk('sdr2 vê 2 atividades', '2', pg_temp.count_as('00000000-0000-4000-8000-0000000000a4', 'public.crm_activities'));

-- Sem CRM
select pg_temp.chk('employee não vê oportunidades', '0', pg_temp.count_as('00000000-0000-4000-8000-0000000000a5', 'public.crm_opportunities'));
select pg_temp.chk('employee não vê contas',        '0', pg_temp.count_as('00000000-0000-4000-8000-0000000000a5', 'public.crm_accounts'));
select pg_temp.chk('employee não vê etapas',        '0', pg_temp.count_as('00000000-0000-4000-8000-0000000000a5', 'public.crm_stages'));
select pg_temp.chk('employee_dev não vê oportunidades', '0', pg_temp.count_as('00000000-0000-4000-8000-0000000000a8', 'public.crm_opportunities'));
select pg_temp.chk('client não vê oportunidades', '0', pg_temp.count_as('00000000-0000-4000-8000-0000000000a6', 'public.crm_opportunities'));
select pg_temp.chk('client não vê contatos',      '0', pg_temp.count_as('00000000-0000-4000-8000-0000000000a6', 'public.crm_contacts'));
select pg_temp.chk('client não vê histórico',     '0', pg_temp.count_as('00000000-0000-4000-8000-0000000000a6', 'public.crm_audit_log'));
select pg_temp.chk('client não insere oportunidade', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a6', 'insert into public.crm_opportunities (title) values (''TESTE invasão'')'));
select pg_temp.chk('anon é barrado na tabela', 'err:42501', pg_temp.count_as(null, 'public.crm_opportunities'));
select pg_temp.chk('anon é barrado na view',   'err:42501', pg_temp.count_as(null, 'public.crm_opportunity_overview'));
select pg_temp.chk('anon é barrado na RPC',    'err:42501', pg_temp.value_as(null, 'select public.crm_my_access()::text'));

-- Views herdam a RLS
select pg_temp.chk('overview do sdr1 tem 2 linhas', '2', pg_temp.count_as('00000000-0000-4000-8000-0000000000a3', 'public.crm_opportunity_overview'));
select pg_temp.chk('funil do sdr1 soma 2 oportunidades', '2',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3', 'select sum(opportunity_count)::text from public.crm_funnel_summary'));
select pg_temp.chk('funil do sdr1 soma o valor só das dele', '3000.00',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3', 'select sum(estimated_total)::text from public.crm_funnel_summary'));
select pg_temp.chk('busca do sdr1 encontra pela conta', '1',
  pg_temp.count_as('00000000-0000-4000-8000-0000000000a3', 'public.crm_opportunity_overview where search_text ilike ''%conta b%'''));
select pg_temp.chk('busca do sdr1 não encontra o que não é dele', '0',
  pg_temp.count_as('00000000-0000-4000-8000-0000000000a3', 'public.crm_opportunity_overview where search_text ilike ''%conta c%'''));
select pg_temp.chk('filtro sem responsável (sócio vê a Op4)', '1',
  pg_temp.count_as('00000000-0000-4000-8000-0000000000a2', 'public.crm_opportunity_overview where owner_id is null and title like ''TESTE%'''));

-- ── Acesso efetivo e membros ────────────────────────────────────────────────
select pg_temp.chk('crm_my_access do sdr1', 'assigned/false',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3',
    'select (a->>''access_level'') || ''/'' || (a->>''can_assign'') from public.crm_my_access() a'));
select pg_temp.chk('crm_my_access do sales_trial', 'full/true/false',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a2',
    'select (a->>''access_level'') || ''/'' || (a->>''can_assign'') || ''/'' || (a->>''can_manage_access'') from public.crm_my_access() a'));
select pg_temp.chk('crm_my_access do employee', 'none',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a5', 'select a->>''access_level'' from public.crm_my_access() a'));
-- Quem não tem CRM completo só recebe id e nome de quem aparece no que vê.
-- sdr1 vê: Op1/Op2 (dele), conta A e contato A1 (do sócio), conta B e B1 (dele).
select pg_temp.chk('sdr1 só recebe quem aparece no que ele vê', 'Teste Sócio Probatório,Teste SDR Um',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3',
    'select string_agg(m.full_name, '','' order by m.id) from public.crm_list_members() m
      where m.id::text like ''00000000-0000-4000-8000-0000000000a%'''));
select pg_temp.chk('sdr1 não recebe e-mail, papel nem nível de acesso de ninguém', '0',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3',
    'select count(*)::text from public.crm_list_members() m
      where m.email is not null or m.role is not null or m.access_level is not null'));
-- sdr2 vê: Op3 (do sócio, ele é SDR), conta C e C1 (sem dono), X (dele),
-- atividades do sócio.
select pg_temp.chk('sdr2 só recebe quem aparece no que ele vê', 'Teste Sócio Probatório,Teste SDR Dois',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a4',
    'select string_agg(m.full_name, '','' order by m.id) from public.crm_list_members() m
      where m.id::text like ''00000000-0000-4000-8000-0000000000a%'''));
select pg_temp.chk('sales_trial recebe todos com CRM, com e-mail (é quem atribui)', '5/5',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a2',
    'select count(*)::text || ''/'' || count(m.email)::text from public.crm_list_members() m
      where m.id::text like ''00000000-0000-4000-8000-0000000000a%'''));
-- Nome vazio: quem tem CRM completo vê o e-mail no lugar; os demais, 'Sem nome'.
insert into auth.users (id, email, aud, role, raw_user_meta_data) values
  ('00000000-0000-4000-8000-0000000000a9', 'crm-semnome@example.invalid', 'authenticated', 'authenticated', '{}');
update public.profiles set role = 'sdr' where id = '00000000-0000-4000-8000-0000000000a9';
insert into public.crm_activities (id, opportunity_id, type, summary, created_by) values
  ('00000000-0000-4000-8000-0000000000e9', '00000000-0000-4000-8000-0000000000f1', 'note', 'TESTE nota sem nome',
   '00000000-0000-4000-8000-0000000000a9');
select pg_temp.chk('sem CRM completo, nome vazio vira "Sem nome", nunca o e-mail', 'Sem nome',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3',
    'select m.full_name from public.crm_list_members() m where m.id = ''00000000-0000-4000-8000-0000000000a9'''));
select pg_temp.chk('com CRM completo, nome vazio mostra o e-mail', 'crm-semnome@example.invalid',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a2',
    'select m.full_name from public.crm_list_members() m where m.id = ''00000000-0000-4000-8000-0000000000a9'''));
delete from public.crm_activities where id = '00000000-0000-4000-8000-0000000000e9';
select pg_temp.chk('sdr1 não vê o ajuste de acesso dos outros', '0',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3',
    'select count(*)::text from public.crm_list_members() m where m.crm_access is not null'));
select pg_temp.chk('client não lista membros', '0',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a6', 'select count(*)::text from public.crm_list_members()'));
select pg_temp.chk('super_admin lista também a equipe sem CRM', '7',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a1',
    'select count(*)::text from public.crm_list_members(true) m where m.email like ''crm-teste-%'''));

-- ── Edição de contas e contatos ─────────────────────────────────────────────
select pg_temp.chk('sdr1 edita a conta dele', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_accounts set phone = ''61 3333-0000'', segment = ''Odontologia'' where id = ''00000000-0000-4000-8000-00000000ac0b'''));
select pg_temp.chk('edição da conta vai para o histórico com autor', '1',
  (select count(*)::text from public.crm_audit_log
   where entity_type = 'account' and entity_id = '00000000-0000-4000-8000-00000000ac0b'
     and action = 'update' and changes ? 'phone' and changes ? 'segment'
     and actor_id = '00000000-0000-4000-8000-0000000000a3'));
select pg_temp.chk('sdr1 edita a conta que vê pela oportunidade', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_accounts set city = ''Brasília'' where id = ''00000000-0000-4000-8000-00000000ac0a'''));
select pg_temp.chk('sdr1 não edita conta que não vê (0 linhas)', 'ok:0',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_accounts set city = ''x'' where id = ''00000000-0000-4000-8000-00000000ac0c'''));
select pg_temp.chk('sdr1 edita o contato dele', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_contacts set job_title = ''Sócia'' where id = ''00000000-0000-4000-8000-00000000c0b1'''));
select pg_temp.chk('sdr1 não edita contato que não vê (0 linhas)', 'ok:0',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_contacts set job_title = ''x'' where id = ''00000000-0000-4000-8000-00000000c0c1'''));
select pg_temp.chk('sdr1 cria contato numa conta que vê', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'insert into public.crm_contacts (id, account_id, full_name, owner_id, client_request_id)
     values (''00000000-0000-4000-8000-00000000c0b2'', ''00000000-0000-4000-8000-00000000ac0b'', ''TESTE Contato B2'',
             ''00000000-0000-4000-8000-0000000000a2'', ''00000000-0000-4000-8000-00000000c0de'')'));
select pg_temp.chk('contato criado pelo sdr1 fica com ele mesmo como responsável', '00000000-0000-4000-8000-0000000000a3',
  (select owner_id::text from public.crm_contacts where id = '00000000-0000-4000-8000-00000000c0b2'));
select pg_temp.chk('contato repetido (mesma chave de envio) é recusado', 'err:23505',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'insert into public.crm_contacts (account_id, full_name, client_request_id)
     values (''00000000-0000-4000-8000-00000000ac0b'', ''TESTE Contato B2'', ''00000000-0000-4000-8000-00000000c0de'')'));
select pg_temp.chk('sdr1 não cria contato em conta que não vê', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'insert into public.crm_contacts (account_id, full_name) values (''00000000-0000-4000-8000-00000000ac0c'', ''TESTE invasão'')'));
select pg_temp.chk('sdr1 não troca o responsável do contato', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_contacts set owner_id = ''00000000-0000-4000-8000-0000000000a2'' where id = ''00000000-0000-4000-8000-00000000c0b1'''));
select pg_temp.chk('sales_trial atribui o responsável da conta', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'update public.crm_accounts set owner_id = ''00000000-0000-4000-8000-0000000000a2'' where id = ''00000000-0000-4000-8000-00000000ac0c'''));

-- ── Mudança de etapa ────────────────────────────────────────────────────────
select pg_temp.chk('sdr1 muda a etapa da oportunidade dele', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_opportunities set stage_id = ''contato'' where id = ''00000000-0000-4000-8000-0000000000f1'''));
select pg_temp.chk('mudança de etapa vai para o histórico com autor', '1',
  (select count(*)::text from public.crm_audit_log
   where entity_type = 'opportunity' and entity_id = '00000000-0000-4000-8000-0000000000f1'
     and action = 'update'
     and changes -> 'stage_id' = '{"old":"novo","new":"contato"}'::jsonb
     and actor_id = '00000000-0000-4000-8000-0000000000a3'));
select pg_temp.chk('sdr1 não altera oportunidade de outro (0 linhas)', 'ok:0',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_opportunities set stage_id = ''proposta'' where id = ''00000000-0000-4000-8000-0000000000f3'''));
select pg_temp.chk('perda sem motivo é recusada', 'err:23514',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_opportunities set stage_id = ''perdido'' where id = ''00000000-0000-4000-8000-0000000000f2'''));
select pg_temp.chk('perda com motivo fecha a oportunidade', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_opportunities set stage_id = ''perdido'', lost_reason = ''Sem verba'' where id = ''00000000-0000-4000-8000-0000000000f2'''));
select pg_temp.chk('perda grava closed_at', 'true',
  (select (closed_at is not null)::text from public.crm_opportunities where id = '00000000-0000-4000-8000-0000000000f2'));
-- (verificação em comando separado: uma subconsulta no mesmo comando usa o
-- snapshot de antes da função e não veria a alteração)
select pg_temp.chk('sdr1 reabre a oportunidade', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_opportunities set stage_id = ''diagnostico'' where id = ''00000000-0000-4000-8000-0000000000f2'''));
select pg_temp.chk('reabrir limpa closed_at', 'true',
  (select (closed_at is null)::text from public.crm_opportunities where id = '00000000-0000-4000-8000-0000000000f2'));

-- ── Mudança de responsável ──────────────────────────────────────────────────
select pg_temp.chk('sdr1 não troca o responsável', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_opportunities set owner_id = ''00000000-0000-4000-8000-0000000000a4'' where id = ''00000000-0000-4000-8000-0000000000f1'''));
select pg_temp.chk('sdr1 não se tira de SDR', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_opportunities set sdr_id = null where id = ''00000000-0000-4000-8000-0000000000f2'''));
select pg_temp.chk('sdr1 não troca o dono da conta', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_accounts set owner_id = ''00000000-0000-4000-8000-0000000000a2'' where id = ''00000000-0000-4000-8000-00000000ac0b'''));
select pg_temp.chk('sdr1 não altera o autor', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_opportunities set created_by = ''00000000-0000-4000-8000-0000000000a2'' where id = ''00000000-0000-4000-8000-0000000000f1'''));
select pg_temp.chk('sales_trial repassa a Op2 (SDR1 fica como SDR)', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'update public.crm_opportunities set owner_id = ''00000000-0000-4000-8000-0000000000a2'' where id = ''00000000-0000-4000-8000-0000000000f2'''));
select pg_temp.chk('Op1 nasceu com sdr1 como SDR (responsável era SDR)', '00000000-0000-4000-8000-0000000000a3',
  (select sdr_id::text from public.crm_opportunities where id = '00000000-0000-4000-8000-0000000000f1'));
select pg_temp.chk('sales_trial repassa a Op1 e tira o SDR', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'update public.crm_opportunities set owner_id = ''00000000-0000-4000-8000-0000000000a2'', sdr_id = null where id = ''00000000-0000-4000-8000-0000000000f1'''));
select pg_temp.chk('sales_trial atribui a Op4 a um SDR', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'update public.crm_opportunities set owner_id = ''00000000-0000-4000-8000-0000000000a4'' where id = ''00000000-0000-4000-8000-0000000000f4'''));
select pg_temp.chk('atribuir a um SDR preenche o SDR e ele passa a ver', '00000000-0000-4000-8000-0000000000a4/2',
  (select sdr_id::text from public.crm_opportunities where id = '00000000-0000-4000-8000-0000000000f4')
  || '/' || pg_temp.count_as('00000000-0000-4000-8000-0000000000a4', 'public.crm_opportunities'));
select pg_temp.chk('troca de responsável vai para o histórico', '1',
  (select count(*)::text from public.crm_audit_log
   where entity_type = 'opportunity' and entity_id = '00000000-0000-4000-8000-0000000000f1'
     and changes -> 'owner_id' ->> 'old' = '00000000-0000-4000-8000-0000000000a3'
     and changes -> 'owner_id' ->> 'new' = '00000000-0000-4000-8000-0000000000a2'
     and actor_id = '00000000-0000-4000-8000-0000000000a2'));
-- Quem só aparece no histórico do que o SDR vê também vem pelo nome.
select pg_temp.chk('sales_trial passa a Op2 pelo admin e de volta', 'ok:1/ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'update public.crm_opportunities set owner_id = ''00000000-0000-4000-8000-0000000000a1'' where id = ''00000000-0000-4000-8000-0000000000f2''')
  || '/' || pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'update public.crm_opportunities set owner_id = ''00000000-0000-4000-8000-0000000000a2'' where id = ''00000000-0000-4000-8000-0000000000f2'''));
select pg_temp.chk('sdr1 recebe o nome de quem foi responsável no histórico, sem e-mail', 'Teste Admin/0',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3',
    'select string_agg(m.full_name, '','') || ''/'' || count(m.email)::text from public.crm_list_members() m
      where m.id = ''00000000-0000-4000-8000-0000000000a1'''));
select pg_temp.chk('depois do repasse, sdr1 vê só a Op2 (via sdr_id)', 'TESTE Op 2',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3', 'select string_agg(title, '','' order by title) from public.crm_opportunities'));
select pg_temp.chk('sdr1 perde o histórico da Op1', '0',
  pg_temp.count_as('00000000-0000-4000-8000-0000000000a3',
    'public.crm_audit_log where entity_id = ''00000000-0000-4000-8000-0000000000f1'''));
select pg_temp.chk('sdr1 mantém o histórico da Op2', 'true',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3',
    'select (count(*) > 0)::text from public.crm_audit_log where entity_id = ''00000000-0000-4000-8000-0000000000f2'''));

-- ── Próxima ação vencida no indicador ───────────────────────────────────────
select pg_temp.chk('sales_trial agenda próxima ação (já vencida)', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'update public.crm_opportunities set next_action = ''Ligar'', next_action_at = now() - interval ''1 day'' where id = ''00000000-0000-4000-8000-0000000000f3'''));
select pg_temp.chk('ação vencida aparece na lista e no funil', 'true/1',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a2',
    'select next_action_overdue::text from public.crm_opportunity_overview where id = ''00000000-0000-4000-8000-0000000000f3''')
  || '/' || pg_temp.value_as('00000000-0000-4000-8000-0000000000a2',
    'select sum(overdue_count)::text from public.crm_funnel_summary'));

-- ── Criação por SDR ─────────────────────────────────────────────────────────
select pg_temp.chk('sdr1 cria oportunidade "para outro": vira dele', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'insert into public.crm_opportunities (id, title, owner_id, account_id) values (''00000000-0000-4000-8000-0000000000f5'', ''TESTE Op 5'', ''00000000-0000-4000-8000-0000000000a4'', ''00000000-0000-4000-8000-00000000ac0b'')'));
select pg_temp.chk('oportunidade do sdr1: dono, SDR e autor = sdr1', 'true',
  (select (owner_id = '00000000-0000-4000-8000-0000000000a3' and sdr_id = owner_id and created_by = owner_id)::text
   from public.crm_opportunities where id = '00000000-0000-4000-8000-0000000000f5'));
select pg_temp.chk('sdr1 não liga oportunidade a conta que não vê', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'insert into public.crm_opportunities (title, account_id) values (''TESTE Op invasora'', ''00000000-0000-4000-8000-00000000ac0c'')'));
select pg_temp.chk('sdr1 não move contato para conta que não vê', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_contacts set account_id = ''00000000-0000-4000-8000-00000000ac0c'' where id = ''00000000-0000-4000-8000-00000000c0b1'''));
select pg_temp.chk('sdr1 cria conta e ela é dele', 'ok:1/1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'insert into public.crm_accounts (id, name, owner_id) values (''00000000-0000-4000-8000-00000000ac0d'', ''TESTE Conta D'', null)')
  || '/' || pg_temp.count_as('00000000-0000-4000-8000-0000000000a3',
    'public.crm_accounts where id = ''00000000-0000-4000-8000-00000000ac0d'''));

-- ── Novo lead pela RPC (conta + contato + oportunidade) ─────────────────────
select pg_temp.chk('sdr1 cria lead completo pela RPC', 'true',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3',
    'select (public.crm_create_opportunity(
        p_request_id => ''00000000-0000-4000-8000-00000000cafe'', p_title => ''TESTE Lead RPC'',
        p_account_name => ''TESTE Clínica RPC'', p_contact_name => ''TESTE Dra. RPC'', p_contact_phone => ''61 9999-0000'',
        p_source => ''manual_indicacao'', p_estimated_value => 3900, p_owner_id => ''00000000-0000-4000-8000-0000000000a2''
      ) is not null)::text'));
select pg_temp.chk('repetir o envio não duplica nada', 'true/1/1/1',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3',
    'select (public.crm_create_opportunity(p_request_id => ''00000000-0000-4000-8000-00000000cafe'', p_title => ''TESTE Lead RPC'')
             = (select id from public.crm_opportunities where client_request_id = ''00000000-0000-4000-8000-00000000cafe''))::text')
  || '/' || (select count(*)::text from public.crm_opportunities where client_request_id = '00000000-0000-4000-8000-00000000cafe')
  || '/' || (select count(*)::text from public.crm_accounts      where client_request_id = '00000000-0000-4000-8000-00000000cafe')
  || '/' || (select count(*)::text from public.crm_contacts      where client_request_id = '00000000-0000-4000-8000-00000000cafe'));
select pg_temp.chk('lead criado pelo sdr1 é todo dele, ligado entre si', 'true',
  (select (o.owner_id = '00000000-0000-4000-8000-0000000000a3'
           and o.sdr_id = o.owner_id
           and a.owner_id = o.owner_id and c.owner_id = o.owner_id
           and c.account_id = a.id and o.account_id = a.id and o.contact_id = c.id
           and o.estimated_value = 3900 and o.source = 'manual_indicacao')::text
   from public.crm_opportunities o
   join public.crm_accounts a on a.id = o.account_id
   join public.crm_contacts c on c.id = o.contact_id
   where o.client_request_id = '00000000-0000-4000-8000-00000000cafe'));
select pg_temp.chk('RPC não liga a conta que o sdr1 não vê', 'err:42501',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a3',
    'select public.crm_create_opportunity(p_request_id => gen_random_uuid(), p_title => ''TESTE invasão'',
       p_account_id => ''00000000-0000-4000-8000-00000000ac0c'')::text'));
select pg_temp.chk('employee não cria pela RPC', 'err:42501',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a5',
    'select public.crm_create_opportunity(p_request_id => gen_random_uuid(), p_title => ''TESTE invasão'')::text'));

-- ── Atividades ──────────────────────────────────────────────────────────────
select pg_temp.chk('sdr1 registra atividade na Op2', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'insert into public.crm_activities (id, opportunity_id, type, summary, created_by, client_request_id) values (''00000000-0000-4000-8000-0000000000e4'', ''00000000-0000-4000-8000-0000000000f2'', ''message'', ''TESTE WhatsApp'', ''00000000-0000-4000-8000-0000000000a2'', ''00000000-0000-4000-8000-00000000beef'')'));
select pg_temp.chk('atividade: autor é quem gravou e conta vem da oportunidade', 'true',
  (select (created_by = '00000000-0000-4000-8000-0000000000a3'
           and account_id = '00000000-0000-4000-8000-00000000ac0b'
           and contact_id = '00000000-0000-4000-8000-00000000c0b1')::text
   from public.crm_activities where id = '00000000-0000-4000-8000-0000000000e4'));
select pg_temp.chk('envio duplicado (mesma chave) é recusado', 'err:23505',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'insert into public.crm_activities (opportunity_id, type, summary, client_request_id) values (''00000000-0000-4000-8000-0000000000f2'', ''message'', ''TESTE WhatsApp'', ''00000000-0000-4000-8000-00000000beef'')'));
select pg_temp.chk('sdr1 não registra atividade na Op3', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'insert into public.crm_activities (opportunity_id, type, summary) values (''00000000-0000-4000-8000-0000000000f3'', ''call'', ''TESTE invasão'')'));
select pg_temp.chk('atividade sem vínculo é recusada', 'err:23514',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'insert into public.crm_activities (type, summary) values (''note'', ''TESTE solta'')'));
select pg_temp.chk('sdr1 edita a própria atividade', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.crm_activities set summary = ''TESTE WhatsApp respondido'' where id = ''00000000-0000-4000-8000-0000000000e4'''));
select pg_temp.chk('edição de atividade vai para o histórico', '1',
  (select count(*)::text from public.crm_audit_log
   where entity_type = 'activity' and entity_id = '00000000-0000-4000-8000-0000000000e4' and action = 'update'));
select pg_temp.chk('sdr2 não edita atividade alheia (0 linhas)', 'ok:0',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a4',
    'update public.crm_activities set summary = ''x'' where id = ''00000000-0000-4000-8000-0000000000e2'''));

-- ── Histórico imutável e exclusão ───────────────────────────────────────────
select pg_temp.chk('ninguém do app altera o histórico', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a1', 'update public.crm_audit_log set action = ''delete'''));
select pg_temp.chk('ninguém do app apaga o histórico', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a1', 'delete from public.crm_audit_log'));
select pg_temp.chk('ninguém do app escreve no histórico', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'insert into public.crm_audit_log (entity_type, entity_id, action) values (''opportunity'', ''x'', ''update'')'));
select pg_temp.chk('sales_trial não exclui oportunidade (0 linhas)', 'ok:0',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'delete from public.crm_opportunities where id = ''00000000-0000-4000-8000-0000000000f4'''));
select pg_temp.chk('super_admin exclui', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a1',
    'delete from public.crm_opportunities where id = ''00000000-0000-4000-8000-0000000000f4'''));
select pg_temp.chk('a exclusão fica no histórico com autor', '1',
  (select count(*)::text from public.crm_audit_log
   where entity_id = '00000000-0000-4000-8000-0000000000f4' and action = 'delete'
     and actor_id = '00000000-0000-4000-8000-0000000000a1'));

-- ── Etapas ──────────────────────────────────────────────────────────────────
select pg_temp.chk('sdr1 não edita etapa (0 linhas)', 'ok:0',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3', 'update public.crm_stages set label = ''x'' where id = ''novo'''));
select pg_temp.chk('sales_trial não edita etapa (0 linhas)', 'ok:0',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2', 'update public.crm_stages set label = ''x'' where id = ''novo'''));
select pg_temp.chk('manager edita etapa', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'update public.crm_stages set probability = 15 where id = ''novo'''));
-- Ocupação neste ponto: Op1 em contato, Op2 em diagnostico, Op3/Op5/lead RPC
-- em novo; proposta, negociacao, ganho e perdido vazias.
select pg_temp.chk('Novo não pode ser desativada (entrada dos leads)', 'err:23514',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'update public.crm_stages set active = false where id = ''novo'''));
select pg_temp.chk('Novo não pode deixar de ser aberta', 'err:23514',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'update public.crm_stages set kind = ''won'' where id = ''novo'''));
select pg_temp.chk('etapa com oportunidades não é desativada', 'err:23514',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'update public.crm_stages set active = false where id = ''contato'''));
select pg_temp.chk('tipo de etapa com oportunidades não muda', 'err:23514',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'update public.crm_stages set kind = ''lost'' where id = ''diagnostico'''));
select pg_temp.chk('etapa vazia é desativada e reativada', 'ok:1/ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'update public.crm_stages set active = false where id = ''proposta''')
  || '/' || pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'update public.crm_stages set active = true where id = ''proposta'''));
select pg_temp.chk('o funil não fica sem etapa ganha ativa', 'err:23514',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'update public.crm_stages set active = false where id = ''ganho'''));
select pg_temp.chk('manager cria etapa', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7',
    'insert into public.crm_stages (id, label, position, kind, probability) values (''qualificacao'', ''Qualificação'', 25, ''open'', 30)'));
select pg_temp.chk('sales_trial não cria etapa', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'insert into public.crm_stages (id, label, position, kind) values (''invasao'', ''Invasão'', 99, ''open'')'));
select pg_temp.chk('id de etapa não muda', 'err:23514',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'update public.crm_stages set id = ''qualif'' where id = ''qualificacao'''));
select pg_temp.chk('reordenar exige todas as etapas', 'err:22023',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'select public.crm_reorder_stages(array[''novo'', ''contato''])'));
select pg_temp.chk('reordenar não aceita etapa repetida', 'err:22023',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7',
    'select public.crm_reorder_stages(array[''novo'',''novo'',''contato'',''diagnostico'',''proposta'',''negociacao'',''ganho'',''perdido''])'));
select pg_temp.chk('sales_trial não reordena', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a2',
    'select public.crm_reorder_stages(array[''novo'',''qualificacao'',''contato'',''diagnostico'',''proposta'',''negociacao'',''ganho'',''perdido''])'));
select pg_temp.chk('manager reordena', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7',
    'select public.crm_reorder_stages(array[''novo'',''contato'',''qualificacao'',''diagnostico'',''proposta'',''negociacao'',''ganho'',''perdido''])'));
select pg_temp.chk('ordem nova gravada de 10 em 10', 'novo:10,contato:20,qualificacao:30,diagnostico:40,proposta:50,negociacao:60,ganho:70,perdido:80',
  (select string_agg(id || ':' || position, ',' order by position) from public.crm_stages));
select pg_temp.chk('Novo não é excluída', 'err:23514',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'delete from public.crm_stages where id = ''novo'''));
select pg_temp.chk('etapa com oportunidades não é excluída', 'err:23503',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'delete from public.crm_stages where id = ''contato'''));
select pg_temp.chk('etapa vazia é excluída', 'ok:1',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a7', 'delete from public.crm_stages where id = ''qualificacao'''));
select pg_temp.chk('criação e exclusão de etapa ficam no histórico', '1/1',
  (select count(*) filter (where action = 'insert')::text || '/' || count(*) filter (where action = 'delete')::text
   from public.crm_audit_log where entity_type = 'stage' and entity_id = 'qualificacao'));

-- ── Ajuste de acesso sem novo APK ───────────────────────────────────────────
select pg_temp.chk('sdr1 não se promove pela coluna', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.profiles set crm_access = ''full'' where id = ''00000000-0000-4000-8000-0000000000a3'''));
select pg_temp.chk('sales_trial não usa a RPC de acesso', 'err:42501',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a2',
    'select public.crm_set_member_access(''00000000-0000-4000-8000-0000000000a2'', ''full'')::text'));
select pg_temp.chk('super_admin restringe o sales_trial', 'assigned',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a1',
    'select public.crm_set_member_access(''00000000-0000-4000-8000-0000000000a2'', ''assigned'') ->> ''access_level'''));
select pg_temp.chk('sales_trial restrito vê só as dele (Op1, Op2, Op3)', '3',
  pg_temp.count_as('00000000-0000-4000-8000-0000000000a2', 'public.crm_opportunities'));
select pg_temp.chk('ajuste de acesso fica no histórico', '1',
  (select count(*)::text from public.crm_audit_log
   where entity_type = 'member_access' and entity_id = '00000000-0000-4000-8000-0000000000a2'));
select pg_temp.chk('sales_trial não vê o histórico de acesso', '0',
  pg_temp.count_as('00000000-0000-4000-8000-0000000000a2', 'public.crm_audit_log where entity_type = ''member_access'''));
select pg_temp.chk('super_admin devolve o padrão (nulo = completo)', 'full',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a1',
    'select public.crm_set_member_access(''00000000-0000-4000-8000-0000000000a2'', null) ->> ''access_level'''));
select pg_temp.chk('employee com permissão explícita passa a ver tudo', 'full/',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a1',
    'select public.crm_set_member_access(''00000000-0000-4000-8000-0000000000a5'', ''full'') ->> ''access_level''') || '/'
  || (select case when pg_temp.count_as('00000000-0000-4000-8000-0000000000a5', 'public.crm_opportunities')
                       = (select count(*)::text from public.crm_opportunities) then '' else 'diferente' end));
select pg_temp.chk('client não recebe CRM nem pela RPC', 'err:22023',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a1',
    'select public.crm_set_member_access(''00000000-0000-4000-8000-0000000000a6'', ''full'')::text'));
update public.profiles set crm_access = 'full' where id = '00000000-0000-4000-8000-0000000000a6';
select pg_temp.chk('client continua sem CRM mesmo com a coluna forçada', '0',
  pg_temp.count_as('00000000-0000-4000-8000-0000000000a6', 'public.crm_opportunities'));
-- Fim da fase probatória: o papel muda no servidor e o acesso continua completo.
update public.profiles set role = 'partner' where id = '00000000-0000-4000-8000-0000000000a2';
select pg_temp.chk('sales_trial promovido a partner mantém CRM completo', 'full',
  pg_temp.value_as('00000000-0000-4000-8000-0000000000a2', 'select a->>''access_level'' from public.crm_my_access() a'));
select pg_temp.chk('authenticated não muda o próprio papel (trava existente)', 'err:42501',
  pg_temp.exec_as('00000000-0000-4000-8000-0000000000a3',
    'update public.profiles set role = ''partner'' where id = ''00000000-0000-4000-8000-0000000000a3'''));

-- ── Lead do site entra no funil ─────────────────────────────────────────────
set local role service_role;
insert into public.leads (id, name, email, whatsapp, clinic_type, revenue_range, source)
values ('00000000-0000-4000-8000-00000000ead1', 'TESTE Lead Site', 'lead-teste@example.invalid',
        '(61) 90000-0000', 'Odontologia', 'R$ 50 a 100 mil', 'lp_clinicas_hero_contato');
reset role;
select pg_temp.chk('lead do site vira contato e oportunidade em "novo" sem responsável', '1/1/novo/sem dono/Odontologia',
  (select count(*)::text from public.crm_contacts where lead_id = '00000000-0000-4000-8000-00000000ead1')
  || '/' || (select count(*)::text from public.crm_opportunities where lead_id = '00000000-0000-4000-8000-00000000ead1')
  || '/' || (select stage_id from public.crm_opportunities where lead_id = '00000000-0000-4000-8000-00000000ead1')
  || '/' || (select case when owner_id is null then 'sem dono' else 'com dono' end
             from public.crm_opportunities where lead_id = '00000000-0000-4000-8000-00000000ead1')
  || '/' || (select qualification ->> 'segment' from public.crm_opportunities where lead_id = '00000000-0000-4000-8000-00000000ead1'));
select pg_temp.chk('sdr não vê o lead sem atribuição', '0',
  pg_temp.count_as('00000000-0000-4000-8000-0000000000a3',
    'public.crm_opportunities where lead_id = ''00000000-0000-4000-8000-00000000ead1'''));
-- Falha no CRM não pode derrubar o cadastro do lead. A falha é simulada com
-- uma constraint provisória que recusa só a oportunidade deste lead.
alter table public.crm_opportunities
  add constraint crm_teste_falha check (title <> 'TESTE Lead Falha') not valid;
set local role service_role;
insert into public.leads (id, name, email, source)
values ('00000000-0000-4000-8000-00000000ead2', 'TESTE Lead Falha', 'lead-falha@example.invalid', 'hero_cta');
reset role;
alter table public.crm_opportunities drop constraint crm_teste_falha;
select pg_temp.chk('lead é gravado mesmo se o CRM falhar (e nada fica pela metade)', '1/0/0',
  (select count(*)::text from public.leads where id = '00000000-0000-4000-8000-00000000ead2')
  || '/' || (select count(*)::text from public.crm_contacts where lead_id = '00000000-0000-4000-8000-00000000ead2')
  || '/' || (select count(*)::text from public.crm_opportunities where lead_id = '00000000-0000-4000-8000-00000000ead2'));

-- Papel original de volta depois de tudo (as funções de teste não vazam papel)
select pg_temp.chk('papel da conexão restaurado', papel, current_user::text) from crm_papel_inicial;

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
