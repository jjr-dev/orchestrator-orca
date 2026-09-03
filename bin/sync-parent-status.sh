#!/usr/bin/env bash
# Move o ticket PAI conforme o estado dos filhos. Sem modelo, custo zero.
#
# DRY RUN por padrao. Passe --apply para mover de verdade.
#
# Uso:
#   bin/sync-parent-status.sh              # varre todos os pais do time
#   bin/sync-parent-status.sh --apply
#   bin/sync-parent-status.sh --apply ACME-84    # so este pai
#
# A REGRA, em uma frase: o pai acompanha o filho mais atrasado que ja foi
# aprovado pelo humano.
#
#   filho em rascunho SEM PR          -> IGNORADO (nunca foi aprovado)
#   filho em rascunho COM PR           -> REABERTO: conta, e puxa o pai
#   todos os demais em Scheduled+      -> pai vai para In Progress
#   todos os demais em In Review+      -> pai vai para In Review
#   todos os demais em Done            -> pai vai para Done
#
# Filho reaberto e o que sustenta a nova leva: um ticket que ja teve PR e voltou
# para `Draft` nao e "por aprovar", e trabalho ativo. Sem essa distincao ele
# cairia no saco dos ignorados e o pai continuaria dizendo `In Review` com um
# filho de volta na prancheta. Reaberto leva o pai para `Drafted` — e nao para
# `Draft`, que e a fila da triagem e faria o pai ser redigido a cada 2 minutos
# sem ter nada a redigir.
#
# Por que os backlog sao ignorados: `Drafted` e "redigido, esperando o humano
# ler" — ele nao foi aprovado, entao nao representa trabalho pendente da onda
# atual. Um filho parado em `Ready for Agent` SEGURA o pai, e essa e a
# diferenca que importa: ali o humano ja aprovou e o trabalho simplesmente
# ainda nao arrancou (wip_max, fila, base errada).
#
# SO ANDA PARA FRENTE, com UMA excecao: quando existe filho reaberto. A regra
# original protegia contra desfazer acao humana; reabrir um filho E a acao
# humana, entao seguir o pai para tras aqui obedece, nao desfaz. Fora desse
# caso o script continua recusando andar para tras.
#
# Pai sem filho, ou com todos os filhos em backlog, nunca e tocado.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

APPLY=0; ALVOS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*) echo "flag desconhecida: $1" >&2; exit 2 ;;
    *) ALVOS+=("$1"); shift ;;
  esac
done

TEAM=$(grep -m1 'linear_team:' "$ROOT/registry.yaml" | awk '{print $2}')
[ -n "$TEAM" ] || { echo "nao achei linear_team no registry.yaml" >&2; exit 2; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Uma consulta paginada traz time inteiro: filho e pai saem da mesma lista.
CURSOR=null; : > "$TMP/raw"
while :; do
  Q=$(printf '{ issues(filter:{team:{key:{eq:"%s"}}}, first:250, after:%s){ nodes{ identifier number state{name type} parent{ identifier } attachments{ nodes{ url } } } pageInfo{ hasNextPage endCursor } } }' "$TEAM" "$CURSOR")
  "$DIR/linear-query.sh" "$Q" > "$TMP/page" || { echo "consulta ao Linear falhou" >&2; exit 2; }
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]),strict=False)
i=d.get("data",{}).get("issues")
if not i: sys.exit(3)
for n in i["nodes"]: print(json.dumps(n))
' "$TMP/page" >> "$TMP/raw" || { echo "resposta inesperada do Linear" >&2; exit 2; }
  HAS=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]),strict=False);p=d["data"]["issues"]["pageInfo"];print(p["hasNextPage"],p["endCursor"] or "")' "$TMP/page")
  [ "${HAS%% *}" = "True" ] || break
  CURSOR="\"${HAS#* }\""
done

# Estados do time, para traduzir nome -> id na hora de aplicar.
"$DIR/linear-query.sh" "{ teams(filter:{key:{eq:\"$TEAM\"}}){ nodes{ states{ nodes{ id name } } } } }" > "$TMP/states"

python3 - "$TMP/raw" "$TMP/states" "$APPLY" "${ALVOS[@]+"${ALVOS[@]}"}" <<'PY' > "$TMP/plano"
import json,sys
raw,states,apply_=sys.argv[1],sys.argv[2],sys.argv[3]=="1"
alvos=set(sys.argv[4:])

# Escada de progresso. Degrau 0 e "voltou para a prancheta"; os estados de
# rascunho de um filho NUNCA aprovado nao sao degrau nenhum — sao ausencia.
RUNG={"Drafted":0,"Draft":0,"Drafting":0,"Backlog":0,"Todo":0,
      "Scheduled":1,"In Progress":2,"In Review":3,"Manual QA":4,"Done":5}
ALVO={0:"Drafted",1:"In Progress",2:"In Progress",3:"In Review",4:"In Review",5:"Done"}
RASCUNHO={"Draft","Drafting","Drafted"}
SEGURA={"Ready for Agent"}                       # aprovado e nao arrancou
FORA={"Canceled","Duplicate"}

def tem_pr(i):
    return any("/pull/" in (a.get("url") or "") for a in i.get("attachments",{}).get("nodes",[]))

issues=[json.loads(l) for l in open(raw)]
por_ident={i["identifier"]:i for i in issues}
filhos={}
for i in issues:
    p=i.get("parent")
    if p: filhos.setdefault(p["identifier"],[]).append(i)

plano=[]
for pai_id, fs in sorted(filhos.items()):
    pai=por_ident.get(pai_id)
    if not pai: continue
    if alvos and pai_id not in alvos: continue
    est_pai=pai["state"]["name"]
    if est_pai in FORA: continue

    considerados=[]; reabertos=[]
    for f in fs:
        n=f["state"]["name"]
        if n in FORA: continue
        if n in RASCUNHO:
            if tem_pr(f):                        # reaberto: conta
                considerados.append(f); reabertos.append(f["identifier"])
            continue                             # sem PR: nunca aprovado, ignora
        considerados.append(f)
    if not considerados:
        continue

    nomes=[f["state"]["name"] for f in considerados]
    if any(n in SEGURA for n in nomes):
        plano.append((pai_id,est_pai,None,"segura: filho em Ready for Agent"))
        continue
    if any(n not in RUNG for n in nomes):
        plano.append((pai_id,est_pai,None,"filho em estado inesperado: "
                      + ",".join(sorted(set(n for n in nomes if n not in RUNG)))))
        continue

    piso=min(RUNG[n] for n in nomes)             # o filho mais atrasado manda
    alvo=ALVO[piso]
    atual=RUNG.get(est_pai,0)
    if RUNG[alvo]==atual:
        continue
    if RUNG[alvo]<atual and not reabertos:
        plano.append((pai_id,est_pai,None,f"conta daria {alvo} — nao volto estado"))
        continue
    motivo=f"{len(considerados)} filho(s) contados, mais atrasado em " + min(nomes,key=lambda n:RUNG[n])
    if reabertos:
        motivo += " | reaberto: " + ",".join(reabertos)
    plano.append((pai_id,est_pai,alvo,motivo))

st={s["name"]:s["id"] for s in json.load(open(states),strict=False)["data"]["teams"]["nodes"][0]["states"]["nodes"]}
for pai_id,de,para,nota in plano:
    print("\t".join([pai_id,de,para or "-",nota,st.get(para or "","")]))
PY

if [ ! -s "$TMP/plano" ]; then
  echo "nenhum pai para ajustar"
  exit 0
fi

printf '%-10s %-16s %-14s %s\n' PAI DE PARA MOTIVO
printf '%-10s %-16s %-14s %s\n' '---' '---' '---' '---'
N=0
while IFS=$'\t' read -r pai de para nota sid; do
  printf '%-10s %-16s %-14s %s\n' "$pai" "$de" "$para" "$nota"
  [ "$para" = "-" ] && continue
  N=$((N+1))
  if [ "$APPLY" -eq 1 ]; then
    if [ -z "$sid" ]; then
      echo "           -> FALHOU: estado '$para' nao existe no time"
      continue
    fi
    ident_id=$("$DIR/linear-query.sh" "{ issues(filter:{team:{key:{eq:\"$TEAM\"}}, number:{eq:${pai##*-}}}, first:1){ nodes{ id } } }" \
      | jq -r '.data.issues.nodes[0].id // empty')
    if [ -n "$ident_id" ] && "$DIR/linear-query.sh" \
        "mutation { issueUpdate(id: \"$ident_id\", input: { stateId: \"$sid\" }) { success } }" \
        | jq -e '.data.issueUpdate.success' >/dev/null; then
      echo "           -> movido"
    else
      echo "           -> FALHOU ao mover"
    fi
  fi
done < "$TMP/plano"

echo
echo "$N pai(s) para mover"
[ "$APPLY" -eq 0 ] && [ "$N" -gt 0 ] && echo "DRY RUN — rode com --apply para mover"
exit 0
