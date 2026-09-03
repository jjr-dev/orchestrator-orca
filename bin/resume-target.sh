#!/usr/bin/env bash
# Decide se um ticket RETOMA trabalho que ja existe ou COMECA do zero.
# Sem modelo, custo zero. So imprime; nao move nada, nao cria nada.
#
# Uso: resume-target.sh <IDENT>
#
# Saida, uma linha:
#   RESUME    <worktree>  <branch>  <pr-url>   -> despache com --worktree path:<worktree>
#   RECREATE  <repo>      <branch>  <pr-url>   -> worktree sumiu; recrie da propria branch
#   FRESH     primeira-vez                     -> fluxo normal, nunca teve PR
#   FRESH     pr-fechado  <branch-sugerida>    -> PR ja mergeado; branch nova da base atualizada
#
# Por que existe: um ticket que volta para `Draft` depois de ja ter PR e uma
# NOVA LEVA no mesmo escopo, nao um ticket novo. Retomar mantem a revisao que o
# humano ja fez viva no mesmo PR. O `pull-ready` sozinho nao tem como saber
# disso: ele so ve o ticket em `Ready for Agent` e despacharia `new-top-level`,
# cortando branch nova de `origin/<base>` e abrindo PR novo — que e exatamente
# o fluxo ruim que isto substitui.
#
# A fonte da verdade do PR e o ANEXO no Linear, nao a busca por branch: o anexo
# e o link que o proprio worker registrou quando abriu o PR. Buscar por padrao
# de branch acharia PR de outro ticket com numero parecido.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

IDENT="${1:?uso: resume-target.sh <IDENT>}"
NUM="${IDENT##*-}"
[[ "$NUM" =~ ^[0-9]+$ ]] || { echo "IDENT invalido: '$IDENT'" >&2; exit 2; }
TEAM=$(grep -m1 'linear_team:' "$ROOT/registry.yaml" | awk '{print $2}')

# 1. O ticket ja teve PR?
PRURL=$(
  "$DIR/linear-query.sh" "{ issues(filter:{team:{key:{eq:\"$TEAM\"}}, number:{eq:$NUM}}, first:1){ nodes{ attachments{ nodes{ url } } } } }" \
  | jq -r '[.data.issues.nodes[0].attachments.nodes[].url | select(test("/pull/"))] | last // empty'
)
if [ -z "$PRURL" ]; then
  echo "FRESH primeira-vez"
  exit 0
fi

# 2. Esse PR ainda aceita commit?
INFO=$(gh pr view "$PRURL" --json state,headRefName 2>/dev/null || true)
if [ -z "$INFO" ]; then
  echo "FRESH primeira-vez"   # anexo aponta para PR que nao da para ler; trate como novo
  exit 0
fi
ESTADO=$(jq -r '.state' <<<"$INFO")
BRANCH=$(jq -r '.headRefName' <<<"$INFO")

if [ "$ESTADO" != "OPEN" ]; then
  # Mergeado ou fechado: nao da para acrescentar commit. O escopo continua sendo
  # deste ticket, entao a proxima leva sai em branch nova — sufixo incremental
  # para nao colidir com a anterior, que continua existindo no remoto.
  n=2
  while git -C "$ROOT" ls-remote --exit-code --heads origin "${BRANCH%-[0-9]}-$n" >/dev/null 2>&1; do n=$((n+1)); done
  echo "FRESH pr-fechado ${BRANCH}-$n"
  exit 0
fi

# 3. PR aberto. Onde esta o worktree dessa branch?
while IFS= read -r repo; do
  [ -e "$repo/.git" ] || continue
  while IFS=$'\t' read -r wt br; do
    [ "$br" = "$BRANCH" ] || continue
    [ "$wt" = "$repo" ] && continue          # o checkout principal nao serve
    printf 'RESUME %s %s %s\n' "$wt" "$BRANCH" "$PRURL"
    exit 0
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null \
           | awk '/^worktree /{w=$2} /^branch /{b=$2; sub("refs/heads/","",b); print w"\t"b}')
done < <(orca repo list --json | jq -r '.result.repos[].path')

# 4. PR aberto e worktree nao existe mais (GC, ou maquina limpa). Da para
#    recriar da propria branch remota — o codigo esta no PR, nao se perdeu.
REPO=$(
  while IFS= read -r r; do
    git -C "$r" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1 && { echo "$r"; break; }
  done < <(orca repo list --json | jq -r '.result.repos[].path')
)
if [ -n "$REPO" ]; then
  printf 'RECREATE %s %s %s\n' "$REPO" "$BRANCH" "$PRURL"
else
  echo "FRESH primeira-vez"
fi
