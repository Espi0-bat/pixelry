-- Rate limiting de aplicação, compartilhado pelas Edge Functions.
--
-- Não substitui um WAF (Cloudflare) na frente do domínio — é a camada de
-- defesa que roda dentro do Supabase, contíguo aos dados. Janela fixa simples.

create table if not exists public.rate_limits (
  bucket       text        not null,
  window_start timestamptz not null,
  hits         integer     not null default 0,
  primary key (bucket, window_start)
);

alter table public.rate_limits enable row level security;
revoke all on table public.rate_limits from anon, authenticated;

-- Retorna true se a chamada está DENTRO do limite; false se estourou.
-- Uso: select public.check_rate_limit('lead:' || ip, 5, 60);
create or replace function public.check_rate_limit(
  p_bucket         text,
  p_limit          integer,
  p_window_seconds integer
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_window timestamptz;
  v_hits   integer;
begin
  v_window := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );

  insert into public.rate_limits (bucket, window_start, hits)
  values (p_bucket, v_window, 1)
  on conflict (bucket, window_start)
  do update set hits = public.rate_limits.hits + 1
  returning hits into v_hits;

  -- Limpeza oportunista (~1% das chamadas) — não há pg_cron neste projeto.
  if random() < 0.01 then
    delete from public.rate_limits where window_start < now() - interval '1 hour';
  end if;

  return v_hits <= p_limit;
end;
$$;

revoke all on function public.check_rate_limit(text, integer, integer) from anon, authenticated, public;
grant execute on function public.check_rate_limit(text, integer, integer) to service_role;
