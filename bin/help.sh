#!/usr/bin/env bash
# Imprime a referencia de comandos do orquestrador.
#
# A lista e DERIVADA de .claude/skills/orc-*/SKILL.md, nao escrita a mao. Skill
# nova aparece aqui sozinha. O que e escrito a mao e so o grupo e a frase curta
# de cada uma — e quando uma skill nao esta no mapa abaixo, o script reclama em
# vez de omiti-la em silencio.
#
# Esse aviso e o ponto: a falha caracteristica deste projeto e documentacao que
# diverge do sistema sem ninguem perceber.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ" || exit 1

V=$'\033[32m'; A=$'\033[33m'; N=$'\033[1m'; D=$'\033[2m'; Z=$'\033[0m'

# grupo|ordem|frase curta
descreve() {
  case "$1" in
    orc-task)      echo "fluxo|1|nova demanda pelo chat: planeja, mostra, e so despacha quando voce aprova" ;;
    orc-triage)    echo "fluxo|2|le o codigo e redige a spec de tickets em Draft" ;;
    orc-dispatch)  echo "fluxo|3|puxa o que esta em Ready for Agent e despacha" ;;
    orc-adjust)    echo "fluxo|4|pede ajuste no que ja virou PR, sem ticket novo" ;;
    orc-project)   echo "fluxo|5|monta o grafo de ondas de um projeto" ;;
    orc-reconcile) echo "fluxo|6|destrava ticket orfao e limpa worktree morto" ;;
    orc-setup)     echo "config|1|instala do zero, ou completa o que falta" ;;
    orc-linear)    echo "config|2|token, os 9 estados e os grupos de etiqueta" ;;
    orc-repo-add)  echo "config|3|acrescenta um repositorio (Orca + Linear + registry)" ;;
    orc-sync)      echo "config|4|reconcilia registry, Linear e Orca" ;;
    orc-models)    echo "config|5|mostra e ajusta modelo e effort por etapa" ;;
    orc-backend)   echo "config|6|escolhe onde o trabalho e registrado: linear ou orca" ;;
    orc-doctor)    echo "config|7|verifica se tudo esta realmente ligado" ;;
    orc-help)      echo "config|8|esta referencia" ;;
    *)             echo "" ;;
  esac
}

printf '\n%sOrquestrador — referencia de comandos%s\n' "$N" "$Z"

printf '\n%sDuas portas de entrada%s\n\n' "$N" "$Z"
cat <<'FLUXO'
  pelo Linear      voce escreve em Draft -> /orc-triage redige -> voce arrasta
                   para "Ready for Agent" -> /orc-dispatch despacha
                   (os cronjobs fazem triagem e despacho a cada 2 min)

  pelo chat        /orc-task "<pedido>" --repo "<Nome>"
                   cria o ticket, redige a spec e MOSTRA no chat, parado em
                   "Drafted". voce le, pede ajuste, e diz "pode executar" —
                   so ai os workers sobem. --fast pula spec e portao.
FLUXO

# Os sem-grupo se apuram ANTES dos laos de impressao. Aqueles laos terminam em
# `| sort | cut`, e pipeline roda em subshell: variavel setada la dentro morre
# com ele, e o aviso nunca apareceria — silenciosamente, que e o pior jeito.
SEM_GRUPO=""
for d in .claude/skills/orc-*/; do
  nome="$(basename "$d")"
  [ -n "$(descreve "$nome")" ] || SEM_GRUPO="$SEM_GRUPO $nome"
done

for grupo in fluxo config; do
  case "$grupo" in
    fluxo)  printf '\n%sDia a dia%s\n\n' "$N" "$Z" ;;
    config) printf '\n%sConfiguracao%s\n\n' "$N" "$Z" ;;
  esac
  for d in .claude/skills/orc-*/; do
    nome="$(basename "$d")"
    info="$(descreve "$nome")"
    [ -n "$info" ] || continue
    g="${info%%|*}"; resto="${info#*|}"; ord="${resto%%|*}"; frase="${resto#*|}"
    [ "$g" = "$grupo" ] || continue
    printf '%s|  %s/%-14s%s %s\n' "$ord" "$V" "$nome" "$Z" "$frase"
  done | sort -n | cut -d'|' -f2-
done

printf '\n%sScripts, quando voce quiser sem passar por skill%s\n\n' "$N" "$Z"
cat <<'SCRIPTS'
  ./bin/doctor.sh                    diagnostico completo
  ./bin/registry-edit.py show        o registry, legivel
  ./bin/sync-labels.sh [--apply]     etiquetas do Linear a partir do registry
  ./bin/resolve-name.sh --repo "<texto>"
                                     nome aproximado -> chave canonica
  ./bin/linear.sh move --to "Scheduled" JJR-1 JJR-2
                                     escrita rapida no Linear (create/move/update/
                                     comment/label); leitura segue no orca linear
  ./bin/implementer-model.sh <IDENT> --flags
                                     qual modelo/effort aquele ticket usaria
  ./bin/subagent-prompt.sh planner|reviewer <IDENT>
                                     prompt pronto do subagente, do registry
  ./bin/cleanup-worktrees.sh         lista worktrees que ja podem sair
SCRIPTS

printf '\n%sO kill switch%s\n\n' "$N" "$Z"
printf '  touch PAUSE    para tudo, sem desabilitar automation\n'
printf '  rm PAUSE       volta\n'
[ -f PAUSE ] && printf '  %sPAUSE esta ATIVO agora%s\n' "$A" "$Z"

if [ -n "$SEM_GRUPO" ]; then
  printf '\n%saviso%s skill sem grupo em bin/help.sh:%s\n' "$A" "$Z" "$SEM_GRUPO"
  printf '      acrescente em `descreve()`, senao ela nao aparece nesta ajuda\n'
fi

printf '\n%sdetalhe de cada uma: abra .claude/skills/<nome>/SKILL.md%s\n\n' "$D" "$Z"
