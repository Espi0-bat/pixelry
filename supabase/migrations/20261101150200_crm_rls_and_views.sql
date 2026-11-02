-- CRM (app móvel) — 3/4: quem vê e altera o quê, views da lista e do funil,
-- e a RPC de ajuste de acesso.
--
-- Acesso (crm_private.access_level, migration 1/4):
--   full     → super_admin; partner, manager e sales_trial por padrão
--   assigned → sdr por padrão
--   none     → employee, employee_dev, client, desconhecido
--
-- O que "atribuído" significa para quem tem acesso 'assigned':
--   oportunidade → owner_id = eu  ou  sdr_id = eu
--   conta        → owner_id = eu  ou  tem oportunidade atribuída a mim
--   contato      → owner_id = eu  ou  está numa oportunidade atribuída a mim
--                  ou  pertence a uma conta que eu vejo
--   atividade    → ligada a algo que eu vejo
--   histórico    → de algo que eu vejo (ajuste de acesso: só super_admin)
--
-- Escrita:
--   * full escreve em tudo e atribui responsável/SDR.
--   * assigned cria registros (sempre dele: guard_row) e altera o que vê,
--     sem trocar responsável/SDR (guard_row) e sem ligar a contas, contatos
--     ou oportunidades que não vê (WITH CHECK abaixo).
--   * Exclusão definitiva: só super_admin. O app arquiva (archived_at).
--   * Etapas: leitura para quem tem CRM; edição para super_admin, partner e
--     manager com CRM completo.
--
-- (select fn()) faz o planner avaliar a função uma vez por consulta
-- (advisor auth_rls_initplan).

-- ── Visibilidade por atribuição ─────────────────────────────────────────────
-- SECURITY DEFINER: consultam as tabelas sem passar pela RLS delas, o que
-- evita recursão entre as policies de contas, contatos e oportunidades.
-- Todas olham só para auth.uid(); com id nulo devolvem false.

create or replace function crm_private.has_assigned_opportunity_in_account(p_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.crm_opportunities o
    where o.account_id = p_account_id
      and (o.owner_id = auth.uid() or o.sdr_id = auth.uid())
  )
$$;

create or replace function crm_private.has_assigned_opportunity_with_contact(p_contact_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.crm_opportunities o
    where o.contact_id = p_contact_id
      and (o.owner_id = auth.uid() or o.sdr_id = auth.uid())
  )
$$;

create or replace function crm_private.can_see_opportunity(p_opportunity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case crm_private.access_level()
    when 'full' then p_opportunity_id is not null
                     and exists (select 1 from public.crm_opportunities o where o.id = p_opportunity_id)
    when 'assigned' then exists (
      select 1 from public.crm_opportunities o
      where o.id = p_opportunity_id
        and (o.owner_id = auth.uid() or o.sdr_id = auth.uid())
    )
    else false
  end
$$;

create or replace function crm_private.can_see_account(p_account_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case crm_private.access_level()
    when 'full' then p_account_id is not null
                     and exists (select 1 from public.crm_accounts a where a.id = p_account_id)
    when 'assigned' then
      exists (select 1 from public.crm_accounts a where a.id = p_account_id and a.owner_id = auth.uid())
      or crm_private.has_assigned_opportunity_in_account(p_account_id)
    else false
  end
$$;

create or replace function crm_private.can_see_contact(p_contact_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case crm_private.access_level()
    when 'full' then p_contact_id is not null
                     and exists (select 1 from public.crm_contacts c where c.id = p_contact_id)
    when 'assigned' then
      exists (
        select 1 from public.crm_contacts c
        where c.id = p_contact_id
          and (c.owner_id = auth.uid()
               or (c.account_id is not null and crm_private.can_see_account(c.account_id)))
      )
      or crm_private.has_assigned_opportunity_with_contact(p_contact_id)
    else false
  end
$$;

create or replace function crm_private.can_see_activity(p_activity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.crm_activities a
    where a.id = p_activity_id
      and (crm_private.access_level() = 'full'
           or crm_private.can_see_opportunity(a.opportunity_id)
           or crm_private.can_see_account(a.account_id)
           or crm_private.can_see_contact(a.contact_id))
  )
$$;

revoke execute on function crm_private.has_assigned_opportunity_in_account(uuid)   from public;
revoke execute on function crm_private.has_assigned_opportunity_with_contact(uuid) from public;
revoke execute on function crm_private.can_see_opportunity(uuid)                   from public;
revoke execute on function crm_private.can_see_account(uuid)                       from public;
revoke execute on function crm_private.can_see_contact(uuid)                       from public;
revoke execute on function crm_private.can_see_activity(uuid)                      from public;

-- Usadas nas policies: authenticated precisa de EXECUTE.
grant execute on function crm_private.has_assigned_opportunity_in_account(uuid)   to authenticated, service_role;
grant execute on function crm_private.has_assigned_opportunity_with_contact(uuid) to authenticated, service_role;
grant execute on function crm_private.can_see_opportunity(uuid)                   to authenticated, service_role;
grant execute on function crm_private.can_see_account(uuid)                       to authenticated, service_role;
grant execute on function crm_private.can_see_contact(uuid)                       to authenticated, service_role;
grant execute on function crm_private.can_see_activity(uuid)                      to authenticated, service_role;

-- ── Etapas ──────────────────────────────────────────────────────────────────
create policy crm_stages_select on public.crm_stages
  for select to authenticated
  using ((select crm_private.access_level()) <> 'none');

create policy crm_stages_insert on public.crm_stages
  for insert to authenticated
  with check ((select crm_private.can_manage_stages()));

create policy crm_stages_update on public.crm_stages
  for update to authenticated
  using ((select crm_private.can_manage_stages()))
  with check ((select crm_private.can_manage_stages()));

create policy crm_stages_delete on public.crm_stages
  for delete to authenticated
  using ((select crm_private.can_manage_stages()));

-- ── Contas ──────────────────────────────────────────────────────────────────
create policy crm_accounts_select on public.crm_accounts
  for select to authenticated
  using (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and (owner_id = (select auth.uid())
             or crm_private.has_assigned_opportunity_in_account(id)))
  );

create policy crm_accounts_insert on public.crm_accounts
  for insert to authenticated
  with check (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and owner_id = (select auth.uid()))
  );

create policy crm_accounts_update on public.crm_accounts
  for update to authenticated
  using (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and (owner_id = (select auth.uid())
             or crm_private.has_assigned_opportunity_in_account(id)))
  )
  with check (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and (owner_id = (select auth.uid())
             or crm_private.has_assigned_opportunity_in_account(id)))
  );

create policy crm_accounts_delete on public.crm_accounts
  for delete to authenticated
  using ((select crm_private.is_super_admin()));

-- ── Contatos ────────────────────────────────────────────────────────────────
create policy crm_contacts_select on public.crm_contacts
  for select to authenticated
  using (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and (owner_id = (select auth.uid())
             or crm_private.has_assigned_opportunity_with_contact(id)
             or (account_id is not null and crm_private.can_see_account(account_id))))
  );

create policy crm_contacts_insert on public.crm_contacts
  for insert to authenticated
  with check (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and owner_id = (select auth.uid())
        and (account_id is null or crm_private.can_see_account(account_id)))
  );

create policy crm_contacts_update on public.crm_contacts
  for update to authenticated
  using (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and (owner_id = (select auth.uid())
             or crm_private.has_assigned_opportunity_with_contact(id)
             or (account_id is not null and crm_private.can_see_account(account_id))))
  )
  with check (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        -- não pode mover o contato para uma conta que não vê...
        and (account_id is null or crm_private.can_see_account(account_id))
        -- ...e o contato precisa continuar visível depois da alteração
        and (owner_id = (select auth.uid())
             or crm_private.has_assigned_opportunity_with_contact(id)
             or (account_id is not null and crm_private.can_see_account(account_id))))
  );

create policy crm_contacts_delete on public.crm_contacts
  for delete to authenticated
  using ((select crm_private.is_super_admin()));

-- ── Oportunidades ───────────────────────────────────────────────────────────
create policy crm_opportunities_select on public.crm_opportunities
  for select to authenticated
  using (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and (owner_id = (select auth.uid()) or sdr_id = (select auth.uid())))
  );

create policy crm_opportunities_insert on public.crm_opportunities
  for insert to authenticated
  with check (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and (owner_id = (select auth.uid()) or sdr_id = (select auth.uid()))
        and (account_id is null or crm_private.can_see_account(account_id))
        and (contact_id is null or crm_private.can_see_contact(contact_id)))
  );

create policy crm_opportunities_update on public.crm_opportunities
  for update to authenticated
  using (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and (owner_id = (select auth.uid()) or sdr_id = (select auth.uid())))
  )
  with check (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and (owner_id = (select auth.uid()) or sdr_id = (select auth.uid()))
        and (account_id is null or crm_private.can_see_account(account_id))
        and (contact_id is null or crm_private.can_see_contact(contact_id)))
  );

create policy crm_opportunities_delete on public.crm_opportunities
  for delete to authenticated
  using ((select crm_private.is_super_admin()));

-- ── Atividades ──────────────────────────────────────────────────────────────
create policy crm_activities_select on public.crm_activities
  for select to authenticated
  using (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and (crm_private.can_see_opportunity(opportunity_id)
             or crm_private.can_see_account(account_id)
             or crm_private.can_see_contact(contact_id)))
  );

-- Inclusão e edição: quem não tem CRM completo só liga a atividade a
-- registros que vê (todos os informados, não só um) e só edita as próprias.
create policy crm_activities_insert on public.crm_activities
  for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and (
      (select crm_private.access_level()) = 'full'
      or ((select crm_private.access_level()) = 'assigned'
          and (opportunity_id is null or crm_private.can_see_opportunity(opportunity_id))
          and (account_id     is null or crm_private.can_see_account(account_id))
          and (contact_id     is null or crm_private.can_see_contact(contact_id)))
    )
  );

create policy crm_activities_update on public.crm_activities
  for update to authenticated
  using (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and created_by = (select auth.uid())
        and (crm_private.can_see_opportunity(opportunity_id)
             or crm_private.can_see_account(account_id)
             or crm_private.can_see_contact(contact_id)))
  )
  with check (
    (select crm_private.access_level()) = 'full'
    or ((select crm_private.access_level()) = 'assigned'
        and created_by = (select auth.uid())
        and (opportunity_id is null or crm_private.can_see_opportunity(opportunity_id))
        and (account_id     is null or crm_private.can_see_account(account_id))
        and (contact_id     is null or crm_private.can_see_contact(contact_id)))
  );

create policy crm_activities_delete on public.crm_activities
  for delete to authenticated
  using ((select crm_private.is_super_admin()));

-- ── Histórico ───────────────────────────────────────────────────────────────
-- Só SELECT. Sem policy de escrita e sem grant: ninguém do app altera o log.
create policy crm_audit_log_select on public.crm_audit_log
  for select to authenticated
  using (
    case entity_type
      when 'member_access' then (select crm_private.is_super_admin())
      else (select crm_private.access_level()) = 'full'
           or ((select crm_private.access_level()) = 'assigned'
               and case entity_type
                     when 'opportunity' then crm_private.can_see_opportunity(entity_id::uuid)
                     when 'account'     then crm_private.can_see_account(entity_id::uuid)
                     when 'contact'     then crm_private.can_see_contact(entity_id::uuid)
                     when 'activity'    then crm_private.can_see_activity(entity_id::uuid)
                     else false
                   end)
    end
  );

-- ── Views ───────────────────────────────────────────────────────────────────
-- security_invoker: a view roda com a RLS de quem consulta. O SDR recebe só
-- as linhas dele, inclusive nos totais do funil.

-- Lista de oportunidades já com conta, contato e etapa, para filtro, busca e
-- ordenação numa única consulta.
create or replace view public.crm_opportunity_overview
with (security_invoker = true) as
select
  o.id,
  o.title,
  o.account_id,
  a.name       as account_name,
  o.contact_id,
  c.full_name  as contact_name,
  c.phone      as contact_phone,
  c.email      as contact_email,
  o.stage_id,
  s.label      as stage_label,
  s.position   as stage_position,
  s.kind       as stage_kind,
  o.owner_id,
  o.sdr_id,
  o.source,
  o.lead_id,
  o.estimated_value,
  o.next_action,
  o.next_action_at,
  o.expected_close_date,
  o.lost_reason,
  o.qualification,
  o.stage_changed_at,
  o.closed_at,
  o.created_by,
  o.created_at,
  o.updated_at,
  o.archived_at,
  (s.kind = 'open' and o.next_action_at is not null and o.next_action_at < now()) as next_action_overdue,
  lower(concat_ws(' ', o.title, a.name, c.full_name, c.email, c.phone, o.source)) as search_text
from public.crm_opportunities o
join public.crm_stages s on s.id = o.stage_id
left join public.crm_accounts a on a.id = o.account_id
left join public.crm_contacts c on c.id = o.contact_id;

-- Indicadores do funil: quantidade, valor estimado e ações vencidas por etapa
-- ativa, sem as arquivadas.
create or replace view public.crm_funnel_summary
with (security_invoker = true) as
select
  s.id        as stage_id,
  s.label,
  s.position,
  s.kind,
  s.probability,
  count(o.id)::integer                                       as opportunity_count,
  coalesce(sum(o.estimated_value), 0)::numeric(14, 2)        as estimated_total,
  (count(o.id) filter (
     where s.kind = 'open' and o.next_action_at < now()))::integer as overdue_count
from public.crm_stages s
left join public.crm_opportunities o
  on o.stage_id = s.id and o.archived_at is null
where s.active
group by s.id, s.label, s.position, s.kind, s.probability;

revoke all on table public.crm_opportunity_overview, public.crm_funnel_summary from anon, authenticated;
grant select on table public.crm_opportunity_overview, public.crm_funnel_summary to authenticated;

-- ── Ajuste de acesso (fim da fase probatória, SDR novo etc.) ────────────────
-- p_access: 'full' | 'assigned' | 'none' | NULL (volta ao padrão do papel).
-- Só super_admin. super_admin e client não são ajustáveis. Fica no histórico.
create or replace function public.crm_set_member_access(p_user_id uuid, p_access text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text;
  v_old  text;
begin
  if not crm_private.is_super_admin() then
    raise exception 'Somente o super administrador altera acessos ao CRM.'
      using errcode = '42501';
  end if;

  if p_access is not null and p_access <> all (array['none', 'assigned', 'full']) then
    raise exception 'Nível de acesso inválido: use full, assigned, none ou nulo.'
      using errcode = '22023';
  end if;

  select p.role, p.crm_access into v_role, v_old
  from public.profiles p
  where p.id = p_user_id
  for update;

  if not found then
    raise exception 'Pessoa não encontrada.' using errcode = 'P0002';
  end if;

  if v_role = any (array['super_admin', 'client']) then
    raise exception 'O acesso ao CRM deste papel não é ajustável.' using errcode = '22023';
  end if;

  if v_old is distinct from p_access then
    update public.profiles set crm_access = p_access where id = p_user_id;

    insert into public.crm_audit_log (entity_type, entity_id, action, changes, actor_id)
    values ('member_access', p_user_id::text, 'update',
            jsonb_build_object('crm_access', jsonb_build_object('old', v_old, 'new', p_access)),
            auth.uid());
  end if;

  return jsonb_build_object(
    'user_id', p_user_id,
    'role', v_role,
    'crm_access', p_access,
    'access_level', crm_private.access_level_of(p_user_id)
  );
end;
$$;

revoke execute on function public.crm_set_member_access(uuid, text) from public, anon;
grant execute on function public.crm_set_member_access(uuid, text) to authenticated;

-- ── Novo lead pelo app ──────────────────────────────────────────────────────
-- Conta (nova ou existente), contato e oportunidade numa transação só.
-- SECURITY INVOKER: cada INSERT passa pela RLS e pelas travas de quem chama,
-- exatamente como se o app fizesse os três. Por isso o SDR não consegue
-- criar para outra pessoa nem ligar a uma conta que não vê.
-- p_request_id é a chave de idempotência: repetir a chamada (toque duplo,
-- retry de rede) devolve a mesma oportunidade sem duplicar nada.
create or replace function public.crm_create_opportunity(
  p_request_id      uuid,
  p_title           text,
  p_account_id      uuid        default null,
  p_account_name    text        default null,
  p_contact_name    text        default null,
  p_contact_phone   text        default null,
  p_contact_email   text        default null,
  p_source          text        default null,
  p_stage_id        text        default 'novo',
  p_estimated_value numeric     default null,
  p_next_action     text        default null,
  p_next_action_at  timestamptz default null,
  p_owner_id        uuid        default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id         uuid;
  v_account_id uuid := p_account_id;
  v_contact_id uuid;
  v_owner_id   uuid := coalesce(p_owner_id, auth.uid());
begin
  if p_request_id is null then
    raise exception 'Envio sem chave de idempotência.' using errcode = '22023';
  end if;

  select o.id into v_id
  from public.crm_opportunities o
  where o.client_request_id = p_request_id;
  if found then
    return v_id;
  end if;

  if v_account_id is null and nullif(btrim(p_account_name), '') is not null then
    insert into public.crm_accounts (name, owner_id, client_request_id)
    values (btrim(p_account_name), v_owner_id, p_request_id)
    returning id into v_account_id;
  end if;

  if nullif(btrim(p_contact_name), '') is not null then
    insert into public.crm_contacts (account_id, full_name, phone, email, owner_id, client_request_id)
    values (v_account_id, btrim(p_contact_name), nullif(btrim(p_contact_phone), ''),
            nullif(btrim(p_contact_email), ''), v_owner_id, p_request_id)
    returning id into v_contact_id;
  end if;

  insert into public.crm_opportunities (
    title, account_id, contact_id, stage_id, owner_id, source,
    estimated_value, next_action, next_action_at, client_request_id
  ) values (
    btrim(p_title), v_account_id, v_contact_id, coalesce(p_stage_id, 'novo'), v_owner_id,
    nullif(btrim(p_source), ''), p_estimated_value, nullif(btrim(p_next_action), ''),
    p_next_action_at, p_request_id
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke execute on function public.crm_create_opportunity(
  uuid, text, uuid, text, text, text, text, text, text, numeric, text, timestamptz, uuid
) from public, anon;
grant execute on function public.crm_create_opportunity(
  uuid, text, uuid, text, text, text, text, text, text, numeric, text, timestamptz, uuid
) to authenticated;
