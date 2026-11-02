#!/usr/bin/env bash
# Testes de RLS, travas, auditoria, carga inicial e concorrência do CRM.
#
#   supabase/tests/run-crm-rls.sh                    # PADRÃO: Postgres local descartável
#   supabase/tests/run-crm-rls.sh --db-url <url>     # servidor local já rodando (ex.: supabase start)
#   supabase/tests/run-crm-rls.sh --linked           # projeto linkado: exige confirmação
#
# Padrão (local): cria um cluster Postgres numa pasta temporária, só com
# socket Unix (sem porta TCP), e apaga tudo no fim. Precisa de initdb,
# pg_ctl e psql 15+ (ex.: brew install postgresql@17). Use PG_BIN para
# apontar a pasta dos binários.
#
# --db-url: cria um banco descartável no servidor indicado e o apaga no fim.
# Só aceita servidor local (localhost, 127.0.0.1, ::1 ou socket).
#
# Nos dois modos locais roda, em ordem:
#   1. tests/local/supabase_baseline.sql   plataforma Supabase + profiles/leads
#   2. tests/local/existing_data.sql       dados de antes do CRM
#   3. migrations 20261101150*_crm_*.sql   cada uma na sua transação, como o push
#   4. a migration 4/5 de novo             a carga inicial não pode duplicar
#   5. crm_rls.test.sql                    entre begin e rollback
#   6. crm_backfill.test.sql
#   7. crm_concurrency.test.sql            duas conexões via dblink
#
# --linked: roda SÓ o crm_rls.test.sql, entre begin e rollback, contra o
# projeto linkado (é o que a primeira entrega fazia). Segura locks em
# profiles e leads por alguns segundos. Os testes de carga e de concorrência
# gravam dados e nunca rodam em produção. Exige confirmação: digitar o
# project ref no terminal, ou CRM_RLS_CONFIRMAR_PRODUCAO=<project ref> quando
# não houver terminal. Project ref: --project-ref ou SUPABASE_PROJECT_REF.
#
# Sai com código 1 se algum teste falhar.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
migrations=("$root"/supabase/migrations/20261101150*_crm_*.sql)
link_migration="$root/supabase/migrations/20261101150300_crm_link_existing_data.sql"

mode=ephemeral
db_url=""
project_ref="${SUPABASE_PROJECT_REF:-}"

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "erro: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --db-url) [ $# -ge 2 ] || die "--db-url precisa de um valor"; mode=db_url; db_url="$2"; shift 2 ;;
    --linked) mode=linked; shift ;;
    --project-ref) [ $# -ge 2 ] || die "--project-ref precisa de um valor"; project_ref="$2"; shift 2 ;;
    --local) die "--local não é usado: o padrão já é local (cluster descartável). Para 'supabase start', use --db-url postgresql://postgres:postgres@127.0.0.1:54322/postgres" ;;
    -h|--help) usage; exit 0 ;;
    *) die "opção desconhecida: $1 (veja --help)" ;;
  esac
done

# ── Saída dos testes ─────────────────────────────────────────────────────────
# Cada arquivo de teste termina com linhas marcador|n|resultado|teste|esperado|obtido.
total=0
failed=0
# Roda no shell principal (sem pipe), para os contadores valerem no fim.
report() { # $1 = nome do arquivo, stdin = saída do psql (-At, separador \x1f)
  local name="$1" line n result test expected actual count=0
  echo "── $name"
  while IFS=$'\x1f' read -r marker n result test expected actual; do
    [ "$marker" = "CRMTEST" ] || continue
    count=$((count + 1)); total=$((total + 1))
    if [ "$result" = "PASSOU" ]; then
      printf 'ok     %3s  %s\n' "$n" "$test"
    else
      failed=$((failed + 1))
      printf 'FALHOU %3s  %s\n           esperado: %s\n           obtido:   %s\n' "$n" "$test" "$expected" "$actual"
    fi
  done
  [ "$count" -gt 0 ] || { echo "nenhum resultado lido de $name" >&2; failed=$((failed + 1)); }
}

# ── Modo linkado (produção) ─────────────────────────────────────────────────
if [ "$mode" = linked ]; then
  [ -n "$project_ref" ] || die "--linked precisa de --project-ref ou SUPABASE_PROJECT_REF"
  echo "ATENÇÃO: isto roda contra o projeto linkado '$project_ref' (produção)." >&2
  echo "As migrations do CRM e os testes entram numa transação desfeita no fim," >&2
  echo "mas profiles e leads ficam travadas enquanto ela durar." >&2
  if [ -n "${CRM_RLS_CONFIRMAR_PRODUCAO:-}" ]; then
    [ "$CRM_RLS_CONFIRMAR_PRODUCAO" = "$project_ref" ] \
      || die "CRM_RLS_CONFIRMAR_PRODUCAO não confere com o project ref"
  elif [ -t 0 ]; then
    printf 'Digite o project ref para confirmar: ' >&2
    read -r typed
    [ "$typed" = "$project_ref" ] || die "confirmação não confere; nada foi executado"
  else
    die "sem terminal para confirmar; defina CRM_RLS_CONFIRMAR_PRODUCAO=$project_ref"
  fi

  batch="$(mktemp -t crm-rls.XXXXXX)"
  trap 'rm -f "$batch"' EXIT
  {
    echo 'begin;'
    for f in "${migrations[@]}"; do printf '\n-- >>> %s\n' "$(basename "$f")"; cat "$f"; done
    printf '\n-- >>> crm_rls.test.sql\n'; cat "$here/crm_rls.test.sql"
    printf '\nrollback;\n'
  } > "$batch"
  out="$(cd "$root" && supabase db query --linked --project-ref "$project_ref" \
    --output-format json --file "$batch" 2>/dev/null)"
  printf '%s' "$out" | python3 -I -c '
import json, sys
data = json.load(sys.stdin)
rows = data.get("rows") if isinstance(data, dict) else None
if not rows or "resultado" not in rows[0]:
    print(json.dumps(data)[:2000], file=sys.stderr); sys.exit(1)
for r in rows:
    print("\x1f".join("" if r.get(k) is None else str(r.get(k)) for k in ("marcador", "n", "resultado", "test", "expected", "actual")))
' > "$batch.out" || failed=$((failed + 1))
  report "crm_rls.test.sql (linkado)" < "$batch.out"
  rm -f "$batch.out"
  echo; echo "$((total - failed))/$total passaram"
  [ "$failed" -eq 0 ]
  exit
fi

# ── Modos locais ─────────────────────────────────────────────────────────────
find_bin() {
  local name="$1" dir
  for dir in "${PG_BIN:-}" /usr/local/opt/postgresql@17/bin /opt/homebrew/opt/postgresql@17/bin \
             /usr/local/opt/postgresql@16/bin /opt/homebrew/opt/postgresql@16/bin; do
    [ -n "$dir" ] && [ -x "$dir/$name" ] && { echo "$dir/$name"; return; }
  done
  command -v "$name" || die "$name não encontrado. Instale o Postgres (brew install postgresql@17) ou defina PG_BIN."
}

psql_bin="$(find_bin psql)"
export PGCLIENTENCODING=UTF8
# O socket Unix fica em $workdir; no macOS o caminho do socket tem ~103 bytes.
workdir="$(mktemp -d "${TMPDIR:-/tmp}/crm-rls.XXXXXX")"
if [ "${#workdir}" -gt 80 ]; then rmdir "$workdir"; workdir="$(mktemp -d /tmp/crm-rls.XXXXXX)"; fi
cleanup_cmds=("rm -rf '$workdir'")
cleanup() { local i; for ((i=${#cleanup_cmds[@]}-1; i>=0; i--)); do eval "${cleanup_cmds[$i]}" >/dev/null 2>&1 || true; done; }
trap cleanup EXIT

test_db="crm_rls_$(date +%s)_$$"

if [ "$mode" = ephemeral ]; then
  initdb_bin="$(find_bin initdb)"; pg_ctl_bin="$(find_bin pg_ctl)"
  "$initdb_bin" -D "$workdir/data" -U postgres -A trust -E UTF8 --no-locale >"$workdir/initdb.log" 2>&1 \
    || { cat "$workdir/initdb.log" >&2; die "initdb falhou"; }
  port=54329
  # No macOS o postmaster recusa subir sem um locale válido em LC_ALL
  # ("postmaster became multithreaded during startup").
  LC_ALL=C "$pg_ctl_bin" -D "$workdir/data" -l "$workdir/server.log" -w \
    -o "-c listen_addresses='' -k '$workdir' -p $port -c fsync=off -c max_connections=20" start >/dev/null \
    || { cat "$workdir/server.log" >&2; die "o Postgres local não subiu"; }
  cleanup_cmds+=("'$pg_ctl_bin' -D '$workdir/data' -m fast -w stop")
  admin_conn="host=$workdir port=$port user=postgres dbname=postgres"
  test_conn="host=$workdir port=$port user=postgres dbname=$test_db"
else
  host="$(python3 -I -c 'import sys, urllib.parse as u; print(u.urlsplit(sys.argv[1]).hostname or "")' "$db_url")"
  case "$host" in
    ""|localhost|127.0.0.1|::1) ;;
    *) die "--db-url só aceita servidor local (recebido: $host). Produção só com --linked." ;;
  esac
  admin_conn="$db_url"
  test_conn="$(python3 -I -c 'import sys, urllib.parse as u
p = u.urlsplit(sys.argv[1]); print(u.urlunsplit(p._replace(path="/" + sys.argv[2])))' "$db_url" "$test_db")"
fi

psql_run() { "$psql_bin" -X -q -v ON_ERROR_STOP=1 "$@"; }

psql_run "$admin_conn" -c "create database $test_db" >/dev/null
cleanup_cmds+=("'$psql_bin' -X -q '$admin_conn' -c 'drop database if exists $test_db with (force)'")
[ "$("$psql_bin" -X -At "$test_conn" -c 'select current_setting($$server_version_num$$)::int >= 150000')" = t ] \
  || die "é preciso Postgres 15 ou mais novo (security_invoker nas views)"

step() { printf '→ %s\n' "$1"; }
apply() { # $1 = arquivo; aplica numa transação só
  psql_run "$test_conn" --single-transaction -f "$1" >"$workdir/apply.log" 2>&1 \
    || { cat "$workdir/apply.log" >&2; die "falhou ao aplicar $(basename "$1")"; }
}
run_test() { # $1 = nome no relatório, $2 = arquivo; demais args vão para o psql
  local name="$1" file="$2"; shift 2
  if ! psql_run "$test_conn" -At -F $'\x1f' "$@" -f "$file" >"$workdir/test.out" 2>"$workdir/test.err"; then
    cat "$workdir/test.err" >&2
    echo "erro ao rodar $name" >&2
    failed=$((failed + 1))
  fi
  report "$name" < "$workdir/test.out"
}

step "base local (plataforma Supabase + profiles/leads)"; apply "$here/local/supabase_baseline.sql"
step "dados de antes do CRM";                          apply "$here/local/existing_data.sql"
for f in "${migrations[@]}"; do step "$(basename "$f")"; apply "$f"; done
step "$(basename "$link_migration") de novo (carga idempotente)"; apply "$link_migration"

{ echo 'begin;'; cat "$here/crm_rls.test.sql"; echo; echo 'rollback;'; } > "$workdir/crm_rls.sql"
echo
run_test "crm_rls.test.sql" "$workdir/crm_rls.sql"
run_test "crm_backfill.test.sql" "$here/crm_backfill.test.sql"
run_test "crm_concurrency.test.sql" "$here/crm_concurrency.test.sql" -v conninfo="$test_conn"

echo; echo "$((total - failed))/$total passaram"
[ "$failed" -eq 0 ]
