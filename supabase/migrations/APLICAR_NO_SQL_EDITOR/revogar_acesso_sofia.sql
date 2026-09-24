-- ============================================================
-- PIXELRY — revogar o acesso de Sofia (sofiagramelich@icloud.com)
--
-- Rodar no SQL Editor do Supabase. NAO e migration: mexe em dado, nao em
-- schema, e por isso nao entra na pasta de migrations versionadas.
--
-- Tirar o e-mail do codigo (feito no deploy de 24/09/2026) so muda a interface.
-- O acesso de verdade e `profiles.role` + a sessao no Supabase Auth: enquanto
-- a linha dela disser 'employee', o token dela continua valendo para a RLS e
-- para as Edge Functions.
--
-- POR QUE NAO DELETAR A CONTA
-- employee_notes.employee_id, internal_files.from_id/to_id,
-- internal_messages.from_id/to_id e profiles.assigned_employee_id referenciam
-- auth.users(id) SEM `on delete`. O delete falha com violacao de chave
-- estrangeira se existir qualquer registro dela — e, se passasse, levaria o
-- historico junto. Revogar preserva o que ela produziu.
-- ============================================================

-- ── 1. Conferir antes. Nao muda nada. ───────────────────────────────────────
select id, email, role, job_title, full_name
from public.profiles
where email ilike '%sofiagramelich%';

select count(*) as clientes_atribuidos
from public.profiles
where assigned_employee_id in (
  select id from public.profiles where email ilike '%sofiagramelich%'
);

-- ── 2. Revogar. Rode o bloco inteiro de uma vez. ────────────────────────────
begin;

-- Clientes que estavam com ela voltam para "sem responsavel" e aparecem assim
-- no painel, para serem redistribuidos a mao.
update public.profiles
set assigned_employee_id = null
where assigned_employee_id in (
  select id from public.profiles where email ilike '%sofiagramelich%'
);

-- Tira o papel de equipe. 'client' e o unico valor da constraint que nao da
-- acesso ao painel; ela sai da lista de /admin/equipe.
update public.profiles
set role = 'client'
where email ilike '%sofiagramelich%';

commit;

-- ── 3. Encerrar o login. ────────────────────────────────────────────────────
-- Preferir o Dashboard: Authentication → Users → sofiagramelich@icloud.com →
-- "Sign out user" e depois "Delete user" NAO (ver o aviso acima) — use o ban.
-- O SQL abaixo faz o equivalente, caso prefira:

-- update auth.users
-- set banned_until = 'infinity'
-- where email ilike '%sofiagramelich%';

-- delete from auth.sessions
-- where user_id in (select id from auth.users where email ilike '%sofiagramelich%');

-- ── 4. Conferir depois. ─────────────────────────────────────────────────────
select email, role from public.profiles where email ilike '%sofiagramelich%';
-- Esperado: role = 'client'.

-- ── 5. Fora do SQL ──────────────────────────────────────────────────────────
-- Conferir o secret ADMIN_EMAILS das Edge Functions
-- (Dashboard → Edge Functions → Secrets). Qualquer e-mail listado ali passa
-- pela autorizacao em supabase/functions/_shared/auth.ts INDEPENDENTE do role.
-- Se o e-mail dela estiver la, remover.
