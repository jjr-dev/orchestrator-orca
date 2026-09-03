#!/usr/bin/env bash
# Espelha o ticket do Linear na metadata do worktree no Orca: nome legivel,
# link do ticket e status do board. Sem modelo, custo zero.
#
# Uso:
#   sync-worktree-meta.sh              # varre todos os worktrees de ticket
#   sync-worktree-meta.sh ACME-140      # so este
#
# Diferente do cleanup-worktrees.sh e do sync-parent-status.sh, este NAO tem
# dry-run: ele so escreve metadata do Orca (nome de aba, link, coluna do board).
# Nada aqui apaga codigo nem muda estado no Linear, entao exigir --apply so
# atrapalharia o worker, que chama isto a cada mudanca de estado.
#
# Por que existe:
#   - `displayName` nascia como o slug da branch (`acme-140-checkout-recorrente`), que
#     nao diz de que ticket e nem o que faz.
#   - `linkedLinearIssue` estava NULO em TODOS os worktrees (medido em 29/08).
#     O Orca preenche `linkedPR` sozinho, mas o link do ticket nunca era setado.
#   - `workspaceStatus` ficava preso em `in-progress` para sempre, entao o quadro
#     do Orca nao dizia nada.
#
# A fonte da verdade e o estado no Linear, sempre. Este script nunca decide nada:
# le e espelha.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
TEAM=$(grep -m1 'linear_team:' "$ROOT/registry.yaml" | awk '{print $2}')
[ -n "$TEAM" ] || { echo "nao achei linear_team no registry.yaml" >&2; exit 2; }

board() {
  case "$1" in
    "In Progress")                      echo in-progress ;;
    "In Review"|"Manual QA")            echo in-review ;;
    "Done"|"Canceled"|"Duplicate")      echo completed ;;
    *)                                  echo todo ;;   # rascunho, fila, Scheduled
  esac
}

PREFIX_RE="^.*/$(printf '%s' "$TEAM" | tr '[:upper:]' '[:lower:]')-([0-9]+)-"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
: > "$TMP/wt"

while IFS= read -r repo; do
  [ -e "$repo/.git" ] || continue
  git -C "$repo" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{w=$2} /^branch /{b=$2; sub("refs/heads/","",b); print w"\t"b}' \
    | while IFS=$'\t' read -r wt br; do
        [ "$wt" = "$repo" ] && continue
        [[ "$br" =~ $PREFIX_RE ]] || continue
        printf '%s\t%s\n' "$wt" "${BASH_REMATCH[1]}" >> "$TMP/wt"
      done
done < <(orca repo list --json | jq -r '.result.repos[].path')

if [ $# -gt 0 ]; then
  : > "$TMP/f"
  for a in "$@"; do awk -F'\t' -v n="${a##*-}" '$2==n' "$TMP/wt" >> "$TMP/f"; done
  mv "$TMP/f" "$TMP/wt"
fi
[ -s "$TMP/wt" ] || { echo "nenhum worktree de ticket encontrado"; exit 0; }

NUMS=$(cut -f2 "$TMP/wt" | sort -un | paste -sd, -)
"$DIR/linear-query.sh" "{ issues(filter:{team:{key:{eq:\"$TEAM\"}}, number:{in:[$NUMS]}}, first:250){ nodes{ number identifier title state{name} } } }" \
  | jq -r '.data.issues.nodes[] | [.number, .identifier, .state.name, .title] | @tsv' > "$TMP/tk" 2>/dev/null || : > "$TMP/tk"
[ -s "$TMP/tk" ] || { echo "consulta ao Linear falhou — nada alterado" >&2; exit 2; }

N=0
while IFS=$'\t' read -r wt num; do
  linha=$(awk -F'\t' -v n="$num" '$1==n {print; exit}' "$TMP/tk")
  [ -n "$linha" ] || { echo "  $(basename "$wt")  -> ticket $TEAM-$num nao existe mais, pulando"; continue; }
  IFS=$'\t' read -r _ ident estado titulo <<< "$linha"
  nome="$ident · $titulo"
  [ ${#nome} -gt 60 ] && nome="${nome:0:57}..."
  if orca worktree set --worktree "path:$wt" \
       --display-name "$nome" --linear-issue "$ident" \
       --workspace-status "$(board "$estado")" --json >/dev/null 2>&1; then
    printf '  %-22s %-14s %s\n' "$ident" "$(board "$estado")" "$nome"
    N=$((N+1))
  else
    printf '  %-22s FALHOU ao gravar metadata\n' "$ident"
  fi
done < "$TMP/wt"

echo "$N worktree(s) sincronizado(s)"
