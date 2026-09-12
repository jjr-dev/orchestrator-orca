#!/usr/bin/env bash
# Teste do resolve-name.sh contra um registry de fixture.
#
# O que importa aqui nao e "resolveu": e **nunca adivinhar errado**. Um repo
# resolvido para o vizinho cria o ticket no lugar errado, o worker implementa
# noutro codigo, e o erro so aparece no PR. Por isso metade dos casos abaixo
# verifica que ele RECUSA.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cp "$RAIZ/bin/resolve-name.sh" "$TMP/bin/"

cat > "$TMP/registry.yaml" <<'YAML'
defaults:
  agent: claude
stacks:
  "Acme - API/Web":
    - "Acme - API"
    - "Acme - Web"
  "Beta - API/App":
    - "Beta - API"
    - "Beta - App"
companies:
  acme:
    linear_team: ACME
    repos:
      "Acme - API": {slug: a, base: origin/main, gate: []}
      "Acme - Web": {slug: b, base: origin/main, gate: []}
      "Acme - Admin Web": {slug: c, base: origin/main, gate: []}
  beta:
    linear_team: ACME
    repos:
      "Beta - API": {slug: d, base: origin/main, gate: []}
      "Beta - App": {slug: e, base: origin/main, gate: []}
YAML

R="$TMP/bin/resolve-name.sh"
OK=0; FALHOU=0
passa() { OK=$((OK+1));         printf '  \033[32mok\033[0m   %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  \033[31mFALHA\033[0m %s\n' "$1"; [ -n "${2:-}" ] && echo "         $2"; }

resolve() {  # resolve <tipo> <texto> <esperado>
  local got; got=$("$R" "$1" "$2" 2>/dev/null)
  [ "$got" = "$3" ] && passa "$2 -> $3" || falha "$2" "esperava '$3', veio '${got:-vazio}'"
}
recusa() {   # recusa <tipo> <texto> <motivo>
  if "$R" "$1" "$2" >/dev/null 2>&1; then
    falha "deveria recusar: $2" "resolveu para '$("$R" "$1" "$2" 2>/dev/null)'"
  else
    passa "recusa $2 ($3)"
  fi
}

echo "resolve-name — teste contra fixture"
echo

echo " formas de escrever o mesmo repo"
resolve --repo "Acme - API"  "Acme - API"
resolve --repo "Acme API"    "Acme - API"
resolve --repo "acme api"    "Acme - API"
resolve --repo "ACME - API"  "Acme - API"
resolve --repo "acmeapi"     "Acme - API"

echo
echo " o caso que mais engana: prefixo comum"
# "Acme Web" nao pode virar "Acme - Admin Web": o degrau normalizado resolve
# antes de chegar no de palavras, e e isso que este teste trava.
resolve --repo "Acme Web"       "Acme - Web"
resolve --repo "Acme Admin Web" "Acme - Admin Web"

echo
echo " ambiguidade: recusar e listar, nunca adivinhar"
recusa --repo "Acme"  "casa com 3"
recusa --repo "API"   "casa com 2 empresas"
recusa --repo "Beta"  "casa com 2"

echo
echo " inexistente"
recusa --repo "Gama - API"  "nao existe"
recusa --repo ""            "vazio"

echo
echo " stacks"
resolve --stack "Acme - API/Web"  "Acme - API/Web"
resolve --stack "acme api web"    "Acme - API/Web"
resolve --stack "beta"            "Beta - API/App"
recusa  --stack "Acme - API"      "stack nao e repo"

echo
echo " o texto original nunca sai no stdout"
SAIDA=$("$R" --repo "acme api" 2>/dev/null)
[ "$SAIDA" = "Acme - API" ] && passa "stdout e a chave canonica, nao o que foi digitado" \
  || falha "stdout devolveu '$SAIDA'"

echo
echo "  $OK ok, $FALHOU falha(s)"
[ "$FALHOU" -eq 0 ] || exit 1
