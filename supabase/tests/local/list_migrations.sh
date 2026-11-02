#!/usr/bin/env bash
# Lista, em ordem, as migrations do app móvel (CRM, Ponto e Trabalho,
# Financeiro e integração) que os harnesses locais aplicam sobre
# supabase_baseline.sql.
#
#   list_migrations.sh all         todas as 202611*.sql, em ordem de nome
#   list_migrations.sh idempotent  só as que declaram poder ser reaplicadas
#
# Regra da reaplicação (prova de idempotência): tudo, menos as migrations do
# CRM 150000/150100/150200/150400, que criam policies e funções sem
# "if exists" de propósito (a CLI nunca reaplica uma migration já registrada).
# A 150300 (carga inicial) declara ser idempotente e entra na reaplicação.
# O runner do Ponto (run.mjs) repete esta regra em JavaScript.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dir="$(cd "$here/../../migrations" && pwd)"
mode="${1:-all}"
shopt -s nullglob
for f in "$dir"/202611*.sql; do
  case "$mode" in
    all) echo "$f" ;;
    idempotent)
      case "$(basename "$f")" in
        20261101150000_*|20261101150100_*|20261101150200_*|20261101150400_*) ;;
        *) echo "$f" ;;
      esac ;;
    *) echo "list_migrations.sh: modo desconhecido: $mode (use all ou idempotent)" >&2; exit 2 ;;
  esac
done
