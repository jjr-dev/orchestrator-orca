#!/usr/bin/env bash
# Responde qual backend registra o trabalho: `linear` ou `orca`.
#
#   backend.sh              -> imprime o nome
#   backend.sh --is orca    -> saida 0 se for, 1 se nao for
#   backend.sh --explica    -> nome + o que isso implica, para humano
#
# So LE. Quem escreve e o `registry-edit.py set-backend`, que e a porta unica
# do registry e prova que a edicao nao vazou para outra chave.
#
# Precisa ser barato: os prechecks do cron chamam isto a cada 2 minutos, antes
# de decidir se acordam um agente.
#
# Nao adivinha. Registry ausente, chave ausente ou valor desconhecido saem com
# codigo proprio (6) e mensagem no stderr — nunca com um palpite. Um palpite
# aqui manda o sistema inteiro falar com o backend errado.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG="${ORCH_REGISTRY:-$(cd "$DIR/.." && pwd)/registry.yaml}"

[ -f "$REG" ] || { echo "backend: $REG nao existe — rode /orc-setup" >&2; exit 6; }

NOME=$(python3 -c "
import sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception as e:
    print(f'registry ilegivel: {e}', file=sys.stderr); sys.exit(6)
v = ((d.get('defaults') or {}).get('backend') or '').strip().lower()
if v not in ('linear', 'orca'):
    print(f\"defaults.backend e '{v or 'ausente'}'; esperado 'linear' ou 'orca'\", file=sys.stderr)
    sys.exit(6)
print(v)
" "$REG") || { echo "backend: nao consegui determinar o backend" >&2; exit 6; }

case "${1:-}" in
  --is)      [ "$NOME" = "${2:?uso: --is linear|orca}" ] ;;
  --explica)
    echo "$NOME"
    if [ "$NOME" = linear ]; then
      echo "  ticket, estado e etiquetas no Linear; board e cronjobs ativos" >&2
    else
      echo "  spec, pai/filho e status no proprio Orca; fluxo pelo chat, sem board" >&2
    fi ;;
  "")        echo "$NOME" ;;
  *)         echo "uso: $(basename "$0") [--is linear|orca | --explica]" >&2; exit 2 ;;
esac
