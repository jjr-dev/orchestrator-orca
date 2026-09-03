#!/usr/bin/env bash
# Diagnostico da instalacao. Somente leitura: nao cria, nao move, nao conserta.
#
# Existe porque a falha caracteristica deste sistema nao levanta erro. Duas
# reais, ambas descobertas por acaso semanas depois:
#
#   - o guard-commands.sh estava registrado num settings.json que o worker nunca
#     leu. 258 comandos de projeto passaram sem barreira, sem um unico aviso.
#   - o bloco `models` do registry era decoracao: nada lia aqueles valores e
#     tudo rodava no modelo padrao. Sonnet era 0,07% dos tokens.
#
# Nos dois casos o sistema continuou "funcionando". Cada checagem abaixo existe
# porque algo parecido pode acontecer de novo em silencio.
#
# Saida: 0 se tudo passou, 1 se ha falha, 2 se ha so avisos.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ" || exit 1

OK=0; AVISO=0; FALHA=0
V=$'\033[32m'; A=$'\033[33m'; R=$'\033[31m'; Z=$'\033[0m'; D=$'\033[2m'

ok()    { OK=$((OK+1));       printf '  %sok%s    %s\n' "$V" "$Z" "$1"; }
aviso() { AVISO=$((AVISO+1)); printf '  %saviso%s %s\n' "$A" "$Z" "$1"; [ -n "${2:-}" ] && printf '        %s%s%s\n' "$D" "$2" "$Z"; }
falha() { FALHA=$((FALHA+1)); printf '  %sFALHA%s %s\n' "$R" "$Z" "$1"; [ -n "${2:-}" ] && printf '        %s%s%s\n' "$D" "$2" "$Z"; }
secao() { printf '\n%s\n' "$1"; }

py() { python3 -c "$1" 2>/dev/null; }
reg() { py "import yaml;d=yaml.safe_load(open('registry.yaml'));$1"; }

# ---------------------------------------------------------------- 1. binarios
secao "pre-requisitos"
for b in orca jq python3 git; do
  if command -v "$b" >/dev/null 2>&1; then ok "$b"; else falha "$b nao encontrado" "sem ele nada funciona"; fi
done
command -v gh >/dev/null 2>&1 && ok "gh" || aviso "gh nao encontrado" "o worker nao conseguira abrir PR"
py 'import yaml' && ok "python yaml" || falha "modulo yaml ausente" "python3 -m pip install pyyaml"

# ---------------------------------------------------------------- 2. registry
secao "registry"
if [ ! -f registry.yaml ]; then
  falha "registry.yaml nao existe" "rode /orchestrator-setup, ou cp registry.example.yaml registry.yaml"
else
  if reg 'pass'; then
    ok "registry.yaml parseia"

    RUINS=$(reg '
import sys
for e,v in (d.get("companies") or {}).items():
  for n,r in (v.get("repos") or {}).items():
    if not str(r.get("base","")).startswith("origin/"): print(f"{n}: {r.get(\"base\")}")')
    if [ -z "$RUINS" ]; then ok "todo base tem prefixo origin/"
    else falha "base sem origin/ — o worker parte de codigo velho" "$(echo "$RUINS" | tr '\n' ' ')"; fi

    COM_GATE=$(reg '
for e,v in (d.get("companies") or {}).items():
  for n,r in (v.get("repos") or {}).items():
    if r.get("gate"): print(n)')
    if [ -z "$COM_GATE" ]; then ok "gate: [] em todos os repos (execucao zero)"
    else aviso "repo com gate nao vazio" "$(echo "$COM_GATE" | tr '\n' ' ')"; fi

    SEM_ID=$(reg '
for e,v in (d.get("companies") or {}).items():
  for n,r in (v.get("repos") or {}).items():
    i=str(r.get("orca_repo_id",""))
    if not i or i.startswith("00000000"): print(n)')
    [ -z "$SEM_ID" ] && ok "todo repo tem orca_repo_id" \
      || falha "repo sem orca_repo_id real" "$(echo "$SEM_ID" | tr '\n' ' ')"

    N=$(reg 'print(sum(len(v.get("repos") or {}) for v in (d.get("companies") or {}).values()))')
    ok "$N repos em $(reg 'print(len(d.get("companies") or {}))') empresa(s)"
  else
    falha "registry.yaml nao parseia" "$(py 'import yaml;yaml.safe_load(open("registry.yaml"))' 2>&1 | tail -1)"
  fi
fi

[ -f registry.example.yaml ] && ok "registry.example.yaml presente (template)" \
  || aviso "registry.example.yaml ausente" "o setup nao tem de onde partir"

if git rev-parse --git-dir >/dev/null 2>&1; then
  if git check-ignore -q registry.yaml 2>/dev/null; then ok "registry.yaml esta no .gitignore"
  else falha "registry.yaml NAO esta ignorado" "publicar o repo publicaria sua config"; fi
fi

# ---------------------------------------------------------------- 3. linear
secao "linear"
TEAM=$(reg 'print(next(iter(d["companies"].values()))["linear_team"])' 2>/dev/null)
if [ -z "${TEAM:-}" ]; then
  aviso "sem linear_team no registry" "pulei as checagens do Linear"
else
  RESP=$(./bin/linear-query.sh "{ teams(filter:{key:{eq:\"$TEAM\"}}, first:1){ nodes{ id key name
    states{ nodes{ name type } } labels{ nodes{ name parent{ name } } } } } }" 2>/dev/null)
  if [ -z "$RESP" ] || ! jq -e '.data.teams.nodes[0].id' >/dev/null 2>&1 <<<"$RESP"; then
    falha "nao consegui falar com o Linear como time '$TEAM'" "token ausente, invalido, ou team key errada"
  else
    ok "token valido, time $TEAM encontrado"

    FALTAM=""
    for e in Draft Drafting Drafted "Ready for Agent" Scheduled "In Progress" "In Review" "Manual QA" Done; do
      jq -e --arg e "$e" '.data.teams.nodes[0].states.nodes[]|select(.name==$e)' >/dev/null 2>&1 <<<"$RESP" \
        || FALTAM="$FALTAM'$e' "
    done
    [ -z "$FALTAM" ] && ok "os 9 estados do workflow existem" \
      || falha "estado(s) faltando no Linear" "$FALTAM— o precheck fica mudo sem eles"

    # a API devolve o nome SEM o prefixo do grupo: filtra-se por parent.name
    for g in Repo Risk; do
      jq -e --arg g "$g" '.data.teams.nodes[0].labels.nodes[]|select(.parent.name==$g)' >/dev/null 2>&1 <<<"$RESP" \
        && ok "grupo de etiqueta $g/ existe" || falha "grupo $g/ nao existe" "ticket sem Repo/ e invisivel para o coordenador"
    done
    for n in high medium low; do
      jq -e --arg n "$n" '.data.teams.nodes[0].labels.nodes[]|select(.parent.name=="Risk" and .name==$n)' \
        >/dev/null 2>&1 <<<"$RESP" || aviso "Risk/$n nao existe" "tickets desse nivel caem no fallback"
    done

    if [ -f registry.yaml ]; then
      SEM_LABEL=$(jq -r '[.data.teams.nodes[0].labels.nodes[]|select(.parent.name=="Repo")|.name]|join("\n")' <<<"$RESP" \
        | py "
import sys,yaml
labels=set(l.strip() for l in sys.stdin if l.strip())
d=yaml.safe_load(open('registry.yaml'))
for e,v in (d.get('companies') or {}).items():
  for n in (v.get('repos') or {}):
    if n not in labels: print(n)")
      [ -z "$SEM_LABEL" ] && ok "todo repo do registry tem etiqueta Repo/ no Linear" \
        || falha "repo sem etiqueta Repo/ correspondente" "$(echo "$SEM_LABEL" | tr '\n' ' ')— ticket nunca sera roteado"
    fi
  fi
fi

# ---------------------------------------------------------------- 4. modelos
secao "modelos e subagentes"
PAINEL=$(py "import json;print(json.load(open('.claude/settings.json')).get('model',''))")
[ -n "$PAINEL" ] && ok "painel: model=$PAINEL" || aviso "painel sem 'model' no settings.json" "roda no padrao da sua conta"

for ag in orch-planner orch-reviewer; do
  F="$HOME/.claude/agents/$ag.md"
  if [ ! -f "$F" ]; then
    falha "$ag nao instalado em ~/.claude/agents" "rode ./bin/install-agents.sh — sem isso o worker planeja sozinho"
  else
    M=$(sed -n 's/^model: *//p' "$F" | head -1)
    [ -n "$M" ] && ok "$ag instalado (model=$M)" \
      || falha "$ag sem 'model:'" "herdaria modelo e effort de quem chamou"
    if ! cmp -s "$F" ".claude/agents/$ag.md" 2>/dev/null; then
      aviso "$ag difere da fonte no repo" "rode ./bin/install-agents.sh"
    fi
  fi
done

EFFORT=$(py "import json;print(json.load(open('$HOME/.claude/settings.json')).get('effortLevel','(padrao)'))")
ok "effortLevel global: $EFFORT"

if [ -f registry.yaml ] && [ -n "${TEAM:-}" ]; then
  SAIDA=$(./bin/implementer-model.sh "${TEAM}-1" --flags 2>/dev/null)
  case "$SAIDA" in
    --model*--effort*) ok "resolver responde: $SAIDA" ;;
    *) falha "implementer-model nao devolveu os dois flags" "saida: '${SAIDA:-vazia}'" ;;
  esac
fi

# ---------------------------------------------------------------- 5. execucao
secao "hooks e politica de execucao"
if [ -x bin/guard-commands.sh ]; then
  ok "guard-commands.sh existe e e executavel"
  py "
import json;h=json.load(open('.claude/settings.json')).get('hooks',{}).get('PreToolUse',[])
import sys;sys.exit(0 if any('guard-commands' in str(x) for x in h) else 1)" \
    && ok "guard-commands registrado no PreToolUse do painel" \
    || falha "hook nao registrado" "o painel fica sem barreira"
  aviso "o hook NAO alcanca o worker" "ele roda no worktree do cliente, onde este settings.json nao existe: para o worker a politica e regra de prompt"
else
  falha "bin/guard-commands.sh ausente ou sem permissao de execucao"
fi
[ -f PAUSE ] && aviso "PAUSE presente — o kill switch esta acionado" "rm PAUSE para voltar" \
             || ok "kill switch desligado (sem PAUSE)"

# ---------------------------------------------------------------- 6. cronjobs
secao "automations (cronjobs)"
LISTA=$(orca automations list 2>&1)
# "nao listou" tem duas causas muito diferentes, e confundi-las manda alguem
# recriar automations que ja existem. O app fechado nao apaga nada.
if grep -qi 'not running\|Start the Orca app' <<<"$LISTA"; then
  aviso "o app do Orca esta fechado" "nao da para checar as automations; abra o Orca e rode de novo"
  LISTA=""
elif [ -z "$LISTA" ]; then
  aviso "nenhuma automation encontrada" "nada roda sozinho; rode /orchestrator-setup"
else
  for nome in pull-all triage-all morning-reset; do
    LINHA=$(grep -A1 -- "$nome" <<<"$LISTA" | head -2)
    if [ -z "$LINHA" ]; then
      aviso "automation '$nome' nao existe"
    elif grep -q 'disabled' <<<"$LINHA"; then
      falha "automation '$nome' esta DESABILITADA" "nao vai disparar"
    else
      PROX=$(grep -o 'next: [^ ]*' <<<"$LINHA" | head -1 | cut -d' ' -f2)
      ok "'$nome' ativa${PROX:+, proxima $PROX}"
    fi
  done
fi
for p in bin/has-ready.sh bin/has-triage.sh; do
  [ -x "$p" ] && ok "precheck $p executavel" || falha "$p sem permissao de execucao" "o cron nunca dispara"
done

# ---------------------------------------------------------------- resumo
printf '\n  %s%d ok%s, %s%d aviso(s)%s, %s%d falha(s)%s\n' \
  "$V" "$OK" "$Z" "$A" "$AVISO" "$Z" "$R" "$FALHA" "$Z"
[ "$FALHA" -gt 0 ] && exit 1
[ "$AVISO" -gt 0 ] && exit 2
exit 0
