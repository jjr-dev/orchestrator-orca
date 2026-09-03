#!/usr/bin/env bash
# Precheck da automation de execucao.
# Sai 0 se existe pelo menos um ticket elegivel; 1 caso contrario.
# Uso: has-ready.sh <linear_team_key>
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM="${1:?informe a team key do Linear, ex: ACME}"

[ -f "$DIR/../PAUSE" ] && exit 1

# Guarda de sobreposicao. Mesma razao do has-triage.sh, e aqui o risco e MAIOR:
# o claim do pull-ready (mover para "Scheduled") so acontece no Passo 4, depois
# de reconciliar, avaliar o DoR de cada ticket e checar capacidade. Ate la o
# ticket continua em "Ready for Agent" e o precheck continua vendo — duas
# sessoes reclamariam o mesmo ticket.
LOCK_TTL=180
LOCK="$DIR/../state/pull.lock"
mkdir -p "$DIR/../state"
if [ -f "$LOCK" ]; then
  now=$(date +%s)
  mtime=$(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || echo 0)
  [ $(( now - mtime )) -lt "$LOCK_TTL" ] && exit 1
fi

read -r -d '' Q <<QUERY || true
{
  issues(filter: {
    team: { key: { eq: "$TEAM" } }
    state: { name: { eq: "Ready for Agent" } }
  }, first: 50) {
    nodes { id identifier labels { nodes { name parent { name } } } }
  }
}
QUERY

# A API devolve o nome da etiqueta SEM o prefixo do grupo ("Acme - API"),
# com o grupo numa relacao parent separada. O "Repo/" so existe na interface.
# Por isso filtramos por parent.name, nao por startswith("Repo/").
# `set +e` em volta para preservar o codigo real: 1 = fila vazia, 4 = chave
# ausente, 5 = chave invalida. Um `if` colapsaria tudo em 1.
set +e
"$DIR/linear-query.sh" "$Q" \
  | jq -e '[.data.issues.nodes[] | select(any(.labels.nodes[]; .parent.name == "Repo"))] | length > 0' \
  > /dev/null
rc=$?
set -e

# So segura o lock quando VAI despachar.
[ "$rc" -eq 0 ] && touch "$LOCK"
exit "$rc"
