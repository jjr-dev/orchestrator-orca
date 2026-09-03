#!/usr/bin/env bash
# Escolhe COMO implementar um ticket — modelo e effort — a partir do risco.
# Sem modelo, custo zero. So imprime; nao move nada, nao cria nada.
#
# Uso:  implementer-model.sh <IDENT> [--flags | --effort]
#   (sem opcao)  uma palavra: o alias do modelo
#   --flags      o par pronto para o comando: `--model opus --effort high`
#   --effort     uma palavra: o nivel de effort
# Motivo (stderr): uma linha explicando de onde veio a decisao
#
#     orca orchestration worker-start ... $(implementer-model.sh ACME-139 --flags)
#
# Por que existe: a alternativa era uma tabela na skill, aplicada pelo agente da
# vez. Regra que depende de alguem lembrar de aplicar e regra que um dia nao e
# aplicada — e o sintoma seria um ticket de risco alto rodando no ajuste errado,
# sem erro nenhum. Aqui a decisao e dado, nao leitura.
#
# Ordem de resolucao:
#   1. etiqueta Risk/<nivel> no proprio ticket   (a triagem poe, e o humano ajusta)
#   2. risk_default do repo, pela etiqueta Repo/  (quando a triagem nao marcou)
#   3. implementer_fallback do registry           (quando falta dado)
#
# O passo 3 e de proposito o ajuste mais caro: se a informacao sumiu, o erro
# aceitavel e gastar demais, nunca entregar de menos.
#
# `--flags` e usado SEM aspas no comando, porque precisa virar dois pares de
# argumentos. Isso significa que saida vazia nao quebraria nada — o worker so
# herdaria o modelo do painel e o `effortLevel` global, que sao justamente o
# extremo caro. Degradacao segura, e nao falha silenciosa para o lado barato.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
REG="$ROOT/registry.yaml"

MODO="${2:-}"

emitir() {
  case "$MODO" in
    --flags)  echo "--model $1 --effort $2" ;;
    --effort) echo "$2" ;;
    *)        echo "$1" ;;
  esac
}

emergencia() {
  # ultimo recurso: nem o registry deu para ler
  emitir opus xhigh
  echo "implementer-model: $1 — usando opus/xhigh por seguranca" >&2
  exit 0
}

IDENT="${1:-}"
[ -n "$IDENT" ] || emergencia "sem IDENT"
NUM="${IDENT##*-}"
[[ "$NUM" =~ ^[0-9]+$ ]] || emergencia "IDENT invalido '$IDENT'"

TEAM=$(grep -m1 'linear_team:' "$REG" 2>/dev/null | awk '{print $2}')
[ -n "${TEAM:-}" ] || emergencia "linear_team nao encontrado no registry"

RESP=$(
  "$DIR/linear-query.sh" \
    "{ issues(filter:{team:{key:{eq:\"$TEAM\"}}, number:{eq:$NUM}}, first:1){ nodes{ labels{ nodes{ name parent{ name } } } } } }" \
    2>/dev/null
) || emergencia "consulta ao Linear falhou"

# o nome da etiqueta vem SEM o prefixo do grupo: `high`, nao `Risk/high`.
# quem diz o grupo e o parent — por isso filtramos por ele, e nao por prefixo.
RISCO=$(printf '%s' "$RESP" | jq -r '
  .data.issues.nodes[0].labels.nodes[]? | select(.parent.name == "Risk") | .name' 2>/dev/null | head -1)
REPO=$(printf '%s' "$RESP" | jq -r '
  .data.issues.nodes[0].labels.nodes[]? | select(.parent.name == "Repo") | .name' 2>/dev/null | head -1)

ORIGEM="etiqueta Risk/$RISCO"
if [ -z "${RISCO:-}" ]; then
  if [ -n "${REPO:-}" ]; then
    RISCO=$(REPO="$REPO" REG="$REG" python3 - <<'PY' 2>/dev/null
import os, yaml
d = yaml.safe_load(open(os.environ["REG"]))
alvo = os.environ["REPO"]
for emp in (d.get("companies") or {}).values():
    r = (emp.get("repos") or {}).get(alvo)
    if r and r.get("risk_default"):
        print(r["risk_default"]); break
PY
)
    ORIGEM="risk_default do repo '$REPO' (ticket sem etiqueta Risk)"
  fi
fi

# aceita as duas formas no registry: `high: opus` (so modelo) e
# `high: {model: opus, effort: xhigh}`. A primeira nao deve existir, mas um
# registry editado pela metade nao pode derrubar o despacho.
AJUSTE=$(RISCO="${RISCO:-}" REG="$REG" python3 - <<'PY' 2>/dev/null
import os, yaml
m = (yaml.safe_load(open(os.environ["REG"])).get("defaults") or {}).get("models") or {}
r = (os.environ.get("RISCO") or "").strip().lower()
alvo = (m.get("implementer_by_risk") or {}).get(r) or m.get("implementer_fallback") or "opus"
if isinstance(alvo, str):
    alvo = {"model": alvo}
print(alvo.get("model") or "opus", alvo.get("effort") or "xhigh")
PY
)
read -r MODELO EFFORT <<<"${AJUSTE:-}"
[ -n "${MODELO:-}" ] && [ -n "${EFFORT:-}" ] || emergencia "registry sem mapa de modelos"

if [ -z "${RISCO:-}" ]; then
  ORIGEM="sem etiqueta Risk e sem risk_default — fallback"
fi

emitir "$MODELO" "$EFFORT"
echo "implementer-model: $IDENT -> $MODELO/$EFFORT  ($ORIGEM)" >&2
