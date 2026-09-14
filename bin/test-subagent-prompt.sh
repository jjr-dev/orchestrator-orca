#!/usr/bin/env bash
# Teste do subagent-prompt.sh nos dois backends.
#
# O que importa: o prompt precisa conter TUDO que o subagente nao tem como
# buscar sozinho — ele roda no worktree do cliente, onde os scripts do
# orquestrador nao existem. Campo faltando nao da erro: o planner so planeja
# pior, e ninguem percebe.
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$RAIZ" || exit 1
TEAM="${1:-JJR}"

OK=0; F=0
passa(){ OK=$((OK+1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
falha(){ F=$((F+1)); printf '  \033[31mFALHA\033[0m %s\n' "$1"; [ -n "${2:-}" ] && echo "         $2"; }

BACK_ANTES=$(./bin/backend.sh 2>/dev/null || echo linear)
IDS=""
limpa(){
  for u in $IDS; do ./bin/linear-query.sh "mutation{ issueDelete(id:\"$u\"){success} }" >/dev/null 2>&1; done
  ./bin/registry-edit.py set-backend "$BACK_ANTES" >/dev/null 2>&1
  rm -rf state/drafts /tmp/wt-falso
  printf '\n  limpeza: backend=%s\n' "$(./bin/backend.sh)"
}
trap limpa EXIT

# worktree falso, para a deteccao de stack ter o que ler
mkdir -p /tmp/wt-falso
echo '{"dependencies":{"expo":"~51.0.0","react-native":"0.74.0"}}' > /tmp/wt-falso/package.json

echo "subagent-prompt — teste"
echo
echo " backend linear"
./bin/registry-edit.py set-backend linear >/dev/null 2>&1
REPO=$(./bin/resolve-name.sh --repo "naturals app" 2>/dev/null)
echo "# corpo" > /tmp/b.md
OUT=$(./bin/linear.sh create --team "$TEAM" --title "[teste subagent-prompt] alvo" \
      --body-file /tmp/b.md --label "$REPO" --label high --state "Drafted" 2>/dev/null)
IDENT=$(python3 -c "import json,sys;print(json.load(sys.stdin)['created'][0]['identifier'])" <<<"$OUT" 2>/dev/null)
IDS=$(python3 -c "import json,sys;print(json.load(sys.stdin)['created'][0]['id'])" <<<"$OUT" 2>/dev/null)
[ -n "$IDENT" ] && passa "ticket de teste criado ($IDENT)" || { falha "nao criei o ticket"; exit 1; }

P=$(./bin/subagent-prompt.sh planner "$IDENT" --worktree /tmp/wt-falso 2>&1)
for campo in "IDENT: $IDENT" "/tmp/wt-falso" "$REPO" "Expo / React Native" "Risco: high" "origin/main" "ESPECIFICACAO COMPLETA"; do
  grep -qF "$campo" <<<"$P" && passa "prompt contem: $campo" || falha "faltou no prompt: $campo" "$(head -3 <<<"$P")"
done
grep -q "PLAN.md" <<<"$P" && passa "planner sabe onde escrever o PLAN.md" || falha "nao diz onde escrever"
grep -q "gate.*VAZIO\|gate.*roda depois" <<<"$P" && passa "declara a politica de gate do repo" || falha "sem politica de gate"

R=$(./bin/subagent-prompt.sh reviewer "$IDENT" --worktree /tmp/wt-falso 2>&1)
grep -qi "veredito" <<<"$R" && passa "reviewer recebe a instrucao de veredito" || falha "reviewer sem veredito"
grep -q "Nao edite nada" <<<"$R" && passa "reviewer proibido de editar" || falha "reviewer pode editar"
grep -qF "IDENT: $IDENT" <<<"$R" && passa "reviewer recebe o IDENT" || falha "reviewer sem IDENT"

echo
echo " deteccao de stack"
mkdir -p /tmp/wt-falso2 && echo '{}' > /tmp/wt-falso2/composer.json
grep -q "PHP / Laravel" <<<"$(./bin/subagent-prompt.sh planner "$IDENT" --worktree /tmp/wt-falso2 2>&1)" \
  && passa "composer.json -> PHP / Laravel" || falha "nao detectou Laravel"
rm -rf /tmp/wt-falso2

echo
echo " recusa entrada invalida"
./bin/subagent-prompt.sh zzz "$IDENT" >/dev/null 2>&1 && falha "aceitou papel invalido" || passa "recusa papel invalido"
./bin/subagent-prompt.sh planner >/dev/null 2>&1 && falha "aceitou sem IDENT" || passa "recusa sem IDENT"

echo
echo " backend orca"
./bin/registry-edit.py set-backend orca >/dev/null 2>&1
echo "# spec do rascunho

Corpo da spec." > /tmp/s.md
./bin/board.sh draft --title "alvo orca" --body-file /tmp/s.md --label "$REPO" --label medium --slug alvo-orca >/dev/null 2>&1
PO=$(./bin/subagent-prompt.sh planner alvo-orca --worktree /tmp/wt-falso 2>&1)
grep -q "IDENT: alvo-orca" <<<"$PO" && passa "resolve rascunho do backend orca" || falha "nao achou no orca" "$(head -3 <<<"$PO")"
grep -q "Risco: medium" <<<"$PO" && passa "risco vem do front-matter" || falha "risco errado no orca"
grep -qF "$REPO" <<<"$PO" && passa "repo vem do front-matter" || falha "repo errado no orca"

echo
echo "  $OK ok, $F falha(s)"
[ "$F" -eq 0 ]
