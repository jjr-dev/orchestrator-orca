#!/usr/bin/env bash
# A porta unica para registrar trabalho. Resolve o backend e traduz.
#
#   board.sh draft       --team JJR --title "..." --body-file f.md --label "Acme - API" --label high
#   board.sh list-drafts --team JJR
#   board.sh promote     --team JJR <ident...>
#   board.sh move        --to "In Review" <ident...>
#   board.sh comment     --body-file PLAN.md <ident...>
#   board.sh list        --team JJR [--state "Ready for Agent"]
#   board.sh backend     -> qual esta ligado
#
# As skills chamam ISTO, nunca `linear.sh` nem `orca-board.py` direto. E o que
# permite trocar de backend sem reescrever skill nenhuma.
#
# O vocabulario e o do Linear (os 9 nomes de estado), porque era o que ja
# existia escrito em 13 skills. O backend `orca` traduz internamente.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBO="${1:-}"; shift || true
[ -n "$VERBO" ] || { echo "uso: $(basename "$0") <verbo> [args]" >&2; exit 2; }

BACK=$("$DIR/backend.sh") || exit 6
[ "$VERBO" = backend ] && { echo "$BACK"; exit 0; }

if [ "$BACK" = orca ]; then
  exec python3 "$DIR/orca-board.py" "$VERBO" "$@"
fi

# ------------------------------------------------------------------ linear
# Os tres verbos de fluxo nao existem no linear.sh: la eles sao combinacoes de
# estado. Traduzir aqui mantem o linear.sh como porta crua da API.
pega() {  # pega --flag de "$@" sem consumir o resto
  local alvo="$1"; shift
  while [ $# -gt 0 ]; do [ "$1" = "$alvo" ] && { echo "$2"; return; }; shift; done
}

case "$VERBO" in
  draft)
    # No Linear o rascunho JA e um ticket: nasce em `Drafted`, que nenhum cron
    # vigia. E o que deixa o portao durar o tempo que o humano quiser.
    exec "$DIR/linear.sh" create --state "Drafted" "$@"
    ;;

  list-drafts)
    TEAM=$(pega --team "$@")
    [ -n "$TEAM" ] || { echo "board: list-drafts precisa de --team" >&2; exit 2; }
    "$DIR/linear-query.sh" "{ issues(filter:{
      team:{ key:{ eq:\"$TEAM\" } },
      state:{ name:{ eq:\"Drafted\" } },
      labels:{ name:{ eq:\"Queue Jump\" } }
    }, first:50){ nodes{ identifier title parent{ identifier }
      labels{ nodes{ name parent{ name } } } } } }" \
    | python3 -c "
import json,sys
n=json.load(sys.stdin)['data']['issues']['nodes']
def eti(i,g):
    return next((l['name'] for l in i['labels']['nodes']
                 if (l.get('parent') or {}).get('name')==g), None)
print(json.dumps({'drafts':[{
  'identifier':i['identifier'],'title':i['title'],
  'parent':(i.get('parent') or {}).get('identifier'),
  'repo':eti(i,'Repo'),'risk':eti(i,'Risk'),'stack':eti(i,'Stack'),
  'queue_jump':True,
  'fast':any(l['name']=='Fast Track' for l in i['labels']['nodes']),
} for i in n]}, indent=2, ensure_ascii=False))"
    ;;

  promote)
    # Aprovado: sai da sala de espera e entra na fila reivindicada.
    ARGS=(); for a in "$@"; do case "$a" in --team|--title) SKIP=1 ;; *)
      [ "${SKIP:-}" = 1 ] && SKIP= || ARGS+=("$a") ;; esac; done
    [ ${#ARGS[@]} -gt 0 ] || { echo "board: promote precisa de ao menos um ident" >&2; exit 2; }
    exec "$DIR/linear.sh" move --to "Scheduled" "${ARGS[@]}"
    ;;

  create|move|update|comment|label)
    exec "$DIR/linear.sh" "$VERBO" "$@"
    ;;

  list)
    TEAM=$(pega --team "$@"); ESTADO=$(pega --state "$@")
    [ -n "$TEAM" ] || { echo "board: list precisa de --team" >&2; exit 2; }
    if [ -n "$ESTADO" ]; then
      exec orca linear list-issues --team "$TEAM" --state "$ESTADO" --limit 50 --json
    else
      exec orca linear list-issues --team "$TEAM" --limit 50 --json
    fi
    ;;

  *)
    echo "board: verbo '$VERBO' desconhecido" >&2
    echo "  existem: draft list-drafts promote create move update comment label list backend" >&2
    exit 2 ;;
esac
