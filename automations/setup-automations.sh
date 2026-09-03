#!/usr/bin/env bash
# Cria as automations no Orca. Rode uma vez, depois de conferir os flags.
#
# ATENCAO: os flags do `orca automations` mudam entre versoes do app.
# Rode `orca automations --help` e ajuste ANTES de executar isto.
#
# Conferido contra o Orca 1.4.159 em 30/07/2026:
#   --cron  virou  --trigger
#   --agent virou  --provider
# Se a sua versao divergir, o --help manda, nao este arquivo.
set -euo pipefail

# A raiz sai do proprio caminho deste script: nada de default codificado, que
# so acerta na maquina de quem escreveu.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# A team key sai do registry, que e a fonte da verdade. Override por ambiente
# continua valendo para quem tem mais de um time.
TEAM="${LINEAR_TEAM:-$(grep -m1 'linear_team:' "$ROOT/registry.yaml" 2>/dev/null | awk '{print $2}')}"
[ -n "${TEAM:-}" ] || { echo "sem linear_team: rode /orchestrator-setup ou defina LINEAR_TEAM" >&2; exit 1; }

# Workspace unico: um time so no Linear, empresas separadas por etiqueta Repo/.
# Por isso existe UMA automation de pull, nao uma por empresa — o precheck e
# global e as tres disparariam juntas, acordando o modelo a toa duas vezes.
# O coordenador le o registry, respeita wip_max por empresa e ordena por
# prioridade atravessando todas elas.

# --- execucao: a cada 2 min, mas o precheck evita acordar o agente a toa -----
orca automations create --name pull-all \
  --trigger "*/2 * * * *" \
  --workspace "path:$ROOT" --reuse-session --provider claude \
  --precheck "$ROOT/bin/has-ready.sh $TEAM" \
  --prompt "/pull-ready"

# --- triagem: o que faz escrever ticket do celular valer a pena --------------
# `1-59/2` = minutos IMPARES. O pull-all roda nos pares (*/2), entao os dois
# alternam e nunca disparam juntos. Isso importa porque ambos usam a MESMA
# sessao reutilizada (--reuse-session no mesmo --workspace): dois disparos
# simultaneos competiriam pela mesma sessao do Claude.
# Nao troque por "*/5": metade dos multiplos de 5 e par e colidiria com o pull.
orca automations create --name triage-all \
  --trigger "1-59/2 * * * *" \
  --workspace "path:$ROOT" --reuse-session --provider claude \
  --precheck "$ROOT/bin/has-triage.sh $TEAM" \
  --prompt "/triage-tickets"

# --- higiene ----------------------------------------------------------------
# sessao fresca de manha, para o coordenador nao acumular contexto o dia todo
orca automations create --name morning-reset \
  --trigger "0 8 * * 1-5" \
  --workspace "path:$ROOT" --provider claude \
  --prompt "/reconcile"

echo "criadas. confira com: orca automations list --json"
