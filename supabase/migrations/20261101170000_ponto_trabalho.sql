-- Ponto e Trabalho — ponto (jornada, intervalos, correções, revisão) e tarefas
-- da equipe (tarefas, registros do que foi feito, entregas, histórico).
--
-- Contrato: docs/PONTO_TRABALHO_DESIGN.md (§3) no repositório do app.
--
-- A Pixelry ainda não tem horário fixo. O ponto é obrigatório, mas nesta fase
-- serve para MEDIR quanto cada pessoa trabalha antes de existir cobrança ou
-- meta. Por isso a regra mais dura aqui é de privacidade: só o super_admin vê,
-- corrige e revisa o ponto de outra pessoa — garantido por RLS e pelas RPCs,
-- não escondendo telas no app.
--
-- Decisões que atravessam o arquivo:
--   * Migration única e idempotente: roda duas vezes seguidas sem erro e deixa
--     o mesmo estado (if not exists, create or replace, drop … if exists antes
--     de criar, grants repetidos ao fim de cada seção). Sem begin/commit: a CLI
--     já roda cada migration na própria transação. Não toca em dados nem em
--     objetos existentes (profiles, profiles_role_check, policies alheias).
--   * Papéis tratados por TEXTO. O módulo já conhece partner, sales_trial,
--     employee_dev e sdr, mas a profiles_role_check de hoje só aceita
--     super_admin, manager, employee e client. A constraint NÃO é alterada aqui
--     (mudança global, documentada no contrato §6); com os quatro papéis
--     aceitos hoje tudo já funciona.
--   * is_admin()/is_team() não servem a este módulo: is_admin() inclui manager
--     e is_team() não conhece os papéis novos. Os helpers ficam em `private`,
--     schema que o PostgREST não expõe.
--   * Grants em LISTA DE PERMISSÃO. O Supabase dá ALL (no PG 17 isso inclui
--     MAINTAIN) a anon/authenticated/service_role em toda tabela, sequência e
--     função nova de public, e o Postgres dá EXECUTE de função a PUBLIC. Um
--     revoke parcial deixaria sobras; então revoga tudo e concede o necessário.
--   * Lição paga em produção (20260903175521): expressão de policy exige
--     EXECUTE do papel que consulta em TODA função que ela chama. Por isso os
--     três helpers usados nas policies mantêm EXECUTE para authenticated, e
--     são os únicos de `private` que mantêm. Função de trigger não exige.
--   * Dentro de SECURITY DEFINER, current_user é o dono da função. Quem precisa
--     do papel real da conexão (`current_user in ('authenticated','anon')`) é
--     SECURITY INVOKER — mesmo padrão do guard_profile_role (20260902000050).
--     Quem escreve em outra tabela ou lê o perfil de outra pessoa é DEFINER.
--   * Ponto só se escreve pelas RPCs (SECURITY DEFINER, search_path vazio e
--     nomes 100% qualificados). authenticated só tem SELECT nas tabelas.
--
-- Furo global conhecido, ANTERIOR a este módulo (contrato §6.1): pelas
-- migrations, manager (via is_admin() em "Admin full access" de profiles)
-- consegue DELETE + INSERT de um perfil com role = 'super_admin', porque o
-- profiles_guard_role só cobre UPDATE. Isso fura qualquer regra baseada em
-- profiles.role, inclusive a deste módulo. A correção é global e fica proposta
-- no documento de integração; não é aplicada aqui.


-- ════════════════════════════════════════════════════════════════════════════
-- 1. Base
-- ════════════════════════════════════════════════════════════════════════════

-- btree_gist dá o operador = de uuid dentro de índice GiST: é o que permite a
-- exclusion constraint "mesma pessoa E faixas de horário que se cruzam".
create extension if not exists btree_gist with schema extensions;

-- `private` não é exposto pelo PostgREST: nada daqui vira /rest/v1/rpc.
-- USAGE para authenticated porque as policies chamam os helpers.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

-- ── Helpers de papel ───────────────────────────────────────────────────────
-- Lista dos sete papéis internos num lugar só. Chamada apenas de dentro de
-- funções DEFINER (o dono executa), então não precisa de EXECUTE para ninguém.
create or replace function private.pt_is_internal_role(p_role text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    p_role = any (array['super_admin', 'partner', 'manager', 'sales_trial',
                        'employee_dev', 'employee', 'sdr']),
    false)
$$;

revoke all on function private.pt_is_internal_role(text) from public, anon, authenticated;

-- DEFINER porque profiles tem RLS: lido como o próprio usuário, o resultado
-- dependeria das policies de profiles (e poderia recursar nelas).
-- Sem perfil → null ("desconhecido" = sem acesso).
create or replace function private.pt_current_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p where p.id = auth.uid()
$$;

create or replace function private.pt_is_internal()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.pt_is_internal_role(private.pt_current_role())
$$;

create or replace function private.pt_is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.pt_current_role() = 'super_admin', false)
$$;

-- ── Funções de trigger compartilhadas ──────────────────────────────────────
create or replace function private.pt_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function private.pt_set_updated_at() from public, anon, authenticated;

-- Auditoria é somente inclusão. Nem o dono da tabela edita ou apaga linha:
-- o trigger barra UPDATE/DELETE de qualquer papel.
create or replace function private.pt_audit_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit_immutable'
    using errcode = '42501',
          detail  = 'Você não tem permissão para esta ação.';
end;
$$;

revoke all on function private.pt_audit_immutable() from public, anon, authenticated;

-- Trim de espaço em branco nas duas pontas (btrim sozinho só tira espaço).
-- Justificativas e notas passam por aqui. A lista é EXPLÍCITA, e não
-- [[:space:]], por dois motivos: [[:space:]] depende do locale do banco (no C
-- não pega nada fora do ASCII; na glibc pega U+3000 mas não o espaço não
-- separável), e o app valida com String.trim do Dart, que tira exatamente
-- estes: U+0009–U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000–U+200A,
-- U+2028, U+2029, U+202F, U+205F, U+3000 e U+FEFF (BOM). Assim uma
-- justificativa que para o app é vazia ou curta também é para o servidor.
-- E'…\\u…': o escape \uXXXX chega à regex qualquer que seja o
-- standard_conforming_strings da sessão que aplica a migration.
create or replace function private.pt_trim(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(
    p_text,
    E'^[\\u0009-\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]+'
    || E'|[\\u0009-\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000\\uFEFF]+$',
    '', 'g')
$$;

revoke all on function private.pt_trim(text) from public, anon, authenticated;

-- ── Grants da seção ────────────────────────────────────────────────────────
-- Os três helpers das policies: as ÚNICAS funções de `private` com EXECUTE
-- para authenticated (e service_role).
revoke all on function private.pt_current_role(), private.pt_is_internal(), private.pt_is_super_admin()
  from public, anon;
grant execute on function private.pt_current_role(), private.pt_is_internal(), private.pt_is_super_admin()
  to authenticated, service_role;


-- ════════════════════════════════════════════════════════════════════════════
-- 2. Ponto
-- ════════════════════════════════════════════════════════════════════════════

-- ── 2.1 Tabelas ────────────────────────────────────────────────────────────
-- work_date é o dia de Brasília em que a jornada COMEÇOU: a jornada que
-- atravessa a meia-noite conta inteira no dia de início. America/Sao_Paulo
-- está sem horário de verão desde 2019.
--
-- Integridade que não depende das RPCs:
--   * time_shifts_no_overlap: duas jornadas não anuladas da mesma pessoa não
--     se cruzam. Jornada aberta é a faixa [início, ∞), então ela também barra
--     jornada manual posterior ao seu início.
--   * time_shifts_one_open_per_user: no máximo uma jornada aberta por pessoa.
--     É a última barreira contra duas entradas simultâneas.
--   * revisão só em jornada encerrada, e reviewed ⇔ reviewed_at/by.
create table if not exists public.time_shifts (
  id                uuid        primary key default gen_random_uuid(),
  user_id           uuid        not null references public.profiles(id) on delete restrict,
  started_at        timestamptz not null,
  ended_at          timestamptz,
  work_date         date        generated always as ((started_at at time zone 'America/Sao_Paulo')::date) stored,
  source            text        not null default 'clock' check (source in ('clock', 'manual')),
  note              text        check (note is null or char_length(note) <= 500),
  review_status     text        not null default 'none' check (review_status in ('none', 'pending', 'reviewed')),
  reviewed_at       timestamptz,
  reviewed_by       uuid        references public.profiles(id) on delete restrict,
  last_corrected_at timestamptz,
  last_corrected_by uuid        references public.profiles(id) on delete restrict,
  voided_at         timestamptz,
  voided_by         uuid        references public.profiles(id) on delete restrict,
  void_reason       text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint time_shifts_range_chk
    check (ended_at is null or ended_at > started_at),
  constraint time_shifts_void_chk
    check ((voided_at is null) = (voided_by is null) and (voided_at is null) = (void_reason is null)),
  constraint time_shifts_review_chk
    check ((review_status = 'reviewed') = (reviewed_at is not null and reviewed_by is not null)),
  constraint time_shifts_reviewed_closed_chk
    check (review_status <> 'reviewed' or ended_at is not null),
  constraint time_shifts_no_overlap
    exclude using gist (user_id with =, tstzrange(started_at, ended_at, '[)') with &&)
    where (voided_at is null)
);

create unique index if not exists time_shifts_one_open_per_user
  on public.time_shifts (user_id)
  where ended_at is null and voided_at is null;
create index if not exists time_shifts_user_work_date_idx
  on public.time_shifts (user_id, work_date desc);
create index if not exists time_shifts_work_date_idx
  on public.time_shifts (work_date);
create index if not exists time_shifts_pending_review_idx
  on public.time_shifts (review_status)
  where review_status = 'pending';

-- user_id repetido (é o da jornada) para a policy não precisar de subconsulta.
-- '[)' faz intervalos que se tocam (12:00–13:00 e 13:00–13:30) serem válidos.
create table if not exists public.time_breaks (
  id         uuid        primary key default gen_random_uuid(),
  shift_id   uuid        not null references public.time_shifts(id) on delete cascade,
  user_id    uuid        not null references public.profiles(id) on delete restrict,
  started_at timestamptz not null,
  ended_at   timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint time_breaks_range_chk
    check (ended_at is null or ended_at > started_at),
  constraint time_breaks_no_overlap
    exclude using gist (shift_id with =, tstzrange(started_at, ended_at, '[)') with &&)
);

create unique index if not exists time_breaks_one_open_per_shift
  on public.time_breaks (shift_id)
  where ended_at is null;
create index if not exists time_breaks_shift_started_idx
  on public.time_breaks (shift_id, started_at);
create index if not exists time_breaks_user_started_idx
  on public.time_breaks (user_id, started_at);

-- Auditoria do ponto: batidas E correções, somente inclusão.
--   * seq dá a ordem confiável (várias linhas da mesma chamada têm o mesmo
--     created_at: as RPCs gravam o instante da ação, v_now).
--   * before/after são o JSON da jornada (§3.4) antes e depois.
--   * request_id torna a batida idempotente: o app gera um id por intenção e
--     reenvia o MESMO id depois de erro de rede. Único por autor.
create table if not exists public.time_audit_events (
  id              uuid        primary key default gen_random_uuid(),
  seq             bigint      generated always as identity,
  shift_id        uuid        references public.time_shifts(id) on delete restrict,
  subject_user_id uuid        not null references public.profiles(id) on delete restrict,
  actor_id        uuid        not null references public.profiles(id) on delete restrict,
  action          text        not null check (action in ('clock_in', 'break_start', 'break_end', 'clock_out',
                                                         'correct', 'create_manual', 'void', 'review')),
  reason          text        check (reason is null or char_length(reason) <= 1000),
  before          jsonb,
  after           jsonb,
  request_id      uuid,
  created_at      timestamptz not null default clock_timestamp(),
  constraint time_audit_reason_chk
    check (action not in ('correct', 'create_manual', 'void') or char_length(btrim(coalesce(reason, ''))) >= 10)
);

create unique index if not exists time_audit_events_request_uniq
  on public.time_audit_events (actor_id, request_id)
  where request_id is not null;
create unique index if not exists time_audit_events_seq_uniq
  on public.time_audit_events (seq);
create index if not exists time_audit_events_subject_created_idx
  on public.time_audit_events (subject_user_id, created_at desc);
create index if not exists time_audit_events_shift_seq_idx
  on public.time_audit_events (shift_id, seq);

-- ── 2.2 Triggers de integridade ────────────────────────────────────────────
-- Defesa além da validação das RPCs: mesmo o dono da tabela (SQL Editor,
-- service_role) não grava intervalo fora da jornada. São IMEDIATOS (não
-- deferidos), por isso as RPCs seguem uma ordem de escrita fixa:
--   substituir intervalos = apagar intervalos → atualizar jornada → inserir;
--   encerrar             = fechar o intervalo → fechar a jornada.

drop trigger if exists time_shifts_set_updated_at on public.time_shifts;
create trigger time_shifts_set_updated_at
  before update on public.time_shifts
  for each row execute function private.pt_set_updated_at();

drop trigger if exists time_breaks_set_updated_at on public.time_breaks;
create trigger time_breaks_set_updated_at
  before update on public.time_breaks
  for each row execute function private.pt_set_updated_at();

-- DEFINER: lê a linha ATUAL da jornada sem depender de RLS de quem escreve.
-- Não olha current_user. Jornada inexistente também é "fora da jornada".
create or replace function private.time_breaks_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shift record;
begin
  select s.user_id, s.started_at, s.ended_at
    into v_shift
    from public.time_shifts s
   where s.id = new.shift_id;

  if not found
     or new.user_id is distinct from v_shift.user_id
     or new.started_at < v_shift.started_at then
    raise exception 'break_outside_shift'
      using errcode = '23514',
            detail  = 'Os intervalos precisam ficar dentro da jornada.';
  end if;

  if v_shift.ended_at is not null then
    if new.ended_at is null then
      raise exception 'break_open_on_closed_shift'
        using errcode = '23514',
              detail  = 'Informe o fim de todos os intervalos de uma jornada encerrada.';
    end if;
    if new.ended_at > v_shift.ended_at then
      raise exception 'break_outside_shift'
        using errcode = '23514',
              detail  = 'Os intervalos precisam ficar dentro da jornada.';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.time_breaks_guard() from public, anon, authenticated;

drop trigger if exists time_breaks_guard on public.time_breaks;
create trigger time_breaks_guard
  before insert or update on public.time_breaks
  for each row execute function private.time_breaks_guard();

-- O outro lado da mesma regra: mudar a jornada (início, fim, dono) revalida
-- todos os intervalos ATUAIS dela.
create or replace function private.time_shifts_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
      from public.time_breaks b
     where b.shift_id = new.id
       and (b.user_id is distinct from new.user_id or b.started_at < new.started_at)
  ) then
    raise exception 'break_outside_shift'
      using errcode = '23514',
            detail  = 'Os intervalos precisam ficar dentro da jornada.';
  end if;

  if new.ended_at is not null then
    if exists (select 1 from public.time_breaks b where b.shift_id = new.id and b.ended_at is null) then
      raise exception 'break_open_on_closed_shift'
        using errcode = '23514',
              detail  = 'Informe o fim de todos os intervalos de uma jornada encerrada.';
    end if;
    if exists (select 1 from public.time_breaks b where b.shift_id = new.id and b.ended_at > new.ended_at) then
      raise exception 'break_outside_shift'
        using errcode = '23514',
              detail  = 'Os intervalos precisam ficar dentro da jornada.';
    end if;
  end if;

  return null;
end;
$$;

revoke all on function private.time_shifts_guard() from public, anon, authenticated;

drop trigger if exists time_shifts_guard on public.time_shifts;
create trigger time_shifts_guard
  after update on public.time_shifts
  for each row execute function private.time_shifts_guard();

drop trigger if exists time_audit_events_immutable on public.time_audit_events;
create trigger time_audit_events_immutable
  before update or delete on public.time_audit_events
  for each row execute function private.pt_audit_immutable();

-- ── 2.3 RLS ────────────────────────────────────────────────────────────────
-- Leitura: o próprio ponto, ou tudo para o super_admin. manager/partner NÃO
-- veem o ponto alheio nesta fase. client e "desconhecido": 0 linhas.
-- Escrita: nenhuma policy — authenticated nem tem grant de escrita; tudo passa
-- pelas RPCs da seção 2.5.
-- Helpers dentro de (select …) para o planner avaliar uma vez por consulta
-- (advisor auth_rls_initplan).
alter table public.time_shifts       enable row level security;
alter table public.time_breaks       enable row level security;
alter table public.time_audit_events enable row level security;

drop policy if exists time_shifts_select on public.time_shifts;
create policy time_shifts_select on public.time_shifts
  for select to authenticated
  using (
    (select private.pt_is_internal())
    and (time_shifts.user_id = (select auth.uid()) or (select private.pt_is_super_admin()))
  );

drop policy if exists time_breaks_select on public.time_breaks;
create policy time_breaks_select on public.time_breaks
  for select to authenticated
  using (
    (select private.pt_is_internal())
    and (time_breaks.user_id = (select auth.uid()) or (select private.pt_is_super_admin()))
  );

drop policy if exists time_audit_events_select on public.time_audit_events;
create policy time_audit_events_select on public.time_audit_events
  for select to authenticated
  using (
    (select private.pt_is_internal())
    and (time_audit_events.subject_user_id = (select auth.uid()) or (select private.pt_is_super_admin()))
  );

-- ── 2.4 Totais ─────────────────────────────────────────────────────────────
-- security_invoker: a view lê as tabelas com os privilégios e a RLS de quem
-- consulta (sem isso, rodaria como o dono e mostraria o ponto de todos).
-- Abertos medidos até now(). Cada intervalo é recortado em zero para nunca
-- dar segundos negativos (consulta numa transação que começou antes da batida).
create or replace view public.time_shift_totals
with (security_invoker = true) as
select
  s.id                                                        as shift_id,
  s.user_id                                                   as user_id,
  s.work_date                                                 as work_date,
  s.started_at                                                as started_at,
  s.ended_at                                                  as ended_at,
  (s.ended_at is null)                                        as is_open,
  coalesce(bt.has_open_break, false)                          as on_break,
  ((coalesce(s.ended_at, now()) at time zone 'America/Sao_Paulo')::date > s.work_date)
                                                              as crosses_midnight,
  coalesce(bt.break_seconds, 0)::bigint                       as break_seconds,
  greatest(
    0::bigint,
    floor(extract(epoch from (coalesce(s.ended_at, now()) - s.started_at)))::bigint
      - coalesce(bt.break_seconds, 0)::bigint
  )                                                           as worked_seconds,
  s.review_status                                             as review_status,
  (s.voided_at is not null)                                   as is_voided
from public.time_shifts s
left join lateral (
  select
    floor(extract(epoch from sum(greatest(coalesce(b.ended_at, now()) - b.started_at, interval '0'))))::bigint
                                as break_seconds,
    bool_or(b.ended_at is null) as has_open_break
  from public.time_breaks b
  where b.shift_id = s.id
) bt on true;

-- ── 2.5 Funções internas das RPCs ──────────────────────────────────────────
-- Todas em `private`, sem EXECUTE para ninguém: só as RPCs DEFINER (que rodam
-- como o dono) as chamam.

-- Um único lugar para código → SQLSTATE + frase pt-BR (contrato §3.7). O app
-- traduz pelo `message`; o `detail` ajuda quem lê o log.
create or replace function private.time_raise(p_code text)
returns void
language plpgsql
set search_path = ''
as $$
declare
  v_state  text := 'P0001';
  v_detail text;
begin
  v_detail := case p_code
    when 'not_authenticated'          then 'Sua sessão expirou. Entre novamente.'
    when 'not_allowed'                then 'Você não tem permissão para esta ação.'
    when 'shift_already_open'         then 'Você já tem uma jornada aberta.'
    when 'no_open_shift'              then 'Não há jornada aberta. Registre a entrada primeiro.'
    when 'break_already_open'         then 'Você já está em intervalo.'
    when 'no_open_break'              then 'Não há intervalo aberto.'
    when 'break_open'                 then 'Encerre o intervalo antes de registrar a saída.'
    when 'invalid_reason'             then 'Escreva uma justificativa com pelo menos 10 caracteres.'
    when 'invalid_range'              then 'O horário de saída precisa ser depois da entrada.'
    when 'future_timestamp'           then 'Não é possível registrar horários no futuro.'
    when 'break_outside_shift'        then 'Os intervalos precisam ficar dentro da jornada.'
    when 'breaks_overlap'             then 'Os intervalos não podem se sobrepor.'
    when 'break_open_on_closed_shift' then 'Informe o fim de todos os intervalos de uma jornada encerrada.'
    when 'invalid_breaks'             then 'Lista de intervalos inválida.'
    when 'shift_overlap'              then 'Esse horário se sobrepõe a outra jornada sua.'
    when 'shift_not_found'            then 'Jornada não encontrada.'
    when 'shift_locked'               then 'Esta jornada já foi revisada pelo administrador. Peça a correção a ele.'
    when 'shift_voided'               then 'Esta jornada foi anulada.'
    when 'shift_open'                 then 'Não é possível revisar uma jornada em aberto.'
    when 'shift_changed'              then 'Esta jornada mudou depois que você abriu a tela. Atualize e revise de novo.'
    when 'cannot_reopen'              then 'Uma jornada encerrada não pode ser reaberta.'
    when 'request_id_conflict'        then 'Esta ação já foi enviada com outro pedido. Atualize a tela.'
    -- Fora da tabela do contrato (entrada que ele não cobre; ver relatório).
    -- Os SQLSTATEs escolhidos caem no genérico "Dados inválidos. Revise os
    -- campos." do app: 23514 (observação longa demais, mesma família da
    -- check constraint da coluna) e 22P02 (p_shifts malformado, o mesmo que o
    -- Postgres levanta para texto que não é uuid/timestamptz).
    when 'invalid_note'               then 'A observação pode ter no máximo 500 caracteres.'
    when 'invalid_shifts'             then 'Lista de jornadas inválida.'
    else 'Algo deu errado. Tente novamente.'
  end;

  if p_code in ('not_authenticated', 'not_allowed') then
    v_state := '42501';
  elsif p_code = 'invalid_note' then
    v_state := '23514';
  elsif p_code = 'invalid_shifts' then
    v_state := '22P02';
  end if;

  raise exception using message = p_code, errcode = v_state, detail = v_detail;
end;
$$;

revoke all on function private.time_raise(text) from public, anon, authenticated;

-- Violação de constraint dentro de uma RPC vira código de negócio pelo NOME
-- da constraint/índice (não pelo texto da mensagem, que muda entre versões).
-- Os triggers de integridade não têm nome de constraint: mantêm o próprio código.
create or replace function private.time_constraint_code(p_constraint text, p_message text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_constraint
    when 'time_shifts_no_overlap'         then 'shift_overlap'
    when 'time_shifts_one_open_per_user'  then 'shift_already_open'
    when 'time_breaks_no_overlap'         then 'breaks_overlap'
    when 'time_breaks_one_open_per_shift' then 'break_already_open'
    when 'time_audit_events_request_uniq' then 'request_id_conflict'
    else case
      when coalesce(p_constraint, '') = ''
       and p_message in ('break_outside_shift', 'break_open_on_closed_shift') then p_message
      else 'invalid_breaks'
    end
  end
$$;

revoke all on function private.time_constraint_code(text, text) from public, anon, authenticated;

-- JSON da jornada (contrato §3.4), igual ao embedding
-- time_shifts?select=*,time_breaks(*): todas as colunas + intervalos por início.
-- INVOKER: só é chamada de dentro das RPCs DEFINER, então roda como o dono.
create or replace function private.time_shift_json(p_shift_id uuid)
returns jsonb
language sql
set search_path = ''
as $$
  select to_jsonb(s) || jsonb_build_object(
           'time_breaks',
           coalesce(
             (select jsonb_agg(to_jsonb(b) order by b.started_at, b.id)
                from public.time_breaks b
               where b.shift_id = s.id),
             '[]'::jsonb))
    from public.time_shifts s
   where s.id = p_shift_id
$$;

revoke all on function private.time_shift_json(uuid) from public, anon, authenticated;

create or replace function private.time_audit_insert(
  p_shift_id   uuid,
  p_subject    uuid,
  p_actor      uuid,
  p_action     text,
  p_reason     text,
  p_before     jsonb,
  p_after      jsonb,
  p_request_id uuid,
  p_now        timestamptz)
returns void
language sql
set search_path = ''
as $$
  insert into public.time_audit_events
    (shift_id, subject_user_id, actor_id, action, reason, before, after, request_id, created_at)
  values
    (p_shift_id, p_subject, p_actor, p_action, p_reason, p_before, p_after, p_request_id, p_now)
$$;

revoke all on function private.time_audit_insert(uuid, uuid, uuid, text, text, jsonb, jsonb, uuid, timestamptz)
  from public, anon, authenticated;

-- Justificativa obrigatória: 10..1000 caracteres depois do trim. Devolve o
-- texto já aparado, que é o que vai para a auditoria.
create or replace function private.time_check_reason(p_reason text)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_reason text := coalesce(private.pt_trim(p_reason), '');
begin
  if char_length(v_reason) < 10 or char_length(v_reason) > 1000 then
    perform private.time_raise('invalid_reason');
  end if;
  return v_reason;
end;
$$;

revoke all on function private.time_check_reason(text) from public, anon, authenticated;

-- Validação de correção e de jornada manual, na ORDEM do contrato (o app
-- espelha a mesma ordem em validateShiftDraft):
--   justificativa → reabertura/fim obrigatório → faixa da jornada → formato
--   dos intervalos → futuro (tolerância zero) → faixa de cada intervalo →
--   intervalos dentro da jornada → ordem/sobreposição → intervalo aberto em
--   jornada encerrada.
-- "Ordenados e sem sobreposição" é checado na ordem em que a lista chega:
-- cada intervalo começa no fim do anterior ou depois. Um intervalo aberto que
-- não é o último se sobrepõe ao seguinte, o que também cobre "jornada aberta
-- ⇒ no máximo um aberto e ele é o último". Encostar é válido ('[)').
create or replace function private.time_validate_draft(
  p_started_at timestamptz,
  p_ended_at   timestamptz,
  p_breaks     jsonb,
  p_reason     text,
  p_now        timestamptz,
  p_shift_open boolean,
  p_is_new     boolean)
returns text
language plpgsql
set search_path = ''
as $$
declare
  v_reason text;
  v_elem   jsonb;
  v_start  timestamptz;
  v_end    timestamptz;
  v_starts timestamptz[] := '{}';
  v_ends   timestamptz[] := '{}';
  v_n      integer;
  v_i      integer;
begin
  v_reason := private.time_check_reason(p_reason);

  if p_ended_at is null then
    if p_is_new then
      perform private.time_raise('invalid_range');
    elsif not p_shift_open then
      perform private.time_raise('cannot_reopen');
    end if;
  end if;

  if p_started_at is null
     or not isfinite(p_started_at)
     or (p_ended_at is not null and (not isfinite(p_ended_at) or p_ended_at <= p_started_at)) then
    perform private.time_raise('invalid_range');
  end if;

  -- Formato: array de objetos {"started_at": texto, "ended_at": texto|null}.
  -- Chaves extras são ignoradas; ended_at ausente vale null.
  if p_breaks is null or jsonb_typeof(p_breaks) <> 'array' then
    perform private.time_raise('invalid_breaks');
  end if;

  for v_elem in
    select x.e from jsonb_array_elements(p_breaks) with ordinality as x(e, n) order by x.n
  loop
    if jsonb_typeof(v_elem) <> 'object'
       or jsonb_typeof(v_elem -> 'started_at') is distinct from 'string'
       or coalesce(jsonb_typeof(v_elem -> 'ended_at'), 'null') not in ('null', 'string') then
      perform private.time_raise('invalid_breaks');
    end if;

    begin
      v_start := (v_elem ->> 'started_at')::timestamptz;
      v_end   := (v_elem ->> 'ended_at')::timestamptz;
    exception when others then
      perform private.time_raise('invalid_breaks');
    end;

    if not isfinite(v_start) or (v_end is not null and not isfinite(v_end)) then
      perform private.time_raise('invalid_breaks');
    end if;

    v_starts := array_append(v_starts, v_start);
    v_ends   := array_append(v_ends, v_end);
  end loop;

  v_n := coalesce(array_length(v_starts, 1), 0);

  if p_started_at > p_now or p_ended_at > p_now then
    perform private.time_raise('future_timestamp');
  end if;
  for v_i in 1 .. v_n loop
    if v_starts[v_i] > p_now or v_ends[v_i] > p_now then
      perform private.time_raise('future_timestamp');
    end if;
  end loop;

  for v_i in 1 .. v_n loop
    if v_ends[v_i] is not null and v_ends[v_i] <= v_starts[v_i] then
      perform private.time_raise('invalid_range');
    end if;
  end loop;

  -- Dentro de [início, fim) — ou [início, ∞) com a jornada aberta. Um intervalo
  -- aberto numa jornada encerrada só é "fora" se começar no fim ou depois; se
  -- começou dentro, o erro certo é o de baixo (falta informar o fim).
  for v_i in 1 .. v_n loop
    if v_starts[v_i] < p_started_at
       or (p_ended_at is not null and (v_starts[v_i] >= p_ended_at or v_ends[v_i] > p_ended_at)) then
      perform private.time_raise('break_outside_shift');
    end if;
  end loop;

  for v_i in 2 .. v_n loop
    if v_ends[v_i - 1] is null or v_starts[v_i] < v_ends[v_i - 1] then
      perform private.time_raise('breaks_overlap');
    end if;
  end loop;

  if p_ended_at is not null then
    for v_i in 1 .. v_n loop
      if v_ends[v_i] is null then
        perform private.time_raise('break_open_on_closed_shift');
      end if;
    end loop;
  end if;

  return v_reason;
end;
$$;

revoke all on function private.time_validate_draft(timestamptz, timestamptz, jsonb, text, timestamptz, boolean, boolean)
  from public, anon, authenticated;

-- ── 2.6 RPCs ───────────────────────────────────────────────────────────────
-- Prólogo comum (contrato §3.3), nesta ordem:
--   1. auth.uid() null → not_authenticated; 2. não interno → not_allowed;
--   3. RPC que recebe jornada: leitura SIMPLES do dono; inexistente OU de outra
--      pessoa sem ser super_admin → shift_not_found. Vem antes de qualquer
--      outra checagem (anulada, revisada, aberta) para não virar oráculo do
--      ponto alheio. Nunca FOR UPDATE antes do advisory lock;
--   4. advisory lock por DONO do ponto: duas batidas simultâneas da mesma
--      pessoa viram uma fila, então não nascem duas jornadas nem dois
--      intervalos (os índices únicos parciais são a última barreira);
--   5. depois do lock: v_now := clock_timestamp() (now() é o início da
--      transação, que pode ser ANTERIOR à batida que estávamos esperando) e
--      releitura FOR UPDATE. Em READ COMMITTED cada comando depois do lock vê
--      o que a chamada anterior gravou; TODAS as checagens e o `before` da
--      auditoria usam essa releitura;
--   6. idempotência por request_id (antes das checagens de estado: a repetição
--      de uma batida que deu certo devolve a mesma jornada em vez de
--      shift_already_open). Exatamente UMA linha de auditoria por chamada leva
--      o request_id — a da ação da RPC; eventos colaterais gravam null;
--   7. violação de constraint num sub-bloco, traduzida pelo nome.
-- Toda RPC que devolve jornada devolve o JSON de §3.4 + "server_now", que o
-- app usa para corrigir o relógio do aparelho.

create or replace function public.time_my_status()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_now   timestamptz;
  v_shift uuid;
begin
  if v_uid is null then
    perform private.time_raise('not_authenticated');
  end if;
  if not private.pt_is_internal() then
    perform private.time_raise('not_allowed');
  end if;

  v_now := clock_timestamp();

  select s.id
    into v_shift
    from public.time_shifts s
   where s.user_id = v_uid
     and s.ended_at is null
     and s.voided_at is null;

  return jsonb_build_object(
    'open_shift', case when v_shift is null then null else private.time_shift_json(v_shift) end,
    'server_now', v_now);
end;
$$;

create or replace function public.time_clock_in(
  p_request_id uuid default null,
  p_note       text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := auth.uid();
  v_note        text := nullif(private.pt_trim(p_note), '');
  v_now         timestamptz;
  v_open        public.time_shifts%rowtype;
  v_prev_action text;
  v_prev_shift  uuid;
  v_shift_id    uuid;
  v_constraint  text;
  v_message     text;
begin
  if v_uid is null then
    perform private.time_raise('not_authenticated');
  end if;
  if not private.pt_is_internal() then
    perform private.time_raise('not_allowed');
  end if;
  if char_length(v_note) > 500 then
    perform private.time_raise('invalid_note');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('ponto.time:' || v_uid::text, 0));
  v_now := clock_timestamp();

  select s.*
    into v_open
    from public.time_shifts s
   where s.user_id = v_uid
     and s.ended_at is null
     and s.voided_at is null
     for update;

  if p_request_id is not null then
    select e.action, e.shift_id
      into v_prev_action, v_prev_shift
      from public.time_audit_events e
     where e.actor_id = v_uid
       and e.request_id = p_request_id;
    if found then
      if v_prev_action <> 'clock_in' then
        perform private.time_raise('request_id_conflict');
      end if;
      return private.time_shift_json(v_prev_shift) || jsonb_build_object('server_now', v_now);
    end if;
  end if;

  if v_open.id is not null then
    perform private.time_raise('shift_already_open');
  end if;

  begin
    insert into public.time_shifts (user_id, started_at, source, note)
    values (v_uid, v_now, 'clock', v_note)
    returning id into v_shift_id;

    perform private.time_audit_insert(
      v_shift_id, v_uid, v_uid, 'clock_in', null,
      null, private.time_shift_json(v_shift_id), p_request_id, v_now);
  exception when integrity_constraint_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform private.time_raise(private.time_constraint_code(v_constraint, v_message));
  end;

  return private.time_shift_json(v_shift_id) || jsonb_build_object('server_now', v_now);
end;
$$;

create or replace function public.time_start_break(p_request_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := auth.uid();
  v_now         timestamptz;
  v_open        public.time_shifts%rowtype;
  v_break_id    uuid;
  v_prev_action text;
  v_prev_shift  uuid;
  v_before      jsonb;
  v_constraint  text;
  v_message     text;
begin
  if v_uid is null then
    perform private.time_raise('not_authenticated');
  end if;
  if not private.pt_is_internal() then
    perform private.time_raise('not_allowed');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('ponto.time:' || v_uid::text, 0));
  v_now := clock_timestamp();

  select s.*
    into v_open
    from public.time_shifts s
   where s.user_id = v_uid
     and s.ended_at is null
     and s.voided_at is null
     for update;

  if p_request_id is not null then
    select e.action, e.shift_id
      into v_prev_action, v_prev_shift
      from public.time_audit_events e
     where e.actor_id = v_uid
       and e.request_id = p_request_id;
    if found then
      if v_prev_action <> 'break_start' then
        perform private.time_raise('request_id_conflict');
      end if;
      return private.time_shift_json(v_prev_shift) || jsonb_build_object('server_now', v_now);
    end if;
  end if;

  if v_open.id is null then
    perform private.time_raise('no_open_shift');
  end if;

  select b.id
    into v_break_id
    from public.time_breaks b
   where b.shift_id = v_open.id
     and b.ended_at is null
     for update;
  if found then
    perform private.time_raise('break_already_open');
  end if;

  v_before := private.time_shift_json(v_open.id);

  begin
    insert into public.time_breaks (shift_id, user_id, started_at)
    values (v_open.id, v_open.user_id, v_now);

    perform private.time_audit_insert(
      v_open.id, v_uid, v_uid, 'break_start', null,
      v_before, private.time_shift_json(v_open.id), p_request_id, v_now);
  exception when integrity_constraint_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform private.time_raise(private.time_constraint_code(v_constraint, v_message));
  end;

  return private.time_shift_json(v_open.id) || jsonb_build_object('server_now', v_now);
end;
$$;

create or replace function public.time_end_break(p_request_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := auth.uid();
  v_now         timestamptz;
  v_open        public.time_shifts%rowtype;
  v_break_id    uuid;
  v_prev_action text;
  v_prev_shift  uuid;
  v_before      jsonb;
  v_constraint  text;
  v_message     text;
begin
  if v_uid is null then
    perform private.time_raise('not_authenticated');
  end if;
  if not private.pt_is_internal() then
    perform private.time_raise('not_allowed');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('ponto.time:' || v_uid::text, 0));
  v_now := clock_timestamp();

  select s.*
    into v_open
    from public.time_shifts s
   where s.user_id = v_uid
     and s.ended_at is null
     and s.voided_at is null
     for update;

  if p_request_id is not null then
    select e.action, e.shift_id
      into v_prev_action, v_prev_shift
      from public.time_audit_events e
     where e.actor_id = v_uid
       and e.request_id = p_request_id;
    if found then
      if v_prev_action <> 'break_end' then
        perform private.time_raise('request_id_conflict');
      end if;
      return private.time_shift_json(v_prev_shift) || jsonb_build_object('server_now', v_now);
    end if;
  end if;

  if v_open.id is null then
    perform private.time_raise('no_open_shift');
  end if;

  select b.id
    into v_break_id
    from public.time_breaks b
   where b.shift_id = v_open.id
     and b.ended_at is null
     for update;
  if not found then
    perform private.time_raise('no_open_break');
  end if;

  v_before := private.time_shift_json(v_open.id);

  begin
    update public.time_breaks b
       set ended_at = v_now
     where b.id = v_break_id;

    perform private.time_audit_insert(
      v_open.id, v_uid, v_uid, 'break_end', null,
      v_before, private.time_shift_json(v_open.id), p_request_id, v_now);
  exception when integrity_constraint_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform private.time_raise(private.time_constraint_code(v_constraint, v_message));
  end;

  return private.time_shift_json(v_open.id) || jsonb_build_object('server_now', v_now);
end;
$$;

-- Saída com intervalo aberto: só com p_close_open_break = true (o app pede
-- confirmação). Aí o intervalo fecha em v_now ANTES da jornada (ordem dos
-- triggers imediatos) e ganha a própria linha break_end, com request_id null:
-- o request_id fica só na linha clock_out, a ação desta RPC.
-- p_note, quando vem, substitui a observação da jornada.
create or replace function public.time_clock_out(
  p_request_id       uuid    default null,
  p_close_open_break boolean default false,
  p_note             text    default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := auth.uid();
  v_note        text := nullif(private.pt_trim(p_note), '');
  v_now         timestamptz;
  v_open        public.time_shifts%rowtype;
  v_break_id    uuid;
  v_prev_action text;
  v_prev_shift  uuid;
  v_before      jsonb;
  v_constraint  text;
  v_message     text;
begin
  if v_uid is null then
    perform private.time_raise('not_authenticated');
  end if;
  if not private.pt_is_internal() then
    perform private.time_raise('not_allowed');
  end if;
  if char_length(v_note) > 500 then
    perform private.time_raise('invalid_note');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('ponto.time:' || v_uid::text, 0));
  v_now := clock_timestamp();

  select s.*
    into v_open
    from public.time_shifts s
   where s.user_id = v_uid
     and s.ended_at is null
     and s.voided_at is null
     for update;

  if p_request_id is not null then
    select e.action, e.shift_id
      into v_prev_action, v_prev_shift
      from public.time_audit_events e
     where e.actor_id = v_uid
       and e.request_id = p_request_id;
    if found then
      if v_prev_action <> 'clock_out' then
        perform private.time_raise('request_id_conflict');
      end if;
      return private.time_shift_json(v_prev_shift) || jsonb_build_object('server_now', v_now);
    end if;
  end if;

  if v_open.id is null then
    perform private.time_raise('no_open_shift');
  end if;

  select b.id
    into v_break_id
    from public.time_breaks b
   where b.shift_id = v_open.id
     and b.ended_at is null
     for update;
  if found and not coalesce(p_close_open_break, false) then
    perform private.time_raise('break_open');
  end if;

  v_before := private.time_shift_json(v_open.id);

  begin
    if v_break_id is not null then
      update public.time_breaks b
         set ended_at = v_now
       where b.id = v_break_id;

      perform private.time_audit_insert(
        v_open.id, v_uid, v_uid, 'break_end', null,
        v_before, private.time_shift_json(v_open.id), null, v_now);

      v_before := private.time_shift_json(v_open.id);
    end if;

    update public.time_shifts s
       set ended_at = v_now,
           note     = coalesce(v_note, s.note)
     where s.id = v_open.id;

    perform private.time_audit_insert(
      v_open.id, v_uid, v_uid, 'clock_out', null,
      v_before, private.time_shift_json(v_open.id), p_request_id, v_now);
  exception when integrity_constraint_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform private.time_raise(private.time_constraint_code(v_constraint, v_message));
  end;

  return private.time_shift_json(v_open.id) || jsonb_build_object('server_now', v_now);
end;
$$;

-- Correção: substitui início, fim e a lista INTEIRA de intervalos.
-- Dono corrige direto (sem aprovação prévia) enquanto a jornada não foi
-- revisada; depois disso só o super_admin. review_status: super_admin
-- corrigindo e a jornada resultante encerrada → reviewed; qualquer outro caso
-- → pending (inclusive super_admin corrigindo jornada ainda aberta, que não
-- pode ficar revisada).
-- A repetição do mesmo request_id só devolve a jornada se for a MESMA ação na
-- MESMA jornada; request_id reaproveitado em outra jornada é conflito.
create or replace function public.time_correct_shift(
  p_shift_id   uuid,
  p_started_at timestamptz,
  p_ended_at   timestamptz,
  p_breaks     jsonb,
  p_reason     text,
  p_request_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := auth.uid();
  v_is_admin    boolean;
  v_subject     uuid;
  v_now         timestamptz;
  v_shift       public.time_shifts%rowtype;
  v_prev_action text;
  v_prev_shift  uuid;
  v_reason      text;
  v_status      text;
  v_rev_at      timestamptz;
  v_rev_by      uuid;
  v_before      jsonb;
  v_constraint  text;
  v_message     text;
begin
  if v_uid is null then
    perform private.time_raise('not_authenticated');
  end if;
  if not private.pt_is_internal() then
    perform private.time_raise('not_allowed');
  end if;
  v_is_admin := private.pt_is_super_admin();

  select s.user_id into v_subject from public.time_shifts s where s.id = p_shift_id;
  if not found or (v_subject <> v_uid and not v_is_admin) then
    perform private.time_raise('shift_not_found');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('ponto.time:' || v_subject::text, 0));
  v_now := clock_timestamp();

  select s.* into v_shift from public.time_shifts s where s.id = p_shift_id for update;
  if not found or v_shift.user_id <> v_subject then
    perform private.time_raise('shift_not_found');
  end if;

  if p_request_id is not null then
    select e.action, e.shift_id
      into v_prev_action, v_prev_shift
      from public.time_audit_events e
     where e.actor_id = v_uid
       and e.request_id = p_request_id;
    if found then
      if v_prev_action <> 'correct' or v_prev_shift is distinct from p_shift_id then
        perform private.time_raise('request_id_conflict');
      end if;
      return private.time_shift_json(v_prev_shift) || jsonb_build_object('server_now', v_now);
    end if;
  end if;

  if not v_is_admin and v_shift.review_status = 'reviewed' then
    perform private.time_raise('shift_locked');
  end if;
  if v_shift.voided_at is not null then
    perform private.time_raise('shift_voided');
  end if;

  v_reason := private.time_validate_draft(
    p_started_at, p_ended_at, p_breaks, p_reason, v_now, v_shift.ended_at is null, false);

  if v_is_admin and p_ended_at is not null then
    v_status := 'reviewed';
    v_rev_at := v_now;
    v_rev_by := v_uid;
  else
    v_status := 'pending';
  end if;

  v_before := private.time_shift_json(v_shift.id);

  begin
    delete from public.time_breaks b where b.shift_id = v_shift.id;

    update public.time_shifts s
       set started_at        = p_started_at,
           ended_at          = p_ended_at,
           last_corrected_at = v_now,
           last_corrected_by = v_uid,
           review_status     = v_status,
           reviewed_at       = v_rev_at,
           reviewed_by       = v_rev_by
     where s.id = v_shift.id;

    insert into public.time_breaks (shift_id, user_id, started_at, ended_at)
    select v_shift.id, v_shift.user_id,
           (x.e ->> 'started_at')::timestamptz,
           (x.e ->> 'ended_at')::timestamptz
      from jsonb_array_elements(p_breaks) with ordinality as x(e, n)
     order by x.n;

    perform private.time_audit_insert(
      v_shift.id, v_shift.user_id, v_uid, 'correct', v_reason,
      v_before, private.time_shift_json(v_shift.id), p_request_id, v_now);
  exception when integrity_constraint_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform private.time_raise(private.time_constraint_code(v_constraint, v_message));
  end;

  return private.time_shift_json(v_shift.id) || jsonb_build_object('server_now', v_now);
end;
$$;

-- Dia esquecido. p_user_id null = o próprio chamador; outra pessoa só o
-- super_admin, e o alvo precisa ser interno. Mesmas validações da correção,
-- com fim obrigatório. Na repetição, o request_id só vale para o mesmo alvo.
create or replace function public.time_create_manual_shift(
  p_user_id    uuid,
  p_started_at timestamptz,
  p_ended_at   timestamptz,
  p_breaks     jsonb,
  p_reason     text,
  p_request_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := auth.uid();
  v_is_admin    boolean;
  v_target      uuid;
  v_now         timestamptz;
  v_prev_action text;
  v_prev_shift  uuid;
  v_reason      text;
  v_status      text;
  v_rev_at      timestamptz;
  v_rev_by      uuid;
  v_shift_id    uuid;
  v_constraint  text;
  v_message     text;
begin
  if v_uid is null then
    perform private.time_raise('not_authenticated');
  end if;
  if not private.pt_is_internal() then
    perform private.time_raise('not_allowed');
  end if;
  v_is_admin := private.pt_is_super_admin();

  v_target := coalesce(p_user_id, v_uid);
  if v_target <> v_uid and not v_is_admin then
    perform private.time_raise('not_allowed');
  end if;
  if not private.pt_is_internal_role((select p.role from public.profiles p where p.id = v_target)) then
    perform private.time_raise('not_allowed');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('ponto.time:' || v_target::text, 0));
  v_now := clock_timestamp();

  if p_request_id is not null then
    select e.action, e.shift_id
      into v_prev_action, v_prev_shift
      from public.time_audit_events e
     where e.actor_id = v_uid
       and e.request_id = p_request_id;
    if found then
      if v_prev_action <> 'create_manual'
         or (select s.user_id from public.time_shifts s where s.id = v_prev_shift) is distinct from v_target then
        perform private.time_raise('request_id_conflict');
      end if;
      return private.time_shift_json(v_prev_shift) || jsonb_build_object('server_now', v_now);
    end if;
  end if;

  v_reason := private.time_validate_draft(
    p_started_at, p_ended_at, p_breaks, p_reason, v_now, false, true);

  if v_is_admin then
    v_status := 'reviewed';
    v_rev_at := v_now;
    v_rev_by := v_uid;
  else
    v_status := 'pending';
  end if;

  begin
    insert into public.time_shifts
      (user_id, started_at, ended_at, source, review_status, reviewed_at, reviewed_by)
    values
      (v_target, p_started_at, p_ended_at, 'manual', v_status, v_rev_at, v_rev_by)
    returning id into v_shift_id;

    insert into public.time_breaks (shift_id, user_id, started_at, ended_at)
    select v_shift_id, v_target,
           (x.e ->> 'started_at')::timestamptz,
           (x.e ->> 'ended_at')::timestamptz
      from jsonb_array_elements(p_breaks) with ordinality as x(e, n)
     order by x.n;

    perform private.time_audit_insert(
      v_shift_id, v_target, v_uid, 'create_manual', v_reason,
      null, private.time_shift_json(v_shift_id), p_request_id, v_now);
  exception when integrity_constraint_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform private.time_raise(private.time_constraint_code(v_constraint, v_message));
  end;

  return private.time_shift_json(v_shift_id) || jsonb_build_object('server_now', v_now);
end;
$$;

-- Anular em vez de apagar: a jornada some dos totais, mas o registro e a
-- auditoria ficam. Jornada aberta é encerrada em v_now antes (intervalo
-- primeiro). Uma ÚNICA linha de auditoria (void), com o before da jornada
-- como estava. review_status pela mesma regra da correção (anulada fica
-- encerrada, então super_admin → reviewed).
create or replace function public.time_void_shift(
  p_shift_id   uuid,
  p_reason     text,
  p_request_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid         uuid := auth.uid();
  v_is_admin    boolean;
  v_subject     uuid;
  v_now         timestamptz;
  v_shift       public.time_shifts%rowtype;
  v_prev_action text;
  v_prev_shift  uuid;
  v_reason      text;
  v_status      text;
  v_rev_at      timestamptz;
  v_rev_by      uuid;
  v_before      jsonb;
  v_constraint  text;
  v_message     text;
begin
  if v_uid is null then
    perform private.time_raise('not_authenticated');
  end if;
  if not private.pt_is_internal() then
    perform private.time_raise('not_allowed');
  end if;
  v_is_admin := private.pt_is_super_admin();

  select s.user_id into v_subject from public.time_shifts s where s.id = p_shift_id;
  if not found or (v_subject <> v_uid and not v_is_admin) then
    perform private.time_raise('shift_not_found');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('ponto.time:' || v_subject::text, 0));
  v_now := clock_timestamp();

  select s.* into v_shift from public.time_shifts s where s.id = p_shift_id for update;
  if not found or v_shift.user_id <> v_subject then
    perform private.time_raise('shift_not_found');
  end if;

  if p_request_id is not null then
    select e.action, e.shift_id
      into v_prev_action, v_prev_shift
      from public.time_audit_events e
     where e.actor_id = v_uid
       and e.request_id = p_request_id;
    if found then
      if v_prev_action <> 'void' or v_prev_shift is distinct from p_shift_id then
        perform private.time_raise('request_id_conflict');
      end if;
      return private.time_shift_json(v_prev_shift) || jsonb_build_object('server_now', v_now);
    end if;
  end if;

  if not v_is_admin and v_shift.review_status = 'reviewed' then
    perform private.time_raise('shift_locked');
  end if;
  if v_shift.voided_at is not null then
    perform private.time_raise('shift_voided');
  end if;

  v_reason := private.time_check_reason(p_reason);

  if v_is_admin then
    v_status := 'reviewed';
    v_rev_at := v_now;
    v_rev_by := v_uid;
  else
    v_status := 'pending';
  end if;

  v_before := private.time_shift_json(v_shift.id);

  begin
    if v_shift.ended_at is null then
      update public.time_breaks b
         set ended_at = v_now
       where b.shift_id = v_shift.id
         and b.ended_at is null;
    end if;

    update public.time_shifts s
       set ended_at      = coalesce(s.ended_at, v_now),
           voided_at     = v_now,
           voided_by     = v_uid,
           void_reason   = v_reason,
           review_status = v_status,
           reviewed_at   = v_rev_at,
           reviewed_by   = v_rev_by
     where s.id = v_shift.id;

    perform private.time_audit_insert(
      v_shift.id, v_shift.user_id, v_uid, 'void', v_reason,
      v_before, private.time_shift_json(v_shift.id), p_request_id, v_now);
  exception when integrity_constraint_violation then
    get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
    perform private.time_raise(private.time_constraint_code(v_constraint, v_message));
  end;

  return private.time_shift_json(v_shift.id) || jsonb_build_object('server_now', v_now);
end;
$$;

-- Revisão em lote, só super_admin (checado antes de ler qualquer linha).
-- p_shifts = [{"id": uuid, "updated_at": timestamptz}]: o updated_at que a
-- tela mostrou funciona como trava otimista — se a jornada mudou depois,
-- shift_changed e nada é gravado. Locks por dono em ordem crescente de uuid
-- (ordem fixa = sem deadlock entre duas revisões). Tudo é validado antes da
-- primeira escrita; já revisada é ignorada (não conta, não audita).
create or replace function public.time_review_shifts(
  p_shifts jsonb,
  p_note   text default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_note       text;
  v_now        timestamptz;
  v_elem       jsonb;
  v_id         uuid;
  v_at         timestamptz;
  v_sent_ids   uuid[] := '{}';
  v_sent_at    timestamptz[] := '{}';
  v_ids        uuid[];
  v_to_review  uuid[] := '{}';
  v_subject    uuid;
  v_shift      public.time_shifts%rowtype;
  v_before     jsonb;
  v_i          integer;
  v_count      integer := 0;
  v_constraint text;
  v_message    text;
begin
  if v_uid is null then
    perform private.time_raise('not_authenticated');
  end if;
  if not private.pt_is_internal() then
    perform private.time_raise('not_allowed');
  end if;
  if not private.pt_is_super_admin() then
    perform private.time_raise('not_allowed');
  end if;

  if p_shifts is null or jsonb_typeof(p_shifts) = 'null' then
    return 0;
  end if;
  if jsonb_typeof(p_shifts) <> 'array' then
    perform private.time_raise('invalid_shifts');
  end if;
  if jsonb_array_length(p_shifts) = 0 then
    return 0;
  end if;

  v_note := nullif(private.pt_trim(p_note), '');
  if char_length(v_note) > 1000 then
    perform private.time_raise('invalid_reason');
  end if;

  for v_elem in select x.e from jsonb_array_elements(p_shifts) as x(e) loop
    if jsonb_typeof(v_elem) <> 'object'
       or jsonb_typeof(v_elem -> 'id') is distinct from 'string'
       or jsonb_typeof(v_elem -> 'updated_at') is distinct from 'string' then
      perform private.time_raise('invalid_shifts');
    end if;
    begin
      v_id := (v_elem ->> 'id')::uuid;
      v_at := (v_elem ->> 'updated_at')::timestamptz;
    exception when others then
      perform private.time_raise('invalid_shifts');
    end;
    v_sent_ids := array_append(v_sent_ids, v_id);
    v_sent_at  := array_append(v_sent_at, v_at);
  end loop;

  select array_agg(distinct u.id order by u.id) into v_ids from unnest(v_sent_ids) as u(id);

  for v_subject in
    select distinct s.user_id from public.time_shifts s where s.id = any (v_ids) order by s.user_id
  loop
    perform pg_advisory_xact_lock(hashtextextended('ponto.time:' || v_subject::text, 0));
  end loop;
  v_now := clock_timestamp();

  foreach v_id in array v_ids loop
    select s.* into v_shift from public.time_shifts s where s.id = v_id for update;
    if not found then
      perform private.time_raise('shift_not_found');
    end if;
    for v_i in 1 .. array_length(v_sent_ids, 1) loop
      if v_sent_ids[v_i] = v_id and v_sent_at[v_i] is distinct from v_shift.updated_at then
        perform private.time_raise('shift_changed');
      end if;
    end loop;
    if v_shift.ended_at is null then
      perform private.time_raise('shift_open');
    end if;
    if v_shift.review_status <> 'reviewed' then
      v_to_review := array_append(v_to_review, v_id);
    end if;
  end loop;

  foreach v_id in array v_to_review loop
    v_before := private.time_shift_json(v_id);
    begin
      update public.time_shifts s
         set review_status = 'reviewed',
             reviewed_at   = v_now,
             reviewed_by   = v_uid
       where s.id = v_id
      returning s.user_id into v_subject;

      perform private.time_audit_insert(
        v_id, v_subject, v_uid, 'review', v_note,
        v_before, private.time_shift_json(v_id), null, v_now);
    exception when integrity_constraint_violation then
      get stacked diagnostics v_constraint = constraint_name, v_message = message_text;
      perform private.time_raise(private.time_constraint_code(v_constraint, v_message));
    end;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

-- ── 2.7 Grants da seção ────────────────────────────────────────────────────
-- Tabelas: só leitura (RLS decide as linhas). Revoke de tabela também tira o
-- MAINTAIN do PG 17 e os grants de coluna. As sequências das colunas
-- identity também vêm abertas pelo default do Supabase: sem revoke,
-- authenticated poderia chamar setval e bagunçar a ordem da auditoria.
revoke all on table public.time_shifts, public.time_breaks, public.time_audit_events
  from anon, authenticated;
grant select on table public.time_shifts, public.time_breaks, public.time_audit_events
  to authenticated;

revoke all on sequence public.time_audit_events_seq_seq from anon, authenticated;

revoke all on table public.time_shift_totals from anon, authenticated;
grant select on table public.time_shift_totals to authenticated;

revoke all on function public.time_my_status() from public, anon;
revoke all on function public.time_clock_in(uuid, text) from public, anon;
revoke all on function public.time_start_break(uuid) from public, anon;
revoke all on function public.time_end_break(uuid) from public, anon;
revoke all on function public.time_clock_out(uuid, boolean, text) from public, anon;
revoke all on function public.time_correct_shift(uuid, timestamptz, timestamptz, jsonb, text, uuid) from public, anon;
revoke all on function public.time_create_manual_shift(uuid, timestamptz, timestamptz, jsonb, text, uuid) from public, anon;
revoke all on function public.time_void_shift(uuid, text, uuid) from public, anon;
revoke all on function public.time_review_shifts(jsonb, text) from public, anon;

grant execute on function public.time_my_status() to authenticated;
grant execute on function public.time_clock_in(uuid, text) to authenticated;
grant execute on function public.time_start_break(uuid) to authenticated;
grant execute on function public.time_end_break(uuid) to authenticated;
grant execute on function public.time_clock_out(uuid, boolean, text) to authenticated;
grant execute on function public.time_correct_shift(uuid, timestamptz, timestamptz, jsonb, text, uuid) to authenticated;
grant execute on function public.time_create_manual_shift(uuid, timestamptz, timestamptz, jsonb, text, uuid) to authenticated;
grant execute on function public.time_void_shift(uuid, text, uuid) to authenticated;
grant execute on function public.time_review_shifts(jsonb, text) to authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- 3. Trabalho: tarefas, registros, entregas, histórico
-- ════════════════════════════════════════════════════════════════════════════
-- Tabelas próprias: kanban_tasks/weekly_goals (painel web) não são tocadas.
-- Aqui a escrita é direta pelo PostgREST, com três camadas: grant por coluna,
-- RLS e triggers (regras de coluna por papel e histórico).

-- ── 3.1 Tabelas ────────────────────────────────────────────────────────────
-- Não há DELETE: "cancelar = excluir". canceled sai das listas padrão e o
-- histórico permanece. priority_rank existe só para ordenar por urgência.
create table if not exists public.work_tasks (
  id            uuid        primary key default gen_random_uuid(),
  title         text        not null check (char_length(btrim(title)) between 1 and 200),
  description   text        check (description is null or char_length(description) <= 10000),
  assignee_id   uuid        references public.profiles(id) on delete restrict,
  created_by    uuid        not null default auth.uid() references public.profiles(id) on delete restrict,
  priority      text        not null default 'medium' check (priority in ('low', 'medium', 'high', 'urgent')),
  priority_rank smallint    generated always as (
                              case priority when 'urgent' then 0 when 'high' then 1 when 'medium' then 2 else 3 end
                            ) stored,
  status        text        not null default 'todo'
                            check (status in ('todo', 'in_progress', 'blocked', 'in_review', 'done', 'canceled')),
  due_date      date,
  completed_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists work_tasks_assignee_status_idx on public.work_tasks (assignee_id, status);
create index if not exists work_tasks_created_by_idx      on public.work_tasks (created_by);
create index if not exists work_tasks_status_idx          on public.work_tasks (status);
create index if not exists work_tasks_due_date_idx        on public.work_tasks (due_date);

-- "O que foi feito" (+ resultado). Somente inclusão: corrige-se com um novo
-- registro. Vínculo opcional com tarefa e com jornada.
create table if not exists public.work_logs (
  id            uuid        primary key default gen_random_uuid(),
  user_id       uuid        not null default auth.uid() references public.profiles(id) on delete restrict,
  task_id       uuid        references public.work_tasks(id) on delete restrict,
  shift_id      uuid        references public.time_shifts(id) on delete restrict,
  summary       text        not null check (char_length(btrim(summary)) between 1 and 4000),
  result        text        check (result is null or char_length(result) <= 4000),
  minutes_spent integer     check (minutes_spent is null or minutes_spent between 1 and 1440),
  logged_on     date        not null default ((now() at time zone 'America/Sao_Paulo')::date),
  created_at    timestamptz not null default now()
);

create index if not exists work_logs_task_created_idx   on public.work_logs (task_id, created_at desc);
create index if not exists work_logs_user_logged_on_idx on public.work_logs (user_id, logged_on desc);
create index if not exists work_logs_shift_idx          on public.work_logs (shift_id);

-- Entrega/resultado com link opcional (v1 só aceita link http/https; anexo de
-- arquivo exige bucket próprio — pendência do contrato §6). Somente inclusão.
create table if not exists public.work_deliverables (
  id          uuid        primary key default gen_random_uuid(),
  task_id     uuid        not null references public.work_tasks(id) on delete restrict,
  work_log_id uuid        references public.work_logs(id) on delete restrict,
  created_by  uuid        not null default auth.uid() references public.profiles(id) on delete restrict,
  title       text        not null check (char_length(btrim(title)) between 1 and 200),
  url         text        check (url is null or (char_length(url) <= 2000 and url ~* '^https?://[^[:space:]]+$')),
  notes       text        check (notes is null or char_length(notes) <= 2000),
  created_at  timestamptz not null default now()
);

create index if not exists work_deliverables_task_created_idx on public.work_deliverables (task_id, created_at desc);

-- Histórico da tarefa: somente inclusão e escrito SÓ pelos triggers abaixo.
-- actor_id null = service_role/migration (sem usuário final).
create table if not exists public.work_task_events (
  id         uuid        primary key default gen_random_uuid(),
  seq        bigint      generated always as identity,
  task_id    uuid        not null references public.work_tasks(id) on delete restrict,
  actor_id   uuid        references public.profiles(id) on delete restrict,
  action     text        not null check (action in ('created', 'updated', 'log_added', 'deliverable_added')),
  changes    jsonb       not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);

create unique index if not exists work_task_events_seq_uniq     on public.work_task_events (seq);
create index if not exists        work_task_events_task_seq_idx on public.work_task_events (task_id, seq);

-- ── 3.2 Triggers ───────────────────────────────────────────────────────────
-- Regras de coluna por papel. SECURITY INVOKER de propósito: com DEFINER,
-- current_user seria o dono da função e "é usuário final?" seria sempre não.
-- Assim current_user é o papel real da conexão — 'authenticated'/'anon' via
-- PostgREST, 'service_role' nas Edge Functions, 'postgres' no SQL Editor.
-- O papel do chamador vem só dos helpers (que authenticated pode executar).
--   Usuário final fora do módulo (client, sem perfil): not_allowed já aqui.
--   Trigger BEFORE roda antes do WITH CHECK da RLS; sem esta barreira, o
--   work_tasks_validate_assignee responderia primeiro e diria a um cliente
--   se um uuid qualquer é perfil interno (oráculo da equipe).
--   INSERT de usuário final: created_by = quem chama, datas do servidor.
--   UPDATE de usuário final: id/created_by/created_at imutáveis (o grant por
--   coluna já barra antes; isto é a rede de proteção). Fora do super_admin,
--   assignee_id é imutável; quem criou muda título, descrição, prioridade,
--   prazo e status; tarefa atribuída por outra pessoa (e sdr sempre) só muda
--   status e nunca usa `canceled` — nem para cancelar nem para tirar do
--   cancelamento, que é decisão de quem criou.
create or replace function private.work_tasks_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_end_user boolean := current_user in ('authenticated', 'anon');
  v_uid      uuid    := auth.uid();
  v_role     text;
begin
  if v_end_user and not private.pt_is_internal() then
    raise exception 'not_allowed'
      using errcode = '42501',
            detail  = 'Você não tem permissão para esta ação.';
  end if;

  if tg_op = 'INSERT' then
    if v_end_user then
      new.created_by := v_uid;
      new.created_at := now();
    end if;
    new.completed_at := case when new.status = 'done' then now() end;
  else
    if v_end_user then
      if new.id is distinct from old.id
         or new.created_by is distinct from old.created_by
         or new.created_at is distinct from old.created_at then
        raise exception 'task_field_not_allowed'
          using errcode = '42501',
                detail  = 'Você não pode alterar este campo desta tarefa.';
      end if;

      if not private.pt_is_super_admin() then
        v_role := private.pt_current_role();

        if new.assignee_id is distinct from old.assignee_id then
          raise exception 'task_field_not_allowed'
            using errcode = '42501',
                  detail  = 'Você não pode alterar este campo desta tarefa.';
        end if;

        if v_role is distinct from 'sdr' and old.created_by = v_uid then
          null; -- quem criou: título, descrição, prioridade, prazo e status
        elsif new.title       is distinct from old.title
           or new.description is distinct from old.description
           or new.priority    is distinct from old.priority
           or new.due_date    is distinct from old.due_date
           or (new.status is distinct from old.status
               and (new.status = 'canceled' or old.status = 'canceled')) then
          raise exception 'task_field_not_allowed'
            using errcode = '42501',
                  detail  = 'Você não pode alterar este campo desta tarefa.';
        end if;
      end if;
    end if;

    -- completed_at é só do servidor: continua concluída → mantém a data em
    -- que concluiu (ninguém a reescreve num UPDATE qualquer).
    if new.status = 'done' and old.status is distinct from 'done' then
      new.completed_at := now();
    elsif new.status <> 'done' then
      new.completed_at := null;
    else
      new.completed_at := old.completed_at;
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

revoke all on function private.work_tasks_before_write() from public, anon, authenticated;

drop trigger if exists work_tasks_before_write on public.work_tasks;
create trigger work_tasks_before_write
  before insert or update on public.work_tasks
  for each row execute function private.work_tasks_before_write();

-- DEFINER: precisa ler o perfil de OUTRA pessoa (o responsável), o que a RLS
-- de profiles não deixa todo papel interno fazer. Não olha current_user.
create or replace function private.work_tasks_validate_assignee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.assignee_id is not null
     and not private.pt_is_internal_role(
           (select p.role from public.profiles p where p.id = new.assignee_id)) then
    raise exception 'invalid_assignee'
      using errcode = '23514',
            detail  = 'Responsável inválido.';
  end if;
  return new;
end;
$$;

revoke all on function private.work_tasks_validate_assignee() from public, anon, authenticated;

drop trigger if exists work_tasks_validate_assignee on public.work_tasks;
create trigger work_tasks_validate_assignee
  before insert or update of assignee_id on public.work_tasks
  for each row execute function private.work_tasks_validate_assignee();

-- INVOKER pelo mesmo motivo do work_tasks_before_write: autor e data vêm do
-- servidor quando quem escreve é usuário final.
create or replace function private.work_logs_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.user_id    := auth.uid();
    new.created_at := now();
  end if;
  return new;
end;
$$;

revoke all on function private.work_logs_before_insert() from public, anon, authenticated;

drop trigger if exists work_logs_before_insert on public.work_logs;
create trigger work_logs_before_insert
  before insert on public.work_logs
  for each row execute function private.work_logs_before_insert();

create or replace function private.work_deliverables_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.created_by := auth.uid();
    new.created_at := now();
  end if;
  return new;
end;
$$;

revoke all on function private.work_deliverables_before_insert() from public, anon, authenticated;

drop trigger if exists work_deliverables_before_insert on public.work_deliverables;
create trigger work_deliverables_before_insert
  before insert on public.work_deliverables
  for each row execute function private.work_deliverables_before_insert();

-- Histórico. DEFINER porque escreve em work_task_events, que não tem grant
-- nem policy de escrita para ninguém. actor_id = auth.uid() quando é um
-- perfil (service_role sem usuário fica null, em vez de quebrar a FK).
create or replace function private.work_tasks_log_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor   uuid;
  v_changes jsonb := '{}'::jsonb;
begin
  select p.id into v_actor from public.profiles p where p.id = auth.uid();

  if tg_op = 'INSERT' then
    insert into public.work_task_events (task_id, actor_id, action, changes)
    values (new.id, v_actor, 'created', jsonb_build_object(
      'title',       new.title,
      'status',      new.status,
      'priority',    new.priority,
      'assignee_id', new.assignee_id,
      'due_date',    new.due_date));
    return null;
  end if;

  if new.title is distinct from old.title then
    v_changes := v_changes || jsonb_build_object('title', jsonb_build_object('from', old.title, 'to', new.title));
  end if;
  if new.description is distinct from old.description then
    v_changes := v_changes || jsonb_build_object('description', jsonb_build_object('from', old.description, 'to', new.description));
  end if;
  if new.assignee_id is distinct from old.assignee_id then
    v_changes := v_changes || jsonb_build_object('assignee_id', jsonb_build_object('from', old.assignee_id, 'to', new.assignee_id));
  end if;
  if new.priority is distinct from old.priority then
    v_changes := v_changes || jsonb_build_object('priority', jsonb_build_object('from', old.priority, 'to', new.priority));
  end if;
  if new.status is distinct from old.status then
    v_changes := v_changes || jsonb_build_object('status', jsonb_build_object('from', old.status, 'to', new.status));
  end if;
  if new.due_date is distinct from old.due_date then
    v_changes := v_changes || jsonb_build_object('due_date', jsonb_build_object('from', old.due_date, 'to', new.due_date));
  end if;

  if v_changes <> '{}'::jsonb then
    insert into public.work_task_events (task_id, actor_id, action, changes)
    values (new.id, v_actor, 'updated', v_changes);
  end if;
  return null;
end;
$$;

revoke all on function private.work_tasks_log_event() from public, anon, authenticated;

drop trigger if exists work_tasks_log_event on public.work_tasks;
create trigger work_tasks_log_event
  after insert or update on public.work_tasks
  for each row execute function private.work_tasks_log_event();

-- Registro no histórico da tarefa leva SÓ o id: resumo, minutos e jornada são
-- privados ao autor (quem vê a tarefa não vê o registro alheio).
create or replace function private.work_logs_log_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.task_id is not null then
    insert into public.work_task_events (task_id, actor_id, action, changes)
    values (new.task_id,
            (select p.id from public.profiles p where p.id = auth.uid()),
            'log_added',
            jsonb_build_object('log_id', new.id));
  end if;
  return null;
end;
$$;

revoke all on function private.work_logs_log_event() from public, anon, authenticated;

drop trigger if exists work_logs_log_event on public.work_logs;
create trigger work_logs_log_event
  after insert on public.work_logs
  for each row execute function private.work_logs_log_event();

create or replace function private.work_deliverables_log_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.work_task_events (task_id, actor_id, action, changes)
  values (new.task_id,
          (select p.id from public.profiles p where p.id = auth.uid()),
          'deliverable_added',
          jsonb_build_object('deliverable_id', new.id, 'title', new.title));
  return null;
end;
$$;

revoke all on function private.work_deliverables_log_event() from public, anon, authenticated;

drop trigger if exists work_deliverables_log_event on public.work_deliverables;
create trigger work_deliverables_log_event
  after insert on public.work_deliverables
  for each row execute function private.work_deliverables_log_event();

drop trigger if exists work_task_events_immutable on public.work_task_events;
create trigger work_task_events_immutable
  before update or delete on public.work_task_events
  for each row execute function private.pt_audit_immutable();

-- ── 3.3 RLS ────────────────────────────────────────────────────────────────
-- Colunas da tabela externa SEMPRE qualificadas nas subconsultas
-- (work_deliverables.task_id): solto, `l.task_id = task_id` se resolve para a
-- tabela de dentro e vira `l.task_id = l.task_id`, sempre verdadeiro.
-- As subconsultas em work_tasks rodam com a RLS de work_tasks de quem consulta,
-- então eventos/entregas herdam a visibilidade da tarefa.
--
-- Tarefas: super_admin vê todas; os demais internos veem as atribuídas a si e
-- as que criaram; sdr só as atribuídas (matriz do contrato §2 — sdr não cria
-- tarefa, mas um perfil que virou sdr não continua vendo o que criou antes).
alter table public.work_tasks        enable row level security;
alter table public.work_logs         enable row level security;
alter table public.work_deliverables enable row level security;
alter table public.work_task_events  enable row level security;

drop policy if exists work_tasks_select on public.work_tasks;
create policy work_tasks_select on public.work_tasks
  for select to authenticated
  using (
    (select private.pt_is_internal())
    and (
      (select private.pt_is_super_admin())
      or work_tasks.assignee_id = (select auth.uid())
      or (work_tasks.created_by = (select auth.uid()) and (select private.pt_current_role()) <> 'sdr')
    )
  );

-- Criar: super_admin para qualquer interno (ou sem responsável); os demais só
-- para si; sdr não cria. created_by já foi forçado pelo trigger.
drop policy if exists work_tasks_insert on public.work_tasks;
create policy work_tasks_insert on public.work_tasks
  for insert to authenticated
  with check (
    (select private.pt_is_internal())
    and work_tasks.created_by = (select auth.uid())
    and (
      (select private.pt_is_super_admin())
      or ((select private.pt_current_role()) <> 'sdr' and work_tasks.assignee_id = (select auth.uid()))
    )
  );

drop policy if exists work_tasks_update on public.work_tasks;
create policy work_tasks_update on public.work_tasks
  for update to authenticated
  using (
    (select private.pt_is_internal())
    and (
      (select private.pt_is_super_admin())
      or work_tasks.assignee_id = (select auth.uid())
      or (work_tasks.created_by = (select auth.uid()) and (select private.pt_current_role()) <> 'sdr')
    )
  )
  with check (
    (select private.pt_is_internal())
    and (
      (select private.pt_is_super_admin())
      or work_tasks.assignee_id = (select auth.uid())
      or (work_tasks.created_by = (select auth.uid()) and (select private.pt_current_role()) <> 'sdr')
    )
  );

-- Registros: cada um vê os próprios (super_admin vê todos). Vincular só a
-- tarefa que a pessoa enxerga e a jornada própria e não anulada.
drop policy if exists work_logs_select on public.work_logs;
create policy work_logs_select on public.work_logs
  for select to authenticated
  using (
    (select private.pt_is_internal())
    and (work_logs.user_id = (select auth.uid()) or (select private.pt_is_super_admin()))
  );

drop policy if exists work_logs_insert on public.work_logs;
create policy work_logs_insert on public.work_logs
  for insert to authenticated
  with check (
    (select private.pt_is_internal())
    and work_logs.user_id = (select auth.uid())
    and (
      work_logs.task_id is null
      or exists (
        select 1
          from public.work_tasks t
         where t.id = work_logs.task_id
           and (t.assignee_id = (select auth.uid())
                or t.created_by = (select auth.uid())
                or (select private.pt_is_super_admin()))
      )
    )
    and (
      work_logs.shift_id is null
      or exists (
        select 1
          from public.time_shifts s
         where s.id = work_logs.shift_id
           and s.user_id = (select auth.uid())
           and s.voided_at is null
      )
    )
  );

drop policy if exists work_deliverables_select on public.work_deliverables;
create policy work_deliverables_select on public.work_deliverables
  for select to authenticated
  using (
    (select private.pt_is_internal())
    and (
      (select private.pt_is_super_admin())
      or exists (
        select 1
          from public.work_tasks t
         where t.id = work_deliverables.task_id
           and (t.assignee_id = (select auth.uid()) or t.created_by = (select auth.uid()))
      )
    )
  );

-- Entrega ligada a registro: o registro tem de ser da MESMA tarefa e do
-- próprio autor.
drop policy if exists work_deliverables_insert on public.work_deliverables;
create policy work_deliverables_insert on public.work_deliverables
  for insert to authenticated
  with check (
    (select private.pt_is_internal())
    and work_deliverables.created_by = (select auth.uid())
    and exists (
      select 1
        from public.work_tasks t
       where t.id = work_deliverables.task_id
         and (t.assignee_id = (select auth.uid())
              or t.created_by = (select auth.uid())
              or (select private.pt_is_super_admin()))
    )
    and (
      work_deliverables.work_log_id is null
      or exists (
        select 1
          from public.work_logs l
         where l.id = work_deliverables.work_log_id
           and l.task_id = work_deliverables.task_id
           and l.user_id = (select auth.uid())
      )
    )
  );

drop policy if exists work_task_events_select on public.work_task_events;
create policy work_task_events_select on public.work_task_events
  for select to authenticated
  using (
    (select private.pt_is_internal())
    and (
      (select private.pt_is_super_admin())
      or exists (
        select 1
          from public.work_tasks t
         where t.id = work_task_events.task_id
           and (t.assignee_id = (select auth.uid()) or t.created_by = (select auth.uid()))
      )
    )
  );

-- ── 3.4 Grants da seção ────────────────────────────────────────────────────
-- Por coluna: o usuário final nunca escreve created_by, user_id, completed_at,
-- created_at, updated_at nem priority_rank. `id` entra no insert para o app
-- mandar um uuid gerado no cliente e tornar a repetição idempotente (23505 na
-- pkey → busca o registro existente). Sem UPDATE em registros/entregas e sem
-- DELETE em nada.
revoke all on table public.work_tasks, public.work_logs, public.work_deliverables, public.work_task_events
  from anon, authenticated;
grant select on table public.work_tasks, public.work_logs, public.work_deliverables, public.work_task_events
  to authenticated;
grant insert (id, title, description, assignee_id, priority, status, due_date)
  on public.work_tasks to authenticated;
grant update (title, description, assignee_id, priority, status, due_date)
  on public.work_tasks to authenticated;
grant insert (id, task_id, shift_id, summary, result, minutes_spent, logged_on)
  on public.work_logs to authenticated;
grant insert (id, task_id, work_log_id, title, url, notes)
  on public.work_deliverables to authenticated;

revoke all on sequence public.work_task_events_seq_seq from anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- 4. Diretório de pessoas do módulo
-- ════════════════════════════════════════════════════════════════════════════
-- Nome e papel de quem aparece nas telas, sem abrir profiles (cuja RLS não
-- deixa todo papel interno ver a equipe, e expõe e-mail/contato).
-- super_admin: todos os perfis internos. Demais: eu ∪ criadores/responsáveis
-- das tarefas que vejo ∪ autores dos eventos e das entregas dessas tarefas ∪
-- quem mexeu no meu ponto. Não interno → conjunto vazio.
-- Fica no FIM porque é `language sql`: o corpo é validado na criação e lê
-- tabelas das seções 2 e 3.
create or replace function public.ponto_people()
returns table (id uuid, full_name text, role text)
language sql
stable
security definer
set search_path = ''
as $$
  with caller as (
    select auth.uid()                  as uid,
           private.pt_current_role()   as role,
           private.pt_is_internal()    as internal,
           private.pt_is_super_admin() as super_admin
  ),
  my_tasks as (
    select t.id, t.created_by, t.assignee_id
      from public.work_tasks t
      join caller c on c.internal and not c.super_admin
     where t.assignee_id = c.uid
        or (t.created_by = c.uid and c.role <> 'sdr')
  ),
  people as (
    select c.uid as person_id from caller c where c.internal and not c.super_admin
    union
    select mt.created_by from my_tasks mt
    union
    select mt.assignee_id from my_tasks mt
    union
    select e.actor_id from public.work_task_events e join my_tasks mt on mt.id = e.task_id
    union
    select d.created_by from public.work_deliverables d join my_tasks mt on mt.id = d.task_id
    union
    select a.actor_id
      from public.time_audit_events a
      join caller c on c.internal and not c.super_admin
     where a.subject_user_id = c.uid
  )
  select p.id, coalesce(p.full_name, '') as full_name, p.role
    from public.profiles p
    join caller c on c.internal
   where (c.super_admin and private.pt_is_internal_role(p.role))
      or (not c.super_admin
          and p.id in (select pp.person_id from people pp where pp.person_id is not null))
   order by 2, 1
$$;

revoke all on function public.ponto_people() from public, anon;
grant execute on function public.ponto_people() to authenticated;
