#!/usr/bin/env bash
# Teste do linear.sh contra a API real. Cria tickets de verdade e apaga todos
# no fim, inclusive se falhar no meio — por isso o trap antes do primeiro create.
#
# Metade dos casos verifica que ele RECUSA. Um estado ou etiqueta resolvido no
# escuro poe o ticket na coluna errada, e isso so aparece quando alguem olha o
# board.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ" || exit 1
TEAM="${1:-JJR}"

OK=0; FALHOU=0
passa() { OK=$((OK+1));         printf '  \033[32mok\033[0m   %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  \033[31mFALHA\033[0m %s\n' "$1"; [ -n "${2:-}" ] && echo "         $2"; }

CRIADOS=()
limpar() {
  [ ${#CRIADOS[@]} -eq 0 ] && return
  local m="" n=0
  for u in "${CRIADOS[@]}"; do m="$m d$n: issueDelete(id:\"$u\"){ success }"; n=$((n+1)); done
  ./bin/linear-query.sh "mutation{ $m }" >/dev/null 2>&1
  printf '\n  limpeza: %d ticket(s) de teste apagado(s)\n' "${#CRIADOS[@]}"
  varre_restos
}

varre_restos() {
  local resto
  resto=$(./bin/linear-query.sh "{ issues(filter:{ team:{key:{eq:\"$TEAM\"}}, title:{contains:\"[teste linear.sh]\"} }, first:50){ nodes{ id identifier } } }" 2>/dev/null \
    | python3 -c "
import json,sys
n=json.load(sys.stdin)['data']['issues']['nodes']
print('mutation{ ' + ' '.join(f'x{i}: issueDelete(id:\"{x[\"id\"]}\"){{ success }}' for i,x in enumerate(n)) + ' }' if n else '')
print(' '.join(x['identifier'] for x in n), file=sys.stderr)
" 2>/tmp/restos.ids)
  if [ -n "$resto" ]; then
    ./bin/linear-query.sh "$resto" >/dev/null 2>&1
    printf '  \033[33maviso\033[0m a contabilidade deixou restos, varridos por titulo: %s\n' "$(cat /tmp/restos.ids)"
  fi
}
trap limpar EXIT

cria() {  # cria <args...> -> ecoa o identifier, memoriza o uuid para limpeza
  local out; out=$(./bin/linear.sh create --team "$TEAM" "$@" 2>&1) || { echo "ERRO: $out" >&2; return 1; }
  python3 -c "
import json,sys
d=json.loads(sys.stdin.read())['created']
print(' '.join(i['identifier'] for i in d))
open('/tmp/uuids.test','w').write('\n'.join(i['id'] for i in d)+'\n')
" <<< "$out"
}
memoriza() { while read -r u || [ -n "$u" ]; do [ -n "$u" ] && CRIADOS+=("$u"); done < /tmp/uuids.test; }

echo "linear.sh — teste contra o time $TEAM"
echo

echo " cache"
./bin/linear.sh cache --refresh --team "$TEAM" >/tmp/c.out 2>&1 \
  && passa "monta o cache" || falha "cache --refresh" "$(cat /tmp/c.out)"
python3 -c "
import json;d=json.load(open('state/linear-cache.json'))
assert d['version']==1 and d['teams'], 'cache vazio'
" 2>/dev/null && passa "arquivo de cache e JSON valido" || falha "cache invalido"

echo
echo " criar"
PAI=$(cria --title "[teste linear.sh] pai" --state "Draft" 2>/dev/null); RC=$?
if [ $RC -eq 0 ] && [ -n "$PAI" ]; then memoriza; passa "cria um ticket ($PAI)"; else falha "create simples"; fi

FILHOS=$(cria --title "[teste linear.sh] com estado e etiqueta" --state "Drafting" --label "low" 2>/dev/null)
if [ -n "$FILHOS" ]; then memoriza; passa "cria com estado e etiqueta ($FILHOS)"; else falha "create com labels"; fi

cat > /tmp/lote.json <<JSON
[ {"title":"[teste linear.sh] filho A","state":"Drafting","labels":["low"]},
  {"title":"[teste linear.sh] filho B","state":"Drafting","labels":["low"]} ]
JSON
LOTE=$(./bin/linear.sh create --team "$TEAM" --batch /tmp/lote.json --parent "$PAI" 2>&1)
if python3 -c "
import json,sys
d=json.loads(sys.stdin.read())['created']
assert len(d)==2
print(' '.join(i['identifier'] for i in d))
open('/tmp/uuids.test','w').write('\n'.join(i['id'] for i in d)+'\n')
" <<< "$LOTE" >/tmp/lote.ids 2>/dev/null; then
  memoriza; passa "cria 2 filhos numa requisicao ($(cat /tmp/lote.ids))"
else falha "create --batch" "$LOTE"; fi
A=$(cut -d' ' -f1 /tmp/lote.ids); B=$(cut -d' ' -f2 /tmp/lote.ids)

echo
echo " o pai ficou com os filhos certos"
./bin/linear-query.sh "{ issue(id:\"$PAI\"){ children{ nodes{ identifier } } } }" \
  | python3 -c "
import json,sys
n=sorted(x['identifier'] for x in json.load(sys.stdin)['data']['issue']['children']['nodes'])
assert len(n)==2, n
print(' '.join(n))
" >/tmp/kids 2>/dev/null && passa "parent ligou 2 filhos ($(cat /tmp/kids))" || falha "parentId nao ligou"

echo
echo " mover, comentar, etiquetar"
./bin/linear.sh move --to "Scheduled" "$A" "$B" >/dev/null 2>&1 \
  && passa "move 2 tickets numa requisicao" || falha "move em lote"
./bin/linear-query.sh "{ a: issue(id:\"$A\"){ state{name} } b: issue(id:\"$B\"){ state{name} } }" \
  | python3 -c "
import json,sys;d=json.load(sys.stdin)['data']
assert d['a']['state']['name']=='Scheduled' and d['b']['state']['name']=='Scheduled', d
" 2>/dev/null && passa "os dois estao mesmo em Scheduled" || falha "o estado nao mudou de verdade"

./bin/linear.sh comment --body "comentario de teste" "$A" "$B" >/dev/null 2>&1 \
  && passa "comenta em 2 tickets" || falha "comment em lote"

./bin/linear.sh label --add "Queue Jump" "$A" >/dev/null 2>&1 \
  && passa "acrescenta etiqueta" || falha "label --add"
./bin/linear-query.sh "{ issue(id:\"$A\"){ labels{ nodes{ name } } } }" \
  | grep -q "Queue Jump" && passa "a etiqueta esta mesmo no ticket" || falha "label nao aplicada"
./bin/linear.sh label --remove "Queue Jump" "$A" >/dev/null 2>&1 \
  && passa "remove etiqueta" || falha "label --remove"
./bin/linear-query.sh "{ issue(id:\"$A\"){ labels{ nodes{ name } } } }" \
  | grep -q "Queue Jump" && falha "a etiqueta continua la" || passa "a etiqueta saiu de verdade"

echo
echo " reescrever ticket existente"
echo "spec reescrita pela triagem" > /tmp/spec.md
./bin/linear.sh update --body-file /tmp/spec.md --title "[teste linear.sh] retitulado" "$A" >/dev/null 2>&1 \
  && passa "update titulo + corpo" || falha "update"
./bin/linear-query.sh "{ issue(id:\"$A\"){ title description } }" | python3 -c "
import json,sys;d=json.load(sys.stdin)['data']['issue']
assert 'retitulado' in d['title'], d['title']
assert 'spec reescrita' in (d['description'] or ''), d['description']
" 2>/dev/null && passa "titulo e corpo mudaram de verdade" || falha "update nao gravou"

./bin/linear.sh update --parent "" "$A" >/dev/null 2>&1 && passa "desliga o pai" || falha "update --parent vazio"
./bin/linear-query.sh "{ issue(id:\"$A\"){ parent{ identifier } } }" | grep -q '"parent":null' \
  && passa "o vinculo com o pai saiu de verdade" || falha "ainda tem pai"

echo
echo " recusa em vez de adivinhar"
recusa() {
  local out; out=$(eval "$1" 2>&1)
  if [ $? -eq 0 ]; then falha "deveria recusar: $2"
  elif echo "$out" | grep -qi "existem:"; then passa "recusa $2, e lista o que existe"
  else falha "recusou $2 sem listar alternativas" "$out"; fi
}
recusa "./bin/linear.sh move --to 'Nao Existe' $A"                  "estado inexistente"
recusa "./bin/linear.sh label --add 'Etiqueta Fantasma' $A"          "etiqueta inexistente"
recusa "./bin/linear.sh create --team $TEAM --title x --state 'Zzz'" "create com estado invalido"
recusa "./bin/linear.sh update --state 'Zzz' $A"                         "update com estado invalido"

OUT=$(./bin/linear.sh move --to "Scheduled" "ZZZ-99999" 2>&1)
[ $? -ne 0 ] && passa "recusa ticket inexistente" || falha "aceitou ticket inexistente"

echo
echo " o cache se conserta sozinho"
python3 -c "
import json
c=json.load(open('state/linear-cache.json'))
for t in c['teams'].values(): t['estados']={'Lixo':'00000000-0000-0000-0000-000000000000'}
json.dump(c,open('state/linear-cache.json','w'))
"
./bin/linear.sh move --to "Drafting" "$A" >/dev/null 2>&1 \
  && passa "cache corrompido: rebusca e completa a operacao" || falha "nao se recuperou do cache ruim"

echo '{"nao":' > state/linear-cache.json
./bin/linear.sh move --to "Scheduled" "$A" >/dev/null 2>&1 \
  && passa "cache ilegivel: reconstroi do zero" || falha "nao sobreviveu a cache corrompido"

echo
echo "  $OK ok, $FALHOU falha(s)"
[ "$FALHOU" -eq 0 ]
