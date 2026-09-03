#!/usr/bin/env bash
# Precheck da automation de triagem.
# Sai 0 se existe ticket parado em "Draft" esperando ser redigido.
# Uso: has-triage.sh <linear_team_key>
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAM="${1:?informe a team key do Linear, ex: ACME}"

[ -f "$DIR/../PAUSE" ] && exit 1

# Guarda de sobreposicao.
#
# O precheck e level-triggered: ele so para de ver o ticket quando a skill o move
# de "Draft" para "Drafting". A skill faz esse claim logo no inicio, mas existe
# uma janela entre o dispatch e o claim — subir a sessao, carregar a skill, achar
# o ticket. Se essa janela passar do intervalo do cron, a automation despacha uma
# SEGUNDA triagem no mesmo ticket. Aconteceu em 30/07: tres rodando juntas.
#
# O lock cobre exatamente essa janela, e nada alem dela. TTL curto de proposito:
# depois disso ou o ticket ja saiu de "Draft" (e a propria consulta resolve), ou
# a sessao morreu e despachar de novo e o certo.
LOCK_TTL=180
LOCK="$DIR/../state/triage.lock"
mkdir -p "$DIR/../state"
if [ -f "$LOCK" ]; then
  now=$(date +%s)
  mtime=$(stat -f %m "$LOCK" 2>/dev/null || stat -c %Y "$LOCK" 2>/dev/null || echo 0)
  [ $(( now - mtime )) -lt "$LOCK_TTL" ] && exit 1
fi

# O estado E o claim. Nao ha etiqueta para filtrar aqui — nem "Drafted" (virou o
# estado final da triagem) nem "Fast Track" (esse nunca passa por "Draft": o
# humano manda direto para "Ready for Agent").
#
# Um ticket com "Fast Track" largado em "Draft" e triado normalmente, de
# proposito: a coluna e a intencao. Excluir por etiqueta faria o card sumir da
# fila sem ninguem perceber, que e a classe de falha que este sistema mais sofre.
read -r -d '' Q <<QUERY || true
{
  issues(filter: {
    team: { key: { eq: "$TEAM" } }
    state: { name: { eq: "Draft" } }
  }, first: 50) {
    nodes { id identifier }
  }
}
QUERY

# `set +e` em volta para preservar o codigo de saida real: 1 = fila vazia,
# 4 = chave ausente, 5 = chave invalida. Um `if` colapsaria 4 e 5 em 1 e a gente
# perderia o diagnostico.
set +e
"$DIR/linear-query.sh" "$Q" \
  | jq -e '.data.issues.nodes | length > 0' \
  > /dev/null
rc=$?
set -e

# So segura o lock quando VAI despachar. Erro de chave nao deve travar a fila.
[ "$rc" -eq 0 ] && touch "$LOCK"
exit "$rc"
