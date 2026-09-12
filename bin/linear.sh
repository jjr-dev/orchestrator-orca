#!/usr/bin/env bash
# Escrita rapida no Linear. Leitura continua sendo `orca linear issue|list-issues`.
#
#   linear.sh create  --team JJR --title "..." --state Draft --label "My Finance"
#   linear.sh create  --batch filhos.json --parent JJR-216
#   linear.sh move    --to "Scheduled" JJR-217 JJR-218
#   linear.sh comment --body-file PLAN.md JJR-217
#   linear.sh label   --add "Queue Jump" --remove "Fast Track" JJR-217
#   linear.sh cache   --refresh --team JJR
#
# Existe so para resolver a chave do jeito que o resto do projeto resolve — o
# porque esta no linear-key.sh. A logica toda mora no linear-api.py.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/linear-key.sh"
export LINEAR_API_KEY
exec python3 "$DIR/linear-api.py" "$@"
