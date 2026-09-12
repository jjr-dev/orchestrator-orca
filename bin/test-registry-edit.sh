#!/usr/bin/env bash
# Teste do registry-edit.py. Roda contra uma copia descartavel do
# registry.example.yaml — nunca toca no registry de ninguem.
#
# O que ele cobre nao e "a operacao funcionou": e "a operacao nao destruiu o
# resto do arquivo". Os 183 comentarios do registry sao a auditoria, e a falha
# que este teste existe para pegar e a silenciosa — o YAML continua valido e o
# significado mudou.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
cp "$RAIZ/bin/registry-edit.py" "$TMP/bin/"
cp "$RAIZ/registry.example.yaml" "$TMP/registry.yaml"
cp "$RAIZ/registry.example.yaml" "$TMP/registry.example.yaml"
EDIT="$TMP/bin/registry-edit.py"

OK=0; FALHOU=0
COMENTARIOS_INICIAIS=$(grep -c '#' "$TMP/registry.yaml")

passa() { OK=$((OK+1));      printf '  \033[32mok\033[0m   %s\n' "$1"; }
falha() { FALHOU=$((FALHOU+1)); printf '  \033[31mFALHA\033[0m %s\n' "$1"; [ -n "${2:-}" ] && echo "         $2"; }

# --- helpers ---------------------------------------------------------------
valido()      { python3 -c "import yaml,sys; yaml.safe_load(open('$TMP/registry.yaml'))" 2>/dev/null; }
comentarios() { grep -c '#' "$TMP/registry.yaml"; }
tem() {  # tem <expressao python sobre o dict `d`>
  python3 -c "
import yaml; d = yaml.safe_load(open('$TMP/registry.yaml'))
import sys; sys.exit(0 if ($1) else 1)" 2>/dev/null
}

echo "registry-edit — teste contra fixture"
echo

# --- 1. add-repo -----------------------------------------------------------
if "$EDIT" add-repo --company acme --name "Acme - Admin" --slug admin-acme \
     --orca-repo-id 11111111-2222-3333-4444-555555555555 \
     --base origin/main --setup "npm ci" --risk-default low \
     --pair "Acme - API" --manual "npm run lint" "npm run build" >/dev/null 2>&1; then
  valido || falha "add-repo: YAML quebrou"
  tem "'Acme - Admin' in d['companies']['acme']['repos']" \
    && passa "add-repo insere o repo" || falha "add-repo: repo nao apareceu"
  tem "d['companies']['acme']['repos']['Acme - Admin']['gate'] == []" \
    && passa "add-repo forca gate: [] (politica de execucao zero)" || falha "add-repo: gate errado"
  tem "d['companies']['acme']['repos']['Acme - API']['slug'] == 'api-acme'" \
    && passa "add-repo nao mexeu nos repos vizinhos" || falha "add-repo: vizinho corrompido"
  [ "$(comentarios)" -ge "$COMENTARIOS_INICIAIS" ] \
    && passa "add-repo preservou os $COMENTARIOS_INICIAIS comentarios" \
    || falha "add-repo apagou comentario" "antes=$COMENTARIOS_INICIAIS agora=$(comentarios)"
else
  falha "add-repo: comando saiu com erro"
fi

# --- 2. base sem origin/ tem que ser RECUSADA ------------------------------
if "$EDIT" add-repo --company acme --name "Acme - Ruim" --slug ruim \
     --orca-repo-id 99999999-9999-9999-9999-999999999999 \
     --base main >/dev/null 2>&1; then
  falha "base sem origin/ foi ACEITA (deveria recusar)"
else
  tem "'Acme - Ruim' not in d['companies']['acme']['repos']" \
    && passa "recusa base sem origin/ e nao grava nada" || falha "recusou mas gravou"
fi

# --- 3. repo duplicado ------------------------------------------------------
if "$EDIT" add-repo --company acme --name "Acme - API" --slug dup \
     --orca-repo-id 88888888-8888-8888-8888-888888888888 \
     --base origin/main >/dev/null 2>&1; then
  falha "repo duplicado foi aceito"
else
  passa "recusa repo com nome que ja existe"
fi

# --- 4. empresa inexistente -------------------------------------------------
if "$EDIT" add-repo --company fantasma --name "X - API" --slug x \
     --orca-repo-id 77777777-7777-7777-7777-777777777777 \
     --base origin/main >/dev/null 2>&1; then
  falha "empresa inexistente foi aceita"
else
  passa "recusa empresa que nao existe"
fi

# --- 5. add-company ---------------------------------------------------------
if "$EDIT" add-company --key beta --linear-team BETA --wip-max 2 >/dev/null 2>&1; then
  valido && tem "d['companies']['beta']['linear_team'] == 'BETA'" \
    && passa "add-company cria a empresa" || falha "add-company: empresa errada"
  tem "d['companies']['acme']['repos']" \
    && passa "add-company nao mexeu na empresa existente" || falha "add-company: acme sumiu"
else
  falha "add-company: comando saiu com erro"
fi

# --- 5b. add-stack ----------------------------------------------------------
if "$EDIT" add-stack --name "Beta - API/App" --repos "Acme - API" "Acme - Web" >/dev/null 2>&1; then
  valido && tem "d['stacks']['Beta - API/App'] == ['Acme - API','Acme - Web']" \
    && passa "add-stack cria a stack com os membros certos" || falha "add-stack: membros errados"
  tem "'Acme - API/Web' in d['stacks']" \
    && passa "add-stack nao mexeu na stack existente" || falha "add-stack: stack vizinha sumiu"
  tem "len(d['companies']['acme']['repos']) >= 2" \
    && passa "add-stack nao tocou em companies" || falha "add-stack: vazou para companies"
else
  falha "add-stack: comando saiu com erro"
fi

# stack apontando para repo inexistente e o erro que quebra o ticket no meio
if "$EDIT" add-stack --name "X - A/B" --repos "Acme - API" "Nao Existe" >/dev/null 2>&1; then
  falha "add-stack aceitou repo que nao existe no registry"
else
  passa "recusa stack com repo inexistente"
fi

if "$EDIT" add-stack --name "So Um" --repos "Acme - API" >/dev/null 2>&1; then
  falha "add-stack aceitou stack de um repo so"
else
  passa "recusa stack com menos de dois repos"
fi

# --- 5c. rename-stack -------------------------------------------------------
# Renomear existe porque no Linear a etiqueta guarda o vinculo com os tickets:
# apagar e recriar perderia todos. O registry acompanha o mesmo movimento.
if "$EDIT" rename-stack --name "Beta - API/App" --to "Beta - App/API" >/dev/null 2>&1; then
  valido && tem "d['stacks']['Beta - App/API'] == ['Acme - API','Acme - Web']" \
    && passa "rename-stack troca a chave e preserva os membros" || falha "rename-stack: membros perdidos"
  tem "'Beta - API/App' not in d['stacks']" \
    && passa "rename-stack remove o nome antigo" || falha "rename-stack: nome antigo ficou"
  tem "'Acme - API/Web' in d['stacks']" \
    && passa "rename-stack nao mexeu nas outras stacks" || falha "rename-stack: vizinha afetada"
else
  falha "rename-stack: comando saiu com erro"
fi

if "$EDIT" rename-stack --name "Nao Existe" --to "X" >/dev/null 2>&1; then
  falha "rename-stack aceitou stack inexistente"
else
  passa "recusa renomear stack que nao existe"
fi

if "$EDIT" rename-stack --name "Beta - App/API" --to "Acme - API/Web" >/dev/null 2>&1; then
  falha "rename-stack aceitou nome que ja existe"
else
  passa "recusa renomear para nome ja usado"
fi

# --- 6. set-model no bloco de risco ----------------------------------------
if "$EDIT" set-model --role implementer_by_risk.medium --model sonnet --effort high >/dev/null 2>&1; then
  tem "d['defaults']['models']['implementer_by_risk']['medium'] == {'model':'sonnet','effort':'high'}" \
    && passa "set-model troca modelo e effort de um nivel" || falha "set-model: valor errado"
  tem "d['defaults']['models']['implementer_by_risk']['high']['model'] == 'opus'" \
    && passa "set-model nao contaminou os outros niveis" || falha "set-model: vazou para high"
  tem "d['defaults']['models']['reviewer'] == 'opus'" \
    && passa "set-model nao mexeu no reviewer" || falha "set-model: reviewer alterado"
else
  falha "set-model: comando saiu com erro"
fi

# --- 7. set-model num papel simples ----------------------------------------
"$EDIT" set-model --role planner --model sonnet >/dev/null 2>&1
tem "d['defaults']['models']['planner'] == 'sonnet'" \
  && passa "set-model troca papel simples" || falha "set-model: planner nao mudou"
tem "d['defaults']['models']['orchestrator'] == 'opus'" \
  && passa "set-model nao contaminou o orchestrator" || falha "set-model: vazou"

# --- 8. rm-repo -------------------------------------------------------------
ANTES_RM=$(comentarios)
if "$EDIT" rm-repo --name "Acme - Admin" >/dev/null 2>&1; then
  valido && tem "'Acme - Admin' not in d['companies']['acme']['repos']" \
    && passa "rm-repo remove o repo" || falha "rm-repo: repo continua la"
  tem "'Acme - API' in d['companies']['acme']['repos'] and 'Acme - Web' in d['companies']['acme']['repos']" \
    && passa "rm-repo deixou os vizinhos intactos" || falha "rm-repo: levou vizinho junto"
else
  falha "rm-repo: comando saiu com erro"
fi

# --- 9. idempotencia --------------------------------------------------------
SAIDA=$("$EDIT" set-model --role planner --model sonnet 2>&1)
grep -q "nada a fazer" <<<"$SAIDA" \
  && passa "repetir a mesma edicao nao faz nada" || falha "nao detectou no-op" "$SAIDA"

# --- 10. --dry-run nao grava ------------------------------------------------
HASH_ANTES=$(shasum "$TMP/registry.yaml" | awk '{print $1}')
"$EDIT" --dry-run set-model --role reviewer --model haiku >/dev/null 2>&1
[ "$(shasum "$TMP/registry.yaml" | awk '{print $1}')" = "$HASH_ANTES" ] \
  && passa "--dry-run nao grava" || falha "--dry-run gravou"

# --- 11. o arquivo continua util depois de tudo -----------------------------
FINAL=$(comentarios)
[ "$FINAL" -ge $((COMENTARIOS_INICIAIS - 2)) ] \
  && passa "depois de 8 edicoes ainda ha $FINAL comentarios (comecou com $COMENTARIOS_INICIAIS)" \
  || falha "sangria de comentarios" "comecou $COMENTARIOS_INICIAIS, terminou $FINAL"

echo
echo "  $OK ok, $FALHOU falha(s)"
[ "$FALHOU" -eq 0 ] || exit 1
