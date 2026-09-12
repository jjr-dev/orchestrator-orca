#!/usr/bin/env bash
# Reconcilia as etiquetas do Linear com o registry.
#
# Sem --apply so mostra o que falta. Com --apply cria o que falta.
# NUNCA apaga: etiqueta pode ter ticket vinculado, e apagar leva o vinculo
# junto sem volta. Orfa e reportada para voce decidir.
#
# O que ele garante que exista, a partir do registry:
#   grupo Repo/   + um filho por repo em companies.*.repos
#   grupo Stack/  + um filho por chave em stacks
#   grupo Risk/   + high, medium, low
#   Fast Track    (plana) — pedido trivial, pula a redacao da spec
#   Queue Jump    (plana) — pedido do chat, nao consome vaga da empresa
#
# Por que script e nao instrucao na skill: o nome da etiqueta precisa ser
# identico byte a byte a chave do registry — e a chave da resolucao inteira, e
# divergir num espaco deixa todo ticket daquele repo invisivel, sem erro nenhum.
# Comparacao de string nao e trabalho para o julgamento do agente da vez.
#
# ⚠️ `status` e nome reservado no Linear: um grupo com esse nome e recusado.
# Por isso `Fast Track` e plana, e nao um grupo `Status/`.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$DIR/.." && pwd)"
REG="$RAIZ/registry.yaml"

APLICAR=0
[ "${1:-}" = "--apply" ] && APLICAR=1

command -v jq >/dev/null || { echo "falta jq" >&2; exit 1; }
[ -f "$REG" ] || { echo "registry.yaml nao existe — rode /orc-setup" >&2; exit 1; }

TEAM=$(grep -m1 'linear_team:' "$REG" | awk '{print $2}')
[ -n "${TEAM:-}" ] || { echo "linear_team nao encontrado no registry" >&2; exit 1; }

RESP=$("$DIR/linear-query.sh" "{ teams(filter:{key:{eq:\"$TEAM\"}}, first:1){ nodes{
  id key labels(first:250){ nodes{ id name isGroup parent{ name } } } } } }" 2>/dev/null)

TEAM_ID=$(jq -r '.data.teams.nodes[0].id // empty' <<<"$RESP")
[ -n "$TEAM_ID" ] || { echo "nao consegui ler o time '$TEAM' no Linear (token? team key?)" >&2; exit 1; }

# --- o que o registry quer -------------------------------------------------
QUER=$(python3 - "$REG" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
for e in (d.get("companies") or {}).values():
    for n in (e.get("repos") or {}):
        print("Repo\t" + n)
for n in (d.get("stacks") or {}):
    print("Stack\t" + n)
for n in ("high", "medium", "low"):
    print("Risk\t" + n)
PY
)

existe() {  # existe <grupo|-> <nome>
  if [ "$1" = "-" ]; then
    jq -e --arg n "$2" '.data.teams.nodes[0].labels.nodes[]
      | select(.name == $n and (.parent | not))' >/dev/null 2>&1 <<<"$RESP"
  else
    jq -e --arg g "$1" --arg n "$2" '.data.teams.nodes[0].labels.nodes[]
      | select(.name == $n and .parent.name == $g)' >/dev/null 2>&1 <<<"$RESP"
  fi
}
grupo_id() {
  jq -r --arg g "$1" '.data.teams.nodes[0].labels.nodes[]
    | select(.name == $g and .isGroup) | .id' <<<"$RESP" | head -1
}

criar() {  # criar <nome> <grupo|filho:<parent_id>|plana>
  local nome="$1" modo="$2" campos
  campos="teamId: \"$TEAM_ID\", name: \"$nome\""
  case "$modo" in
    grupo)   campos="$campos, isGroup: true" ;;
    plana)   : ;;                                   # nem grupo, nem filho
    filho:*) campos="$campos, parentId: \"${modo#filho:}\"" ;;
    *) echo "modo invalido: $modo" >&2; return 1 ;;
  esac
  local out
  out=$("$DIR/linear-query.sh" "mutation { issueLabelCreate(input: { $campos })
    { success issueLabel { id name } } }" 2>/dev/null)
  jq -r '.data.issueLabelCreate.issueLabel.id // empty' <<<"$out"
}

# --- diagnostico -----------------------------------------------------------
FALTA_GRUPO=(); FALTA_FILHO=(); ORFAS=()

for g in Repo Risk Stack; do
  [ -n "$(grupo_id "$g")" ] || FALTA_GRUPO+=("$g")
done
existe - "Fast Track" || FALTA_GRUPO+=("Fast Track(plana)")
existe - "Queue Jump" || FALTA_GRUPO+=("Queue Jump(plana)")

while IFS=$'\t' read -r g n; do
  [ -z "${g:-}" ] && continue
  existe "$g" "$n" || FALTA_FILHO+=("$g/$n")
done <<<"$QUER"

# orfas: etiqueta Repo/ ou Stack/ que o registry nao conhece
ORFAS_TXT=$(jq -r '.data.teams.nodes[0].labels.nodes[]
  | select(.parent.name == "Repo" or .parent.name == "Stack")
  | "\(.parent.name)/\(.name)"' <<<"$RESP" | python3 - "$REG" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
conhecidos = {"Repo/" + n for e in (d.get("companies") or {}).values() for n in (e.get("repos") or {})}
conhecidos |= {"Stack/" + n for n in (d.get("stacks") or {})}
for l in sys.stdin:
    l = l.strip()
    if l and l not in conhecidos:
        print(l)
PY
)

# --- relatorio -------------------------------------------------------------
V=$'\033[32m'; A=$'\033[33m'; Z=$'\033[0m'
echo "time $TEAM"
echo

if [ ${#FALTA_GRUPO[@]} -eq 0 ] && [ ${#FALTA_FILHO[@]} -eq 0 ]; then
  echo "  ${V}tudo alinhado${Z}: nenhuma etiqueta faltando"
else
  [ ${#FALTA_GRUPO[@]} -gt 0 ] && { echo "  grupos faltando:"; printf '    %s\n' "${FALTA_GRUPO[@]}"; }
  [ ${#FALTA_FILHO[@]} -gt 0 ] && { echo "  etiquetas faltando (${#FALTA_FILHO[@]}):"; printf '    %s\n' "${FALTA_FILHO[@]}"; }
fi

if [ -n "$ORFAS_TXT" ]; then
  echo
  echo "  ${A}orfas${Z} — existem no Linear e nao no registry:"
  printf '    %s\n' $(echo "$ORFAS_TXT")
  echo "    (nao apago: podem ter ticket vinculado. Decida voce.)"
fi

if [ "$APLICAR" -eq 0 ]; then
  echo
  echo "  nada foi criado. Para aplicar: $(basename "$0") --apply"
  exit 0
fi
[ ${#FALTA_GRUPO[@]} -eq 0 ] && [ ${#FALTA_FILHO[@]} -eq 0 ] && exit 0

# --- aplicar ---------------------------------------------------------------
echo
echo "criando..."
# bash 3.2 (o do macOS) com `set -u` trata "${vazio[@]}" como variavel nao
# definida e aborta. Guardar pelo tamanho funciona nas duas versoes, e
# preserva nome com espaco — que `$(...)` sem aspas destruiria.
if [ ${#FALTA_GRUPO[@]} -gt 0 ]; then
  for g in "${FALTA_GRUPO[@]}"; do
    case "$g" in
      *"(plana)")
        nome_plano="${g%(plana)}"
        id=$(criar "$nome_plano" plana)
        [ -n "$id" ] && echo "  + $nome_plano (plana)" || echo "  ! $nome_plano falhou"
        continue ;;
    esac
    if false; then :
    else
      id=$(criar "$g" grupo)
      [ -n "$id" ] && echo "  + grupo $g/" || echo "  ! grupo $g/ falhou"
    fi
  done
fi

# releitura: os grupos recem-criados precisam entrar no cache antes dos filhos
RESP=$("$DIR/linear-query.sh" "{ teams(filter:{key:{eq:\"$TEAM\"}}, first:1){ nodes{
  id key labels(first:250){ nodes{ id name isGroup parent{ name } } } } } }" 2>/dev/null)

if [ ${#FALTA_FILHO[@]} -gt 0 ]; then
  for item in "${FALTA_FILHO[@]}"; do
    g="${item%%/*}"; n="${item#*/}"
    pai=$(grupo_id "$g")
    if [ -z "$pai" ]; then echo "  ! $item — grupo $g/ nao existe"; continue; fi
    id=$(criar "$n" "filho:$pai")
    [ -n "$id" ] && echo "  + $item" || echo "  ! $item falhou"
  done
fi

echo
echo "confira: $(basename "$0")"
