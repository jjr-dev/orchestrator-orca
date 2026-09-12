#!/usr/bin/env bash
# Teste da camada de backend: a troca, os prechecks e os verbos de fluxo.
#
# O que importa aqui e que NENHUM caminho fique mudo. Um precheck que sai 1 por
# registry quebrado parece "sem trabalho" e a fila para em silencio — a falha
# mais cara deste projeto. Metade dos casos verifica codigo de saida.
set -uo pipefail
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$RAIZ" || exit 1
TEAM="${1:-JJR}"

OK=0; FALHOU=0
passa() { OK=$((OK+1));         printf '  \033[32mok\033[0m   %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  \033[31mFALHA\033[0m %s\n' "$1"; [ -n "${2:-}" ] && echo "         $2"; }
ORIGINAL=$(./bin/backend.sh 2>/dev/null || echo linear)
restaura() {
  ./bin/registry-edit.py set-backend "$ORIGINAL" >/dev/null 2>&1
  rm -rf state/drafts
  printf '\n  backend restaurado para %s\n' "$(./bin/backend.sh)"
}
trap restaura EXIT

rc() { "$@" >/dev/null 2>&1; echo $?; }

echo "board — teste dos dois backends"
echo
echo " leitura da configuracao"
[ -n "$(./bin/backend.sh)" ] && passa "backend.sh responde ($(./bin/backend.sh))" || falha "backend.sh mudo"
[ "$(rc env ORCH_REGISTRY=/tmp/inexistente.yaml ./bin/backend.sh)" = 6 ] \
  && passa "registry ausente sai 6, nao adivinha" || falha "deveria sair 6"
printf 'defaults:\n  backend: sei-la\n' > /tmp/ruim.yaml
[ "$(rc env ORCH_REGISTRY=/tmp/ruim.yaml ./bin/backend.sh)" = 6 ] \
  && passa "valor desconhecido sai 6" || falha "aceitou backend invalido"

echo
echo " resolucao da chave: ambiente -> .env -> ~/.zshenv"
TMPH=$(mktemp -d)
cp .env /tmp/env.teste.bak 2>/dev/null || true
if [ -f .env ]; then
  env -u LINEAR_API_KEY HOME="$TMPH" ./bin/linear-query.sh '{ viewer { id } }' 2>/dev/null \
    | grep -q '"viewer"' && passa "le do .env sem depender do ~/.zshenv" \
    || falha ".env nao resolveu a chave"
  # linha vazia tem que falhar FALANDO, nao em silencio
  python3 -c "
import re,pathlib
p=pathlib.Path('.env'); p.write_text(re.sub(r'^LINEAR_API_KEY=.*\$','LINEAR_API_KEY=',p.read_text(),flags=re.M))"
  OUT=$(env -u LINEAR_API_KEY HOME="$TMPH" bash -c '. ./bin/linear-key.sh' 2>&1)
  echo "$OUT" | grep -q "esta vazia" && passa "linha vazia: diz exatamente qual arquivo e qual linha" \
    || falha "mensagem inutil com .env vazio" "$OUT"
  cp /tmp/env.teste.bak .env && rm -f /tmp/env.teste.bak
  env -u LINEAR_API_KEY HOME="$TMPH" ./bin/linear-query.sh '{ viewer { id } }' >/dev/null 2>&1 \
    && passa ".env restaurado e funcionando" || falha "nao restaurei o .env"
else
  passa "sem .env nesta maquina (pulado)"
fi
[ -f .env.example ] && ! grep -qE '^LINEAR_API_KEY=.+' .env.example \
  && passa ".env.example existe e nao tem valor real" || falha ".env.example ausente ou com segredo"
rm -rf "$TMPH"

echo
echo " troca de backend pela porta unica"
./bin/registry-edit.py set-backend orca >/dev/null 2>&1
[ "$(./bin/backend.sh)" = orca ] && passa "trocou para orca" || falha "nao trocou"
[ "$(./bin/board.sh backend)" = orca ] && passa "board.sh enxerga a troca" || falha "board.sh defasado"
./bin/registry-edit.py set-backend orca 2>&1 | grep -qi "ja e" \
  && passa "trocar para o mesmo valor e no-op" || falha "deveria dizer que ja e"

echo
echo " prechecks no backend orca"
[ "$(rc bash bin/has-triage.sh)" = 1 ] \
  && passa "has-triage sai 1 (nao ha fila de triagem sem board)" || falha "has-triage inesperado"
RC=$(rc bash bin/has-ready.sh)
{ [ "$RC" = 0 ] || [ "$RC" = 1 ]; } \
  && passa "has-ready consulta o orca (rc=$RC) sem exigir team" || falha "has-ready rc=$RC"
[ "$(rc env ORCH_REGISTRY=/tmp/inexistente.yaml bash bin/has-ready.sh)" = 6 ] \
  && passa "precheck com registry quebrado sai 6, nao 1" || falha "registry quebrado virou 'fila vazia'"

echo
echo " rascunho no backend orca (arquivo, porque a spec do orca e imutavel)"
echo "# Titulo

corpo da spec" > /tmp/d.md
./bin/board.sh draft --title "teste de rascunho" --body-file /tmp/d.md \
  --label "Likeland - API" --label high --label "Queue Jump" --slug teste-rascunho >/dev/null 2>&1 \
  && passa "draft grava" || falha "draft falhou"
./bin/board.sh list-drafts | python3 -c "
import json,sys
d=json.load(sys.stdin)['drafts']
x=[i for i in d if i['identifier']=='teste-rascunho']
assert x and x[0]['repo']=='Likeland - API' and x[0]['risk']=='high' and x[0]['queue_jump'], x
" 2>/dev/null && passa "list-drafts devolve repo, risk e queue_jump do front-matter" \
  || falha "front-matter nao sobreviveu"
grep -q '<!-- orch' state/drafts/teste-rascunho.md \
  && passa "front-matter e comentario HTML (invisivel no markdown)" || falha "front-matter ausente"

echo
echo " o que o orca nao faz: recusa ou ignora, nunca em silencio"

# `update` PRECISA falhar: nao gravar uma spec em silencio faria o worker
# implementar a versao velha. `comment` e `label` nao: parar o worker por causa
# de um comentario custa mais do que o comentario vale. Os dois casos avisam.
OUT=$(./bin/board.sh update --body x teste-rascunho 2>&1)
if [ $? -eq 0 ]; then falha "update deveria FALHAR (spec errada e perigosa)"
elif echo "$OUT" | grep -qi "ajuste ANTES"; then passa "update falha e diz o caminho certo"
else falha "update falhou sem explicar" "$OUT"; fi

for v in "comment --body x teste-rascunho" "label --add x teste-rascunho"; do
  OUT=$(./bin/board.sh $v 2>&1); RC=$?
  if [ $RC -ne 0 ]; then falha "'${v%% *}' deveria sair 0 (nao pode parar o worker)"
  elif echo "$OUT" | grep -qi "NAO gravado\|NAO alterada"; then
    passa "'${v%% *}' ignora mas AVISA onde a informacao vive"
  else falha "'${v%% *}' ignorou em silencio" "$OUT"; fi
done

echo
echo " volta para linear"
./bin/registry-edit.py set-backend linear >/dev/null 2>&1
[ "$(./bin/backend.sh)" = linear ] && passa "voltou para linear" || falha "nao voltou"
[ "$(rc bash bin/has-triage.sh $TEAM)" != 6 ] && passa "has-triage volta a consultar o Linear" || falha "has-triage rc=6"
./bin/board.sh list-drafts --team "$TEAM" | python3 -c "
import json,sys; json.load(sys.stdin)['drafts']" 2>/dev/null \
  && passa "list-drafts no linear devolve JSON no mesmo formato" || falha "formato divergiu entre backends"

echo
echo "  $OK ok, $FALHOU falha(s)"
[ "$FALHOU" -eq 0 ]
