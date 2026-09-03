#!/usr/bin/env bash
# Da nome a aba do terminal do painel em que ESTA sessao esta rodando.
# Sem modelo, custo zero.
#
# Uso: name-terminal.sh "triagem ACME-138"
#
# Por que existe: os terminais do painel nasciam todos sem nome. Com quatro
# automations e mais o chat, davam 8 abas identicas — impossivel saber qual
# sessao era qual sem abrir uma por uma.
#
# COMO ELE SABE QUAL E O SEU: nao sabe, deduz. Nao existe `orca terminal
# current` nem variavel de ambiente com o handle. A sessao que esta rodando este
# comando e, por definicao, a que produziu output agora — entao ela e o
# `max_by(lastOutputAt)` do worktree do painel. E a mesma deducao que o
# /reconcile usa para nao se matar ao fechar terminais velhos.
#
# LIMITE: se duas sessoes do painel arrancarem no mesmo segundo, uma pode
# renomear a aba da outra. O estrago e um titulo errado — cosmetico. Nao use
# esta deducao para nada destrutivo.
set -euo pipefail

TITULO="${1:?uso: name-terminal.sh \"<titulo>\"}"
PAINEL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

HANDLE=$(
  orca terminal list --worktree "path:$PAINEL" --json 2>/dev/null \
  | jq -r '(.result.terminals // []) | map(select(.lastOutputAt != null))
           | if length == 0 then empty else (max_by(.lastOutputAt) | .handle) end'
)

if [ -z "$HANDLE" ]; then
  echo "nao achei terminal do painel para renomear (sigo assim mesmo)" >&2
  exit 0            # nunca derrube a skill por causa de um nome de aba
fi

orca terminal rename --terminal "$HANDLE" --title "$TITULO" --json >/dev/null 2>&1 \
  && echo "aba renomeada: $TITULO" \
  || echo "nao consegui renomear a aba (sigo assim mesmo)" >&2
exit 0
