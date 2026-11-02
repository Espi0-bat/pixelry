-- 40 — Catálogo: grants como lista de permissão (anon sem nada; sem MAINTAIN;
-- authenticated só SELECT + colunas do contrato), EXECUTE em private só nos
-- três helpers, funções SECURITY DEFINER com search_path vazio, RLS ligada,
-- policies só dos comandos previstos, constraints/índices/FKs de §3.2/§3.5.
-- Leitura de catálogo como postgres (não há caso de permissão aqui; os
-- efeitos dos grants são exercitados como authenticated/anon nos arquivos 20–33).
begin;

-- ── objetos do módulo ───────────────────────────────────────────────────────
select tests.query_is('tabelas e view novas em public: exatamente as do contrato',
  $$select string_agg(relname, ',' order by relname collate "C") from pg_class
     where relnamespace = 'public'::regnamespace and relkind in ('r', 'v', 'm', 'p', 'f') and relname <> 'profiles'$$,
  'time_audit_events,time_breaks,time_shift_totals,time_shifts,work_deliverables,work_logs,work_task_events,work_tasks');
select tests.query_is('funções novas em public: exatamente as 10 RPCs',
  $$select string_agg(proname, ',' order by proname collate "C") from pg_proc
     where pronamespace = 'public'::regnamespace and proname not in ('is_admin', 'is_team', 'handle_new_user', 'guard_profile_role')$$,
  'ponto_people,time_clock_in,time_clock_out,time_correct_shift,time_create_manual_shift,time_end_break,time_my_status,time_review_shifts,time_start_break,time_void_shift');
select tests.query_is('btree_gist instalada no schema extensions',
  $$select extnamespace::regnamespace::text from pg_extension where extname = 'btree_gist'$$, 'extensions');

-- ── tabelas: grants ─────────────────────────────────────────────────────────
select tests.query_is('anon: nenhum privilégio de tabela (inclui MAINTAIN) nas 8 relações',
  $$select count(*)::text from unnest(array['public.time_shifts', 'public.time_breaks', 'public.time_audit_events', 'public.time_shift_totals',
                                           'public.work_tasks', 'public.work_logs', 'public.work_deliverables', 'public.work_task_events']) r,
          unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p
     where has_table_privilege('anon', r, p)$$, '0');
select tests.query_is('anon: nenhum privilégio de coluna',
  $$select count(*)::text from information_schema.column_privileges
     where grantee = 'anon' and table_schema = 'public' and table_name like any (array['time\_%', 'work\_%'])$$, '0');
select tests.query_is('PUBLIC: nenhum privilégio nas 8 relações',
  $$select count(*)::text from pg_class c, unnest(c.relacl) a
     where c.oid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass, 'public.time_shift_totals'::regclass,
                     'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass, 'public.work_task_events'::regclass)
       and a::text like '=%'$$, '0');
-- §1: sequência nova em public também nasce com ALL (USAGE/SELECT/UPDATE) para
-- anon/authenticated/service_role pelos privilégios padrão — e as colunas seq
-- (identity) criam uma sequência cada. "Revoga tudo, concede o necessário":
-- identity gera o valor sem checar privilégio na sequência, então nada precisa
-- ficar; com UPDATE, qualquer um chamaria setval() e quebraria a ordem (e o
-- índice único de seq) das auditorias, derrubando todas as batidas.
select tests.query_is('sequências do módulo: as duas identity de seq (time_audit_events, work_task_events)',
  $$select count(distinct c.oid)::text from pg_class c
      join pg_depend d on d.classid = 'pg_class'::regclass and d.objid = c.oid and d.refclassid = 'pg_class'::regclass
     where c.relkind = 'S' and d.refobjid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass,
       'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass, 'public.work_task_events'::regclass)$$, '2');
select tests.query_is('sequências do módulo: nenhum USAGE/SELECT/UPDATE para anon nem authenticated',
  $$select coalesce(string_agg(format('%s:%s:%s', s.oid::regclass, r, p), ', ' order by s.oid::regclass::text, r, p), '')
      from (select distinct c.oid from pg_class c
              join pg_depend d on d.classid = 'pg_class'::regclass and d.objid = c.oid and d.refclassid = 'pg_class'::regclass
             where c.relkind = 'S' and d.refobjid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass,
               'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass, 'public.work_task_events'::regclass)) s,
           unnest(array['anon', 'authenticated']) r, unnest(array['USAGE', 'SELECT', 'UPDATE']) p
     where has_sequence_privilege(r, s.oid, p)$$, '');
select tests.query_is('sequências do módulo: nada para PUBLIC',
  $$select count(*)::text from pg_class c
      join pg_depend d on d.classid = 'pg_class'::regclass and d.objid = c.oid and d.refclassid = 'pg_class'::regclass,
      unnest(c.relacl) a
     where c.relkind = 'S' and a::text like '=%'
       and d.refobjid in ('public.time_audit_events'::regclass, 'public.work_task_events'::regclass)$$, '0');
select tests.query_is('authenticated: só SELECT de tabela nas 8 relações (sem INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER/MAINTAIN)',
  $$select string_agg(distinct p, ',') from unnest(array['public.time_shifts', 'public.time_breaks', 'public.time_audit_events', 'public.time_shift_totals',
                                           'public.work_tasks', 'public.work_logs', 'public.work_deliverables', 'public.work_task_events']) r,
          unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER', 'MAINTAIN']) p
     where has_table_privilege('authenticated', r, p)$$, 'SELECT');
select tests.query_is('authenticated: SELECT em todas as 8',
  $$select count(*)::text from unnest(array['public.time_shifts', 'public.time_breaks', 'public.time_audit_events', 'public.time_shift_totals',
                                           'public.work_tasks', 'public.work_logs', 'public.work_deliverables', 'public.work_task_events']) r
     where has_table_privilege('authenticated', r, 'SELECT')$$, '8');
select tests.query_is('authenticated: nenhuma escrita por coluna nas tabelas de ponto',
  $$select count(*)::text from pg_attribute a
     where a.attrelid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass, 'public.work_task_events'::regclass)
       and a.attnum > 0 and not a.attisdropped
       and (has_column_privilege('authenticated', a.attrelid, a.attnum, 'INSERT') or has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE')
            or has_column_privilege('authenticated', a.attrelid, a.attnum, 'REFERENCES'))$$, '0');
select tests.query_is('work_tasks: INSERT só nas colunas do contrato',
  $$select string_agg(attname, ',' order by attname collate "C") from pg_attribute
     where attrelid = 'public.work_tasks'::regclass and attnum > 0 and not attisdropped and has_column_privilege('authenticated', attrelid, attnum, 'INSERT')$$,
  'assignee_id,description,due_date,id,priority,status,title');
select tests.query_is('work_tasks: UPDATE só nas colunas do contrato',
  $$select string_agg(attname, ',' order by attname collate "C") from pg_attribute
     where attrelid = 'public.work_tasks'::regclass and attnum > 0 and not attisdropped and has_column_privilege('authenticated', attrelid, attnum, 'UPDATE')$$,
  'assignee_id,description,due_date,priority,status,title');
select tests.query_is('work_logs: INSERT só nas colunas do contrato; sem UPDATE',
  $$select string_agg(attname, ',' order by attname collate "C") || '|' || bool_or(has_column_privilege('authenticated', attrelid, attnum, 'UPDATE'))::text
      from (select attrelid, attnum, attname from pg_attribute
             where attrelid = 'public.work_logs'::regclass and attnum > 0 and not attisdropped) a
     where has_column_privilege('authenticated', attrelid, attnum, 'INSERT') or has_column_privilege('authenticated', attrelid, attnum, 'UPDATE')$$,
  'id,logged_on,minutes_spent,result,shift_id,summary,task_id|false');
select tests.query_is('work_deliverables: INSERT só nas colunas do contrato; sem UPDATE',
  $$select string_agg(attname, ',' order by attname collate "C") || '|' || bool_or(has_column_privilege('authenticated', attrelid, attnum, 'UPDATE'))::text
      from (select attrelid, attnum, attname from pg_attribute
             where attrelid = 'public.work_deliverables'::regclass and attnum > 0 and not attisdropped) a
     where has_column_privilege('authenticated', attrelid, attnum, 'INSERT') or has_column_privilege('authenticated', attrelid, attnum, 'UPDATE')$$,
  'id,notes,task_id,title,url,work_log_id|false');
select tests.query_is('nenhuma REFERENCES de coluna para authenticated nas tabelas de trabalho',
  $$select count(*)::text from pg_attribute a
     where a.attrelid in ('public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass)
       and a.attnum > 0 and not a.attisdropped and has_column_privilege('authenticated', a.attrelid, a.attnum, 'REFERENCES')$$, '0');

-- ── RLS e policies ──────────────────────────────────────────────────────────
select tests.query_is('RLS ligada nas 7 tabelas',
  $$select count(*)::text from pg_class where oid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass,
       'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass, 'public.work_task_events'::regclass) and relrowsecurity$$, '7');
select tests.query_is('comandos das policies por tabela (r=SELECT, a=INSERT, w=UPDATE; nada de ALL/DELETE)',
  $$select string_agg(t || ':' || cmds, ' ' order by t collate "C") from (
      select c.relname::text t, string_agg(p.polcmd::text, '' order by p.polcmd::text) cmds
        from pg_class c left join pg_policy p on p.polrelid = c.oid
       where c.oid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass,
                       'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass, 'public.work_task_events'::regclass)
       group by c.relname) q$$,
  'time_audit_events:r time_breaks:r time_shifts:r work_deliverables:ar work_logs:ar work_task_events:r work_tasks:arw');
select tests.query_true('todas as policies do módulo são permissivas e só para authenticated',
  $$select bool_and(p.polpermissive and p.polroles = array['authenticated'::regrole::oid])
     from pg_policy p where p.polrelid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass,
       'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass, 'public.work_task_events'::regclass)$$);
select tests.query_true('policies chamam os helpers dentro de (select …) (initplan)',
  $$select bool_and(coalesce(pg_get_expr(p.polqual, p.polrelid), pg_get_expr(p.polwithcheck, p.polrelid)) like '%SELECT private.pt_is_internal()%')
     from pg_policy p where p.polrelid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass,
       'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass, 'public.work_task_events'::regclass)$$);
select tests.query_true('nenhuma policy do módulo usa is_admin()/is_team()',
  $$select not bool_or(coalesce(pg_get_expr(p.polqual, p.polrelid), '') || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') ~ '(is_admin|is_team)\(')
     from pg_policy p where p.polrelid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass,
       'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass, 'public.work_task_events'::regclass)$$);
-- §3.0: coluna da tabela externa solta numa subconsulta (`l.task_id = task_id`)
-- se resolve para a tabela de dentro e o Postgres guarda `l.task_id =
-- l.task_id` (sempre verdadeiro). O texto que o catálogo devolve mostra isso.
select tests.query_is('nenhuma policy compara uma coluna com ela mesma (coluna externa solta em subconsulta)',
  $$select coalesce(string_agg(c.relname || '.' || p.polname, ', ' order by c.relname, p.polname), '')
     from pg_policy p join pg_class c on c.oid = p.polrelid
    where p.polrelid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass,
       'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass, 'public.work_task_events'::regclass)
      and (coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), ''))
          ~ '\m([a-z_]+)\.([a-z_]+) = \1\.\2\M'$$,
  '');
select tests.query_true('subconsultas das policies nomeiam a coluna externa pela tabela (work_logs/work_deliverables/work_task_events)',
  $$select bool_and(expr like all (pats)) from (
      select coalesce(pg_get_expr(p.polqual, p.polrelid), '') || ' ' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') as expr,
             case p.polname
               when 'work_logs_insert'         then array['%t.id = work_logs.task_id%', '%s.id = work_logs.shift_id%']
               when 'work_deliverables_insert' then array['%t.id = work_deliverables.task_id%', '%l.id = work_deliverables.work_log_id%',
                                                          '%l.task_id = work_deliverables.task_id%']
               when 'work_deliverables_select' then array['%t.id = work_deliverables.task_id%']
               when 'work_task_events_select'  then array['%t.id = work_task_events.task_id%']
             end as pats
        from pg_policy p
       where p.polname in ('work_logs_insert', 'work_deliverables_insert', 'work_deliverables_select', 'work_task_events_select')) q
    having count(*) = 4$$);
select tests.query_true('view time_shift_totals com security_invoker',
  $$select 'security_invoker=true' = any (reloptions) from pg_class where oid = 'public.time_shift_totals'::regclass$$);

-- ── RPCs ────────────────────────────────────────────────────────────────────
select tests.query_is('assinaturas exatas das RPCs (nome, argumentos)',
  $$select string_agg(proname || '(' || pg_get_function_identity_arguments(oid) || ')', ' ' order by proname collate "C")
     from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'time\_%' or proname = 'ponto_people')$$,
  'ponto_people() time_clock_in(p_request_id uuid, p_note text) time_clock_out(p_request_id uuid, p_close_open_break boolean, p_note text) '
  || 'time_correct_shift(p_shift_id uuid, p_started_at timestamp with time zone, p_ended_at timestamp with time zone, p_breaks jsonb, p_reason text, p_request_id uuid) '
  || 'time_create_manual_shift(p_user_id uuid, p_started_at timestamp with time zone, p_ended_at timestamp with time zone, p_breaks jsonb, p_reason text, p_request_id uuid) '
  || 'time_end_break(p_request_id uuid) time_my_status() time_review_shifts(p_shifts jsonb, p_note text) time_start_break(p_request_id uuid) '
  || 'time_void_shift(p_shift_id uuid, p_reason text, p_request_id uuid)');
select tests.query_is('defaults das RPCs (pronargdefaults)',
  $$select string_agg(proname || '=' || pronargdefaults, ' ' order by proname collate "C")
     from pg_proc where pronamespace = 'public'::regnamespace and proname like 'time\_%'$$,
  'time_clock_in=2 time_clock_out=3 time_correct_shift=1 time_create_manual_shift=1 time_end_break=1 time_my_status=0 time_review_shifts=1 time_start_break=1 time_void_shift=1');
select tests.query_is('retornos: jsonb (integer em review)',
  $$select string_agg(proname || '=' || pg_get_function_result(oid), ' ' order by proname collate "C")
     from pg_proc where pronamespace = 'public'::regnamespace and proname like 'time\_%'$$,
  'time_clock_in=jsonb time_clock_out=jsonb time_correct_shift=jsonb time_create_manual_shift=jsonb time_end_break=jsonb time_my_status=jsonb time_review_shifts=integer time_start_break=jsonb time_void_shift=jsonb');
select tests.query_true('RPCs time_*: plpgsql, SECURITY DEFINER, VOLATILE, search_path vazio',
  $$select bool_and(l.lanname = 'plpgsql' and p.prosecdef and p.provolatile = 'v' and p.proconfig = array['search_path=""'])
     from pg_proc p join pg_language l on l.oid = p.prolang where p.pronamespace = 'public'::regnamespace and p.proname like 'time\_%'$$);
select tests.query_true('ponto_people: sql, STABLE, SECURITY DEFINER, search_path vazio',
  $$select l.lanname = 'sql' and p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
     from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = 'public.ponto_people()'::regprocedure$$);
select tests.query_true('RPCs: EXECUTE para authenticated',
  $$select bool_and(has_function_privilege('authenticated', oid, 'EXECUTE'))
     from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'time\_%' or proname = 'ponto_people')$$);
select tests.query_true('RPCs: sem EXECUTE para anon',
  $$select not bool_or(has_function_privilege('anon', oid, 'EXECUTE'))
     from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'time\_%' or proname = 'ponto_people')$$);
select tests.query_is('RPCs: sem EXECUTE para PUBLIC',
  $$select count(*)::text from pg_proc p, unnest(p.proacl) a
     where p.pronamespace = 'public'::regnamespace and (p.proname like 'time\_%' or p.proname = 'ponto_people') and a::text like '=%'$$, '0');
select tests.query_true('RPCs: ACL explícita (não o padrão implícito, que inclui PUBLIC)',
  $$select bool_and(proacl is not null) from pg_proc where pronamespace = 'public'::regnamespace and (proname like 'time\_%' or proname = 'ponto_people')$$);

-- ── schema private ──────────────────────────────────────────────────────────
select tests.query_true('private: USAGE para authenticated e service_role',
  $$select has_schema_privilege('authenticated', 'private', 'USAGE') and has_schema_privilege('service_role', 'private', 'USAGE')$$);
select tests.query_true('private: sem USAGE para anon e sem CREATE para authenticated',
  $$select not has_schema_privilege('anon', 'private', 'USAGE') and not has_schema_privilege('authenticated', 'private', 'CREATE')$$);
select tests.query_is('private: nada para PUBLIC',
  $$select count(*)::text from pg_namespace n, unnest(n.nspacl) a where n.nspname = 'private' and a::text like '=%'$$, '0');
select tests.query_is('private: EXECUTE para authenticated SÓ nos três helpers',
  $$select string_agg(proname, ',' order by proname collate "C") from pg_proc
     where pronamespace = 'private'::regnamespace and has_function_privilege('authenticated', oid, 'EXECUTE')$$,
  'pt_current_role,pt_is_internal,pt_is_super_admin');
select tests.query_is('private: nenhuma função com EXECUTE para PUBLIC',
  $$select count(*)::text from pg_proc p where p.pronamespace = 'private'::regnamespace
       and (p.proacl is null or exists (select 1 from unnest(p.proacl) a where a::text like '=%'))$$, '0');
select tests.query_is('private: nenhuma função com EXECUTE para anon',
  $$select count(*)::text from pg_proc p, unnest(p.proacl) a where p.pronamespace = 'private'::regnamespace and a::text like 'anon=%'$$, '0');
select tests.query_true('private: service_role executa os helpers',
  $$select bool_and(has_function_privilege('service_role', ('private.' || f || '()')::regprocedure, 'EXECUTE'))
     from unnest(array['pt_current_role', 'pt_is_internal', 'pt_is_super_admin']) f$$);
select tests.query_is('helpers: sql, STABLE, SECURITY DEFINER, search_path vazio, retornos',
  $$select string_agg(proname || ':' || pg_get_function_result(oid) || ':' || (prosecdef and provolatile = 's' and proconfig = array['search_path=""']
                        and prolang = (select oid from pg_language where lanname = 'sql'))::text, ' ' order by proname collate "C")
     from pg_proc where pronamespace = 'private'::regnamespace and proname in ('pt_current_role', 'pt_is_internal', 'pt_is_super_admin')$$,
  'pt_current_role:text:true pt_is_internal:boolean:true pt_is_super_admin:boolean:true');
select tests.query_true('toda função SECURITY DEFINER do módulo tem search_path vazio',
  $$select bool_and(p.proconfig @> array['search_path=""'])
     from pg_proc p where p.prosecdef and (p.pronamespace = 'private'::regnamespace
       or (p.pronamespace = 'public'::regnamespace and (p.proname like 'time\_%' or p.proname = 'ponto_people')))$$);
-- §1: dentro de SECURITY DEFINER, current_user é o dono da função. Uma função
-- DEFINER que testasse `current_user in ('authenticated','anon')` acharia que
-- ninguém é usuário final e pularia as regras de coluna.
select tests.query_is('nenhuma função SECURITY DEFINER do módulo lê current_user/session_user/current_role',
  $$select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text), '')
     from pg_proc p
    where p.prosecdef
      and (p.pronamespace = 'private'::regnamespace
           or (p.pronamespace = 'public'::regnamespace and (p.proname like 'time\_%' or p.proname = 'ponto_people')))
      and p.prosrc ~* '\m(current_user|session_user|current_role)\M'$$,
  '');
select tests.query_is('controle: só os três triggers INVOKER de §3.5 olham current_user',
  $$select string_agg(p.proname, ',' order by p.proname collate "C")
     from pg_proc p
    where (p.pronamespace = 'private'::regnamespace
           or (p.pronamespace = 'public'::regnamespace and (p.proname like 'time\_%' or p.proname = 'ponto_people')))
      and p.prosrc ~* '\mcurrent_user\M' and not p.prosecdef$$,
  'work_deliverables_before_insert,work_logs_before_insert,work_tasks_before_write');
select tests.query_true('time_shift_json(p_shift_id uuid) → jsonb, SECURITY INVOKER',
  $$select pg_get_function_result(p.oid) = 'jsonb' and not p.prosecdef
     from pg_proc p where p.oid = 'private.time_shift_json(uuid)'::regprocedure$$);
select tests.query_is('segurança das funções de trigger (INVOKER só onde o contrato manda olhar current_user)',
  $$select string_agg(proname || '=' || case when prosecdef then 'definer' else 'invoker' end, ' ' order by proname collate "C")
     from pg_proc where pronamespace = 'private'::regnamespace and proname in (
       'work_tasks_before_write', 'work_tasks_validate_assignee', 'work_logs_before_insert', 'work_deliverables_before_insert',
       'work_tasks_log_event', 'work_logs_log_event', 'work_deliverables_log_event', 'time_breaks_guard', 'time_shifts_guard')$$,
  'time_breaks_guard=definer time_shifts_guard=definer work_deliverables_before_insert=invoker work_deliverables_log_event=definer '
  || 'work_logs_before_insert=invoker work_logs_log_event=definer work_tasks_before_write=invoker work_tasks_log_event=definer work_tasks_validate_assignee=definer');
select tests.query_true('triggers INVOKER do trabalho com search_path vazio',
  $$select bool_and(proconfig @> array['search_path=""']) from pg_proc
     where pronamespace = 'private'::regnamespace and proname in ('work_tasks_before_write', 'work_logs_before_insert', 'work_deliverables_before_insert')$$);
select tests.query_true('pt_set_updated_at existe em private',
  $$select count(*) = 1 from pg_proc where pronamespace = 'private'::regnamespace and proname = 'pt_set_updated_at'$$);

-- ── triggers ────────────────────────────────────────────────────────────────
select tests.query_true('todas as funções de trigger das tabelas do módulo estão em private',
  $$select bool_and(p.pronamespace = 'private'::regnamespace)
     from pg_trigger t join pg_proc p on p.oid = t.tgfoid
    where not t.tgisinternal and t.tgrelid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass,
       'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass, 'public.work_task_events'::regclass)$$);
select tests.query_true('triggers imediatos (nenhum constraint trigger adiável)',
  $$select bool_and(not t.tgdeferrable and t.tgconstraint = 0)
     from pg_trigger t where not t.tgisinternal and t.tgrelid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass,
       'public.time_audit_events'::regclass, 'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass,
       'public.work_task_events'::regclass)$$);
select tests.query_true('time_breaks_guard: BEFORE INSERT OR UPDATE em time_breaks',
  $$select bool_or(pg_get_triggerdef(t.oid) like '%BEFORE INSERT OR UPDATE ON public.time_breaks FOR EACH ROW%')
     from pg_trigger t where t.tgrelid = 'public.time_breaks'::regclass and t.tgfoid = 'private.time_breaks_guard()'::regprocedure$$);
select tests.query_true('time_shifts_guard: AFTER UPDATE em time_shifts',
  $$select bool_or(pg_get_triggerdef(t.oid) like '%AFTER UPDATE ON public.time_shifts FOR EACH ROW%')
     from pg_trigger t where t.tgrelid = 'public.time_shifts'::regclass and t.tgfoid = 'private.time_shifts_guard()'::regprocedure$$);
-- tgtype: bit 1 = BEFORE, 8 = DELETE, 16 = UPDATE (um trigger para os dois
-- eventos ou dois triggers separados, tanto faz).
select tests.query_true('auditorias: trigger BEFORE UPDATE e BEFORE DELETE nas duas tabelas',
  $$select bool_and(has_upd and has_del) and count(*) = 2 from (
      select r.oid,
             exists (select 1 from pg_trigger t where t.tgrelid = r.oid and not t.tgisinternal and t.tgtype & 2 = 2 and t.tgtype & 16 = 16) as has_upd,
             exists (select 1 from pg_trigger t where t.tgrelid = r.oid and not t.tgisinternal and t.tgtype & 2 = 2 and t.tgtype & 8 = 8) as has_del
        from pg_class r where r.oid in ('public.time_audit_events'::regclass, 'public.work_task_events'::regclass)) q$$);
select tests.query_true('work_tasks_validate_assignee: BEFORE INSERT OR UPDATE OF assignee_id',
  $$select bool_or(pg_get_triggerdef(t.oid) like '%BEFORE INSERT OR UPDATE OF assignee_id ON public.work_tasks%')
     from pg_trigger t where t.tgfoid = 'private.work_tasks_validate_assignee()'::regprocedure$$);

-- ── constraints, índices e FKs ──────────────────────────────────────────────
select tests.query_is('constraints nomeadas de §3.2',
  $$select string_agg(conname, ',' order by conname collate "C") from pg_constraint
     where conname in ('time_shifts_range_chk', 'time_shifts_void_chk', 'time_shifts_review_chk', 'time_shifts_reviewed_closed_chk',
                       'time_shifts_no_overlap', 'time_breaks_range_chk', 'time_breaks_no_overlap', 'time_audit_reason_chk')$$,
  'time_audit_reason_chk,time_breaks_no_overlap,time_breaks_range_chk,time_shifts_no_overlap,time_shifts_range_chk,time_shifts_review_chk,time_shifts_reviewed_closed_chk,time_shifts_void_chk');
select tests.query_true('time_shifts_no_overlap: EXCLUDE gist (user_id =, tstzrange [) &&) WHERE voided_at IS NULL',
  $$select contype = 'x' and pg_get_constraintdef(oid) like 'EXCLUDE USING gist (user_id WITH =, tstzrange(started_at, ended_at, ''[)''::text) WITH &&) WHERE ((voided_at IS NULL))'
     from pg_constraint where conname = 'time_shifts_no_overlap'$$);
select tests.query_true('time_breaks_no_overlap: EXCLUDE gist (shift_id =, tstzrange [) &&)',
  $$select contype = 'x' and pg_get_constraintdef(oid) = 'EXCLUDE USING gist (shift_id WITH =, tstzrange(started_at, ended_at, ''[)''::text) WITH &&)'
     from pg_constraint where conname = 'time_breaks_no_overlap'$$);
select tests.query_is('time_audit_events_request_uniq (definição exata)',
  $$select pg_get_indexdef('public.time_audit_events_request_uniq'::regclass)$$,
  'CREATE UNIQUE INDEX time_audit_events_request_uniq ON public.time_audit_events USING btree (actor_id, request_id) WHERE (request_id IS NOT NULL)');
select tests.query_is('índices de §3.2/§3.5 presentes (tabela: colunas)',
  $$select string_agg(expect, ' ' order by expect collate "C") from (values
      ('time_shifts', 'btree (user_id, work_date DESC)'), ('time_shifts', 'btree (work_date)'),
      ('time_shifts', 'btree (review_status) WHERE (review_status = ''pending''::text)'),
      ('time_breaks', 'btree (shift_id, started_at)'), ('time_breaks', 'btree (user_id, started_at)'),
      ('time_audit_events', 'btree (seq)'), ('time_audit_events', 'btree (subject_user_id, created_at DESC)'), ('time_audit_events', 'btree (shift_id, seq)'),
      ('work_tasks', 'btree (assignee_id, status)'), ('work_tasks', 'btree (created_by)'), ('work_tasks', 'btree (status)'), ('work_tasks', 'btree (due_date)'),
      ('work_logs', 'btree (task_id, created_at DESC)'), ('work_logs', 'btree (user_id, logged_on DESC)'), ('work_logs', 'btree (shift_id)'),
      ('work_deliverables', 'btree (task_id, created_at DESC)'),
      ('work_task_events', 'btree (seq)'), ('work_task_events', 'btree (task_id, seq)')) as e(tbl, cols)
     cross join lateral (select case when exists (select 1 from pg_indexes i where i.schemaname = 'public' and i.tablename = e.tbl
                                                   and i.indexdef like '% USING ' || e.cols)
                                     then 'ok' else 'FALTA:' || e.tbl || '(' || e.cols || ')' end as expect) x
     where x.expect <> 'ok'$$, null);
select tests.query_true('seq único nas duas auditorias',
  $$select count(*) = 2 from pg_index i where i.indisunique and i.indrelid in ('public.time_audit_events'::regclass, 'public.work_task_events'::regclass)
       and pg_get_indexdef(i.indexrelid) like '%USING btree (seq)'$$);
select tests.query_true('seq é identity ALWAYS nas duas auditorias',
  $$select bool_and(attidentity = 'a') and count(*) = 2 from pg_attribute
     where attname = 'seq' and attrelid in ('public.time_audit_events'::regclass, 'public.work_task_events'::regclass)$$);
select tests.query_is('FKs: só time_breaks.shift_id em cascade; todas as outras RESTRICT',
  $$select string_agg(c.conrelid::regclass::text || '.' || a.attname || '=' || c.confdeltype::text, ' ' order by 1)
     from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.contype = 'f' and c.conrelid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass, 'public.time_audit_events'::regclass,
       'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass, 'public.work_task_events'::regclass)
      and not (c.confdeltype = 'r' or (c.conrelid = 'public.time_breaks'::regclass and a.attname = 'shift_id' and c.confdeltype = 'c'))$$, null);
select tests.query_is('quantidade de FKs do módulo (§3.2 + §3.5)',
  $$select count(*)::text from pg_constraint c where c.contype = 'f' and c.conrelid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass,
       'public.time_audit_events'::regclass, 'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass,
       'public.work_task_events'::regclass)$$, '19');
select tests.query_true('FKs para pessoas apontam para public.profiles (não auth.users)',
  $$select bool_and(c.confrelid in ('public.profiles'::regclass, 'public.time_shifts'::regclass, 'public.work_tasks'::regclass, 'public.work_logs'::regclass))
     from pg_constraint c where c.contype = 'f' and c.conrelid in ('public.time_shifts'::regclass, 'public.time_breaks'::regclass,
       'public.time_audit_events'::regclass, 'public.work_tasks'::regclass, 'public.work_logs'::regclass, 'public.work_deliverables'::regclass,
       'public.work_task_events'::regclass)$$);

-- ── colunas e defaults ──────────────────────────────────────────────────────
select tests.query_is('colunas de time_shifts',
  $$select string_agg(attname, ',' order by attname collate "C") from pg_attribute where attrelid = 'public.time_shifts'::regclass and attnum > 0 and not attisdropped$$,
  'created_at,ended_at,id,last_corrected_at,last_corrected_by,note,review_status,reviewed_at,reviewed_by,source,started_at,updated_at,user_id,void_reason,voided_at,voided_by,work_date');
select tests.query_is('colunas de time_breaks',
  $$select string_agg(attname, ',' order by attname collate "C") from pg_attribute where attrelid = 'public.time_breaks'::regclass and attnum > 0 and not attisdropped$$,
  'created_at,ended_at,id,shift_id,started_at,updated_at,user_id');
select tests.query_is('colunas de time_audit_events',
  $$select string_agg(attname, ',' order by attname collate "C") from pg_attribute where attrelid = 'public.time_audit_events'::regclass and attnum > 0 and not attisdropped$$,
  'action,actor_id,after,before,created_at,id,reason,request_id,seq,shift_id,subject_user_id');
select tests.query_is('colunas de work_tasks',
  $$select string_agg(attname, ',' order by attname collate "C") from pg_attribute where attrelid = 'public.work_tasks'::regclass and attnum > 0 and not attisdropped$$,
  'assignee_id,completed_at,created_at,created_by,description,due_date,id,priority,priority_rank,status,title,updated_at');
select tests.query_is('colunas de work_logs',
  $$select string_agg(attname, ',' order by attname collate "C") from pg_attribute where attrelid = 'public.work_logs'::regclass and attnum > 0 and not attisdropped$$,
  'created_at,id,logged_on,minutes_spent,result,shift_id,summary,task_id,user_id');
select tests.query_is('colunas de work_deliverables',
  $$select string_agg(attname, ',' order by attname collate "C") from pg_attribute where attrelid = 'public.work_deliverables'::regclass and attnum > 0 and not attisdropped$$,
  'created_at,created_by,id,notes,task_id,title,url,work_log_id');
select tests.query_is('colunas de work_task_events',
  $$select string_agg(attname, ',' order by attname collate "C") from pg_attribute where attrelid = 'public.work_task_events'::regclass and attnum > 0 and not attisdropped$$,
  'action,actor_id,changes,created_at,id,seq,task_id');
select tests.query_true('created_at das auditorias com default clock_timestamp()',
  $$select bool_and(pg_get_expr(d.adbin, d.adrelid) = 'clock_timestamp()') and count(*) = 2
     from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where a.attname = 'created_at' and d.adrelid in ('public.time_audit_events'::regclass, 'public.work_task_events'::regclass)$$);
select tests.query_true('work_tasks.created_by e work_logs.user_id e work_deliverables.created_by com default auth.uid()',
  $$select bool_and(pg_get_expr(d.adbin, d.adrelid) = 'auth.uid()') and count(*) = 3
     from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where (d.adrelid, a.attname) in (('public.work_tasks'::regclass, 'created_by'), ('public.work_logs'::regclass, 'user_id'),
                                     ('public.work_deliverables'::regclass, 'created_by'))$$);
select tests.query_true('work_logs.logged_on: default = data de hoje em America/Sao_Paulo',
  $$select pg_get_expr(d.adbin, d.adrelid) like '%America/Sao_Paulo%'
     from pg_attrdef d join pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
    where d.adrelid = 'public.work_logs'::regclass and a.attname = 'logged_on'$$);
select tests.query_true('priority_rank gerada armazenada', $$select attgenerated = 's' from pg_attribute where attrelid = 'public.work_tasks'::regclass and attname = 'priority_rank'$$);

select tests.done();
rollback;
