#!/usr/bin/env bash
# Remove worktrees de ticket que ja fecharam o ciclo inteiro, e as pastas de
# anexo dos tickets que fecharam.
#
# DRY RUN por padrao. Passe --apply para remover de verdade.
#
# Uso:
#   bin/cleanup-worktrees.sh                 # so lista o que sairia
#   bin/cleanup-worktrees.sh --apply         # remove
#   bin/cleanup-worktrees.sh --prefix foo/   # outro padrao de branch
#
# Por que um script e nao a skill fazendo na mao:
# as quatro condicoes abaixo sao objetivas e nao precisam de julgamento. Script
# e auditavel, idempotente e testavel; agente decidindo worktree a worktree, toda
# manha, e uma chance por dia de errar. A skill so chama isto e reporta a saida.
#
# As QUATRO condicoes, todas obrigatorias:
#   1. `git status --short` vazio        -> nada por commitar
#   2. nenhum commit local fora do remoto -> nada por perder
#   3. PR daquela branch esta MERGED     -> o codigo esta na base
#   4. ticket do Linear esta Done        -> o ciclo fechou
#
# Os anexos baixados pelo `linear-assets.sh` saem por regra propria, no fim: so
# o estado do ticket importa (Done, ou sumiu do Linear). Nao ha o que perder —
# o arquivo veio do Linear e se baixa de novo.
#
# A condicao 2 e a unica com sutileza. O teste e
# `git log HEAD --not --remotes`: lista commit alcancavel pelo HEAD e por
# NENHUMA ref remota. Vazio = tudo que existe aqui existe no servidor.
#
# NAO compare `HEAD == headRefOid do PR`. O worktree local costuma ficar ATRAS
# do PR (alguem empurrou commit depois, pela UI ou de outra maquina), e igualdade
# reprovaria um caso perfeitamente seguro — medido: 3 dos 43 worktrees.
#
# NAO use `git merge-base --is-ancestor HEAD origin/<base>` como teste unico:
# com squash merge, que e o recomendado aqui, a branch nunca vira ancestral da
# base, e isso daria falso negativo em TUDO.
#
# Quando a ref remota da branch ja foi podada e o merge foi squash, o teste
# acima acusa. Por isso existe o segundo caminho: se o SHA que o PR mergeou
# ainda existe localmente e `git log <pr>..HEAD` e vazio, esta contido.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

APPLY=0
PREFIX_RE=''          # vazio = derivar da team key (ver abaixo)
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)  APPLY=1; shift ;;
    --prefix) PREFIX_RE="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

TEAM=$(grep -m1 'linear_team:' "$ROOT/registry.yaml" | awk '{print $2}')
[ -n "$TEAM" ] || { echo "nao achei linear_team no registry.yaml" >&2; exit 2; }

# O padrao sai da propria team key, entao o script serve qualquer instalacao sem
# edicao: time ACME -> branch `<namespace>/acme-<N>-<slug>`. O `.*/` engole o
# namespace que o Orca usa (`acme-dev/`, `feat/`, o que for).
#
# Branch sem numero de ticket (`acme-dev/ajuste-form`, `feat/tema`) nao casa, e e
# exatamente o que queremos: worktree criado na mao nunca entra nesta limpeza.
if [ -z "$PREFIX_RE" ]; then
  PREFIX_RE="^.*/$(printf '%s' "$TEAM" | tr '[:upper:]' '[:lower:]')-([0-9]+)-"
fi

# ---------------------------------------------------------------- coleta ----
# Uma passada por todos os worktrees, guardando so os que casam com o padrao.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
: > "$TMP/cand"

while IFS= read -r repo; do
  [ -d "$repo/.git" ] || [ -f "$repo/.git" ] || continue
  git -C "$repo" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{w=$2} /^branch /{b=$2; sub("refs/heads/","",b); print w"\t"b}' \
    | while IFS=$'\t' read -r wt br; do
        [ "$wt" = "$repo" ] && continue          # nunca o checkout principal
        [[ "$br" =~ $PREFIX_RE ]] || continue
        printf '%s\t%s\t%s\t%s\n' "$repo" "$wt" "$br" "${BASH_REMATCH[1]}" >> "$TMP/cand"
      done
done < <(orca repo list --json | jq -r '.result.repos[].path')

TOTAL=$(wc -l < "$TMP/cand" | tr -d ' ')
[ "$TOTAL" -eq 0 ] && echo "nenhum worktree casa com o padrao $PREFIX_RE"

if [ "$TOTAL" -gt 0 ]; then

# --------------------------------------------- estado dos tickets, em LOTE --
NUMS=$(cut -f4 "$TMP/cand" | sort -un | paste -sd, -)
"$DIR/linear-query.sh" "{ issues(filter: {team:{key:{eq:\"$TEAM\"}}, number:{in:[$NUMS]}}, first:250){ nodes{ identifier number state{name} } } }" \
  | jq -r '.data.issues.nodes[] | "\(.number)\t\(.state.name)"' > "$TMP/tickets" 2>/dev/null || : > "$TMP/tickets"

# ------------------------------------------------ PRs merged, um gh por repo --
: > "$TMP/prs"
cut -f1 "$TMP/cand" | sort -u | while IFS= read -r repo; do
  gh pr list --state merged --limit 300 --json headRefName,headRefOid \
     --repo "$(git -C "$repo" remote get-url origin | sed -E 's#^.*[:/]([^/]+/[^/]+)$#\1#; s#\.git$##')" \
     2>/dev/null \
    | jq -r --arg r "$repo" '.[] | "\($r)\t\(.headRefName)\t\(.headRefOid)"' >> "$TMP/prs" || true
done

# --------------------------------------------------------------- decisao ----
printf '%-16s %-42s %-9s %s\n' REPO BRANCH TICKET SITUACAO
printf '%-16s %-42s %-9s %s\n' '---' '---' '---' '---'
SAFE=0
while IFS=$'\t' read -r repo wt br num; do
  motivo=""
  [ -n "$(git -C "$wt" status --short 2>/dev/null)" ] && motivo="sem commitar"

  proid=$(awk -F'\t' -v r="$repo" -v b="$br" '$1==r && $2==b {print $3; exit}' "$TMP/prs")
  if [ -z "$motivo" ] && [ -z "$proid" ]; then
    motivo="PR nao mergeado"
  fi

  # Condicao 2: nenhum commit local fora do remoto.
  if [ -z "$motivo" ]; then
    if [ -n "$(git -C "$wt" log HEAD --not --remotes --oneline 2>/dev/null | head -1)" ]; then
      if git -C "$wt" cat-file -e "$proid^{commit}" 2>/dev/null \
         && [ -z "$(git -C "$wt" log "$proid..HEAD" --oneline 2>/dev/null | head -1)" ]; then
        :   # contido no que o PR mergeou
      else
        motivo="commit local fora do remoto"
      fi
    fi
  fi

  st=$(awk -F'\t' -v n="$num" '$1==n {print $2; exit}' "$TMP/tickets")
  if [ -z "$motivo" ] && [ "$st" != "Done" ]; then
    motivo="ticket em ${st:-?}"
  fi

  if [ -z "$motivo" ]; then
    SAFE=$((SAFE+1))
    printf '%-16s %-42s %-9s %s\n' "$(basename "$repo")" "$br" "$TEAM-$num" "SEGURO"
    if [ "$APPLY" -eq 1 ]; then
      orca worktree rm --worktree "path:$wt" --force --json >/dev/null 2>&1 \
        && echo "                 -> removido" \
        || echo "                 -> FALHOU ao remover"
    fi
  else
    printf '%-16s %-42s %-9s %s\n' "$(basename "$repo")" "$br" "$TEAM-$num" "manter: $motivo"
  fi
done < "$TMP/cand"

fi   # fim do bloco de worktrees

# ----------------------------------------------- anexos de ticket ja fechado --
# Segunda fonte de acumulo, e independente da primeira: a triagem baixa anexo de
# QUALQUER ticket em Draft, inclusive de ticket que nunca vira worktree. Por isso
# a lista de pastas aqui nao e a mesma dos candidatos acima e precisa da propria
# consulta ao Linear.
#
# Teste unico: o ticket esta `Done`, ou sumiu do Linear. Nao ha o que perder —
# o arquivo veio do Linear e o `linear-assets.sh` baixa de novo quando preciso.
AGC=0
AROOT="$("$(dirname "${BASH_SOURCE[0]}")/assets-root.sh")"
ADIRS=$(find "$AROOT" -mindepth 1 -maxdepth 1 -type d -name "$TEAM-*" 2>/dev/null | sort || true)

if [ -n "$ADIRS" ]; then
  : > "$TMP/anums"
  while IFS= read -r d; do
    n="$(basename "$d")"; n="${n##*-}"
    [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" >> "$TMP/anums"
  done <<< "$ADIRS"

  # A consulta e limitada a 250. Passar disso truncaria a resposta e faria um
  # ticket vivo parecer "sumiu do Linear" — o que apagaria anexo em uso. Com o
  # corte, o excedente sai nas proximas passagens.
  ANUMS=$(sort -un "$TMP/anums" | head -250 | paste -sd, -)

  if [ -n "$ANUMS" ]; then
    "$DIR/linear-query.sh" "{ issues(filter: {team:{key:{eq:\"$TEAM\"}}, number:{in:[$ANUMS]}}, first:250){ nodes{ number state{name} } } }" \
      | jq -r '.data.issues.nodes[] | "\(.number)\t\(.state.name)"' > "$TMP/atickets" 2>/dev/null || : > "$TMP/atickets"

    # Resposta vazia com pedido nao-vazio e falha de rede ou de chave, nao
    # "todos os tickets sumiram". Nesse caso nao apague nada.
    if [ -s "$TMP/atickets" ]; then
      sort -un "$TMP/anums" | head -250 > "$TMP/aconsultados"
      echo
      printf '%-14s %s\n' ANEXOS SITUACAO
      printf '%-14s %s\n' '---' '---'
      while IFS= read -r d; do
        n="$(basename "$d")"; n="${n##*-}"
        [[ "$n" =~ ^[0-9]+$ ]] || continue
        grep -qx "$n" "$TMP/aconsultados" || continue     # ficou fora do corte de 250
        st=$(awk -F'\t' -v n="$n" '$1==n {print $2; exit}' "$TMP/atickets")
        if [ "$st" = "Done" ]; then
          sit="SEGURO"
        elif [ -z "$st" ]; then
          sit="SEGURO (ticket sumiu do Linear)"
        else
          sit="manter: ticket em $st"
        fi
        printf '%-14s %s\n' "$(basename "$d")" "$sit"
        if [ "${sit#SEGURO}" != "$sit" ]; then
          AGC=$((AGC+1))
          if [ "$APPLY" -eq 1 ]; then
            rm -rf "$d" && echo "               -> removido" \
                        || echo "               -> FALHOU ao remover"
          fi
        fi
      done <<< "$ADIRS"
    else
      echo "anexos: consulta ao Linear falhou — nada removido" >&2
    fi
  fi
fi

echo
echo "$TOTAL do orquestrador · $SAFE seguros para remover · $AGC pasta(s) de anexo"
[ "$APPLY" -eq 0 ] && { [ "$SAFE" -gt 0 ] || [ "$AGC" -gt 0 ]; } && echo "DRY RUN — rode com --apply para remover"
exit 0
