#!/usr/bin/env bash
# Suíte SQL do financeiro. Roda num Postgres local descartável ou em
# homologação. NUNCA em produção.
#
#   DATABASE_URL=postgres://postgres:postgres@localhost:5432/finance_test \
#     supabase/tests/finance/run.sh --bootstrap        # Postgres vazio
#
#   DATABASE_URL=<url de homologação> FINANCE_FORBIDDEN_REFS=<ref de produção> \
#     supabase/tests/finance/run.sh --skip-migrations  # migrations já aplicadas
#
# Passos:
#   1. trava de segurança (abaixo);
#   2. --bootstrap: fixtures/00_supabase_stub.sql e fixtures/01_baseline_public.sql
#      (ambos não fazem nada se o banco já tiver auth.users / public.profiles);
#   3. sem --skip-migrations: aplica as 5 migrations 202611011745[0-4]0_finance_*.sql
#      em ordem, cada uma numa transação (psql -1), e aplica TODAS DE NOVO
#      (prova de idempotência);
#   4. roda finance_rls.test.sql com PGOPTIONS='-c pixelry.finance_test_harness=on'.
#      A suíte inteira é uma transação que termina em ROLLBACK.
#
# Trava de segurança:
#   * exige DATABASE_URL; só usa psql (nunca `supabase db query` nem --linked);
#   * recusa DATABASE_URL (e PGHOST/PGHOSTADDR/PGUSER/PGSERVICE) que contenha
#     qualquer ref proibida. A lista vem de FINANCE_FORBIDDEN_REFS (separada
#     por vírgula ou espaço) MAIS a ref do projeto linkado, lida de
#     supabase/.temp/project-ref ou supabase/.temp/linked-project.json
#     (arquivos locais, fora do git). Nenhuma ref fica escrita neste
#     repositório, que é público;
#   * se nenhuma ref proibida for conhecida, só aceita banco local
#     (localhost, 127.0.0.1, ::1 ou socket), e só numa forma em que o host
#     real não tenha como ser outro: todo host= precisa ser local, sem lista
#     de hosts (vírgula) e sem %XX nos parâmetros da URI;
#   * recusa hostaddr= e service= na DATABASE_URL e PGHOSTADDR/PGSERVICE no
#     ambiente: com eles o host real não aparece e não dá para conferi-lo;
#   * recusa migration com begin/commit/rollback/start transaction/concurrently.
#
# Sai com o código do psql da suíte (0 = todos os casos passaram).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
migrations_dir="$root/supabase/migrations"

die() {
  printf 'run.sh: %s\n' "$*" >&2
  exit 2
}

usage() {
  sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

bootstrap=0
skip_migrations=0
for arg in "$@"; do
  case "$arg" in
    --bootstrap) bootstrap=1 ;;
    --skip-migrations) skip_migrations=1 ;;
    -h|--help) usage; exit 0 ;;
    --linked|--project-ref|--project-ref=*|--db-url|--db-url=*)
      die "argumento recusado: $arg. Esta suíte só roda por psql com DATABASE_URL (nunca no projeto linkado)." ;;
    *) die "argumento desconhecido: $arg (use --bootstrap, --skip-migrations ou --help)" ;;
  esac
done

if [ "$bootstrap" -eq 1 ] && [ "$skip_migrations" -eq 1 ]; then
  die "--bootstrap e --skip-migrations não combinam: banco vazio precisa das migrations."
fi

command -v psql >/dev/null 2>&1 || die "psql não encontrado no PATH."

[ -n "${DATABASE_URL:-}" ] || die "defina DATABASE_URL (Postgres local descartável ou homologação; nunca produção)."

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

case "$(lower "$DATABASE_URL")" in
  *"supabase db query"*|*--linked*) die "DATABASE_URL inválida." ;;
esac

# ── Refs proibidas ──────────────────────────────────────────────────────────
forbidden=()
if [ -n "${FINANCE_FORBIDDEN_REFS:-}" ]; then
  from_env=()
  IFS=', ' read -r -a from_env <<< "$FINANCE_FORBIDDEN_REFS"
  # ${a[@]+...}: array vazio não quebra `set -u` no bash 3.2 do macOS.
  for ref in ${from_env[@]+"${from_env[@]}"}; do
    if [ -n "$ref" ]; then
      forbidden+=("$(lower "$ref")")
    fi
  done
fi

ref_file="$root/supabase/.temp/project-ref"
if [ -f "$ref_file" ]; then
  linked_ref="$(tr -d '[:space:]' < "$ref_file")"
  if [ -n "$linked_ref" ]; then
    forbidden+=("$(lower "$linked_ref")")
  fi
fi

linked_json="$root/supabase/.temp/linked-project.json"
if [ -f "$linked_json" ]; then
  linked_ref="$(sed -n 's/.*"ref"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9]*\)".*/\1/p' "$linked_json" | head -n 1)"
  if [ -n "$linked_ref" ]; then
    forbidden+=("$(lower "$linked_ref")")
  fi
fi

target="$(lower "$DATABASE_URL ${PGHOST:-} ${PGHOSTADDR:-} ${PGUSER:-} ${PGSERVICE:-}")"

# A libpq aceita espaços em volta do "=" (host = x); normaliza antes de olhar.
norm_url="$(lower "$DATABASE_URL" | sed 's/[[:space:]]*=[[:space:]]*/=/g')"

# hostaddr= conecta num IP que pode não ter nada a ver com o host escrito, e
# service= tira o host de um arquivo fora da URL: nos dois casos a trava não
# enxerga o destino real.
case "$norm_url" in
  *hostaddr=*|*service=*)
    die "DATABASE_URL com hostaddr= ou service= é recusada: o host real não aparece na URL e a trava não consegue conferi-lo." ;;
esac
if [ -n "${PGHOSTADDR:-}${PGSERVICE:-}" ]; then
  die "PGHOSTADDR/PGSERVICE são recusados: o host real não aparece e a trava não consegue conferi-lo. Use só DATABASE_URL."
fi

if [ "${#forbidden[@]}" -gt 0 ]; then
  for ref in "${forbidden[@]}"; do
    case "$target" in
      *"$ref"*) die "o destino contém uma ref proibida (produção). Recusado. Produção não é ambiente de teste." ;;
    esac
  done
else
  # Sem ref conhecida: só banco local, numa forma sem dúvida sobre o host. A
  # libpq deixa ?host= da URI e palavras-chave repetidas sobreporem o host
  # aparente, aceita lista de hosts separada por vírgula e decodifica %XX nos
  # parâmetros da URI; por isso: todo host= tem de ser local, sem vírgula e
  # sem % depois do "?".
  is_local=0
  case "$norm_url" in
    *@localhost:*|*@localhost/*|*@localhost|*@127.0.0.1:*|*@127.0.0.1/*|*@127.0.0.1|*@\[::1\]*) is_local=1 ;;
    postgres:///*|postgresql:///*) is_local=1 ;;
    *host=localhost*|*host=127.0.0.1*|*host=::1*|*host=/*) is_local=1 ;;
  esac
  case "$norm_url" in
    *,*|*\?*%*) is_local=0 ;;
  esac
  while IFS= read -r host_kv; do
    [ -n "$host_kv" ] || continue
    case "${host_kv#host=}" in
      localhost|127.0.0.1|::1|/*) ;;
      *) is_local=0 ;;
    esac
  done <<EOF
$(printf '%s\n' "$norm_url" | grep -o 'host=[^&[:space:]]*' || true)
EOF
  if [ -n "${PGHOST:-}" ]; then
    is_local=0
  fi
  [ "$is_local" -eq 1 ] || die "nenhuma ref proibida conhecida (FINANCE_FORBIDDEN_REFS vazio e sem supabase/.temp) e o destino não é, sem ambiguidade, um banco local. Fora de banco local, defina FINANCE_FORBIDDEN_REFS com a ref de produção."
fi

# ── Migrations do financeiro ────────────────────────────────────────────────
shopt -s nullglob
migrations=("$migrations_dir"/202611011745[0-4]0_finance_*.sql)
shopt -u nullglob
[ "${#migrations[@]}" -eq 5 ] || die "esperadas 5 migrations 202611011745[0-4]0_finance_*.sql, encontradas ${#migrations[@]}."

for f in "${migrations[@]}"; do
  if grep -Eiq '^[[:space:]]*(begin([[:space:]]+(work|transaction))?|commit|rollback|abort|end[[:space:]]+(work|transaction))[[:space:]]*;' "$f" \
     || grep -Eiq 'start[[:space:]]+transaction|concurrently' "$f"; then
    die "$(basename "$f") contém controle de transação ou CONCURRENTLY; migrations do financeiro não podem ter isso."
  fi
done

suite="$here/finance_rls.test.sql"
[ -f "$suite" ] || die "não encontrei $suite"

# O total esperado no fim da suíte precisa bater com as chamadas de pg_temp.chk.
declared="$(sed -n 's/.*v_expected constant integer := \([0-9][0-9]*\);.*/\1/p' "$suite" | head -n 1)"
literal="$(grep -o "pg_temp\.chk('" "$suite" | wc -l | tr -d '[:space:]')"
[ "$declared" = "$literal" ] || die "finance_rls.test.sql declara $declared casos mas tem $literal chamadas de pg_temp.chk."

psql_base=(psql -X -q -v ON_ERROR_STOP=1 -P pager=off --dbname "$DATABASE_URL")

if [ "$bootstrap" -eq 1 ]; then
  echo "── bootstrap: stub do Supabase e baseline de public"
  "${psql_base[@]}" -f "$here/fixtures/00_supabase_stub.sql"
  "${psql_base[@]}" -f "$here/fixtures/01_baseline_public.sql"
fi

if [ "$skip_migrations" -eq 0 ]; then
  for pass in 1 2; do
    echo "── migrations do financeiro (passagem $pass de 2)"
    for f in "${migrations[@]}"; do
      echo "   $(basename "$f")"
      "${psql_base[@]}" -1 -f "$f"
    done
  done
fi

echo "── suíte finance_rls.test.sql (transação com rollback)"
set +e
PGOPTIONS="${PGOPTIONS:-} -c pixelry.finance_test_harness=on" "${psql_base[@]}" -f "$suite"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "── resultado: todos os $literal casos passaram"
else
  echo "── resultado: FALHOU (psql saiu com código $status). Veja as linhas FALHOU acima." >&2
fi
exit "$status"
