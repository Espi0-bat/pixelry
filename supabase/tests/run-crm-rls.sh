#!/usr/bin/env bash
# Roda os testes de RLS do CRM numa transação que termina em ROLLBACK.
#
#   supabase/tests/run-crm-rls.sh                 # projeto linkado (padrão)
#   supabase/tests/run-crm-rls.sh --local         # Supabase local (docker)
#   supabase/tests/run-crm-rls.sh --db-url <url>  # outro banco
#
# O lote enviado é:
#   begin;
#   <as migrations 20261101150*_crm_*.sql, como estão no repositório>
#   <supabase/tests/crm_rls.test.sql>
#   rollback;
# As migrations entram byte a byte: o teste só vale se reproduzir exatamente o
# que o push vai aplicar (ver 20260903175521_revert_harden_helper_fn_execute).
#
# No projeto linkado a transação segura locks em profiles e leads por alguns
# segundos e é desfeita no fim; nada fica gravado. Sai com código 1 se algum
# teste falhar.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
target=("$@")
if [ ${#target[@]} -eq 0 ]; then
  target=(--linked)
  if [ -n "${SUPABASE_PROJECT_REF:-}" ]; then
    target+=(--project-ref "$SUPABASE_PROJECT_REF")
  fi
fi

batch="$(mktemp -t crm-rls.XXXXXX)"
trap 'rm -f "$batch"' EXIT

{
  echo 'begin;'
  for f in "$root"/supabase/migrations/20261101150*_crm_*.sql; do
    printf '\n-- >>> %s\n' "$(basename "$f")"
    cat "$f"
  done
  printf '\n-- >>> crm_rls.test.sql\n'
  cat "$here/crm_rls.test.sql"
  printf '\nrollback;\n'
} > "$batch"

out="$(cd "$root" && supabase db query "${target[@]}" --output-format json --file "$batch" 2>/dev/null)"

python3 -I - "$out" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    data = json.loads(raw)
except ValueError:
    print(raw)
    sys.exit(1)
rows = data.get("rows") if isinstance(data, dict) else None
if not rows or "resultado" not in rows[0]:
    print(raw)
    sys.exit(1)
falhas = [r for r in rows if r["resultado"] != "PASSOU"]
for r in rows:
    marca = "ok  " if r["resultado"] == "PASSOU" else "FALHOU"
    linha = f"{marca} {r['n']:>3}  {r['test']}"
    if r["resultado"] != "PASSOU":
        linha += f"\n           esperado: {r['expected']}\n           obtido:   {r['actual']}"
    print(linha)
print(f"\n{len(rows) - len(falhas)}/{len(rows)} passaram")
sys.exit(1 if falhas else 0)
PY
