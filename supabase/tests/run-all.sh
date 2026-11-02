#!/usr/bin/env bash
# Roda as três suítes SQL do app móvel no ESTADO INTEGRADO (todas as
# migrations 202611*: CRM, Ponto e Trabalho, Financeiro e a de integração),
# cada uma num Postgres local descartável. Nunca toca em produção.
#
#   supabase/tests/run-all.sh              # tudo
#   supabase/tests/run-all.sh --sem-ponto  # pula a suíte Node do Ponto (npm)
#
# 1. CRM:        tests/run-crm-rls.sh (cluster próprio, só socket Unix)
# 2. Financeiro: tests/finance/run.sh --bootstrap num cluster temporário
#                criado aqui (initdb + pg_ctl, porta TCP livre em localhost)
# 3. Ponto:      cd tests/ponto_trabalho && npm test && npm run test:contract
#                (embedded-postgres; exige `npm ci` uma vez)
#
# Precisa de initdb/pg_ctl/psql 15+ (ex.: brew install postgresql@17; use
# PG_BIN para apontar a pasta dos binários) e, para o Ponto, Node 20+.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skip_ponto=0
for arg in "$@"; do
  case "$arg" in
    --sem-ponto) skip_ponto=1 ;;
    -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "run-all.sh: argumento desconhecido: $arg" >&2; exit 2 ;;
  esac
done

find_bin() {
  local name="$1" dir
  for dir in "${PG_BIN:-}" /usr/local/opt/postgresql@17/bin /opt/homebrew/opt/postgresql@17/bin \
             /usr/local/opt/postgresql@16/bin /opt/homebrew/opt/postgresql@16/bin; do
    [ -n "$dir" ] && [ -x "$dir/$name" ] && { echo "$dir/$name"; return; }
  done
  command -v "$name" || { echo "run-all.sh: $name não encontrado (brew install postgresql@17 ou PG_BIN)" >&2; exit 2; }
}

status=0
echo "════ 1/3 CRM (run-crm-rls.sh)"
if ! "$here/run-crm-rls.sh"; then status=1; echo "run-all.sh: CRM FALHOU" >&2; fi

echo
echo "════ 2/3 Financeiro (finance/run.sh --bootstrap)"
initdb_bin="$(find_bin initdb)"; pg_ctl_bin="$(find_bin pg_ctl)"; psql_bin="$(find_bin psql)"
workdir="$(mktemp -d /tmp/fin-all.XXXXXX)"
cleanup() {
  LC_ALL=C "$pg_ctl_bin" -D "$workdir/data" -m fast -w stop >/dev/null 2>&1 || true
  rm -rf "$workdir"
}
trap cleanup EXIT
"$initdb_bin" -D "$workdir/data" -U postgres -A trust -E UTF8 --no-locale >"$workdir/initdb.log" 2>&1 \
  || { cat "$workdir/initdb.log" >&2; echo "run-all.sh: initdb falhou" >&2; exit 2; }
# Porta livre em localhost: o finance/run.sh só aceita destino local explícito.
port="$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
LC_ALL=C "$pg_ctl_bin" -D "$workdir/data" -l "$workdir/server.log" -w \
  -o "-c listen_addresses=127.0.0.1 -p $port -k '$workdir' -c fsync=off" start >/dev/null \
  || { cat "$workdir/server.log" >&2; echo "run-all.sh: o Postgres local não subiu" >&2; exit 2; }
"$psql_bin" -X -q -h 127.0.0.1 -p "$port" -U postgres -d postgres -c 'create database finance_test' >/dev/null
if ! PATH="$(dirname "$psql_bin"):$PATH" DATABASE_URL="postgres://postgres@127.0.0.1:$port/finance_test" \
     "$here/finance/run.sh" --bootstrap; then status=1; echo "run-all.sh: Financeiro FALHOU" >&2; fi

echo
if [ "$skip_ponto" -eq 1 ]; then
  echo "════ 3/3 Ponto e Trabalho: pulado (--sem-ponto)"
else
  echo "════ 3/3 Ponto e Trabalho (npm test + npm run test:contract)"
  if [ ! -d "$here/ponto_trabalho/node_modules" ]; then
    echo "run-all.sh: rode 'npm ci' em supabase/tests/ponto_trabalho antes (funciona offline com o cache do npm)." >&2
    status=1
  else
    (cd "$here/ponto_trabalho" && npm test && npm run test:contract) || { status=1; echo "run-all.sh: Ponto FALHOU" >&2; }
  fi
fi

echo
if [ "$status" -eq 0 ]; then echo "════ run-all.sh: as três suítes passaram"; else echo "════ run-all.sh: FALHOU" >&2; fi
exit "$status"
