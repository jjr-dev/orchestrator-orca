#!/usr/bin/env bash
# Baixa as imagens e arquivos anexados a um ticket do Linear. Sem modelo, custo zero.
#
# Uso: linear-assets.sh <IDENT> [dest-root]
#      linear-assets.sh ACME-51
#
# Imprime uma linha por arquivo, com o caminho local e a URL de origem, para o
# agente correlacionar com os `![](...)` que aparecem na descricao. Sem anexo,
# imprime uma linha so e sai 0 — ausencia de imagem nao e erro.
#
# Por que existe: `uploads.linear.app` NAO e publico (401 sem auth, medido em
# 28/08). WebFetch nao resolve nem com URL na mao, e nao le imagem de qualquer
# forma. O unico caminho e baixar com a chave e apontar o arquivo local, que o
# Read do Claude Code le como imagem de verdade.
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/linear-key.sh"

IDENT="${1:?uso: linear-assets.sh <IDENT> [dest-root]}"
ROOT="${2:-${ORCH_ASSETS_ROOT:-/Volumes/XPG_SSD/developer/.orch-assets}}"

TEAM="${IDENT%%-*}"
NUM="${IDENT##*-}"
if [ "$TEAM" = "$IDENT" ] || ! [[ "$NUM" =~ ^[0-9]+$ ]]; then
  echo "IDENT invalido: '$IDENT' (esperado algo como ACME-51)" >&2
  exit 2
fi

case "$ROOT" in
  /*) ;;
  *) echo "dest-root precisa ser caminho absoluto (veio: '$ROOT') — configure ORCH_ASSETS_ROOT" >&2; exit 2 ;;
esac

# O volume externo pode estar desmontado. Se estiver, PARE: escrever no disco
# interno e justamente o que nao queremos, e o erro seria silencioso — o mkdir
# criaria /Volumes/XPG_SSD como diretorio comum e tudo pareceria funcionar.
VOL="/$(printf '%s' "${ROOT#/}" | cut -d/ -f1-2)"
if [ "${ROOT#/Volumes/}" != "$ROOT" ] && ! mount | grep -q " on $VOL "; then
  echo "volume '$VOL' nao esta montado — nao vou baixar para o disco interno" >&2
  exit 2
fi

DEST="$ROOT/$IDENT"

Q=$(printf '{ issues(filter: { team: { key: { eq: "%s" } } number: { eq: %s } }, first: 1) { nodes { description comments { nodes { body } } attachments { nodes { url } } } } }' "$TEAM" "$NUM")

URLS=$(
  "$(dirname "${BASH_SOURCE[0]}")/linear-query.sh" "$Q" \
    | python3 -c '
import json,re,sys
d=json.load(sys.stdin,strict=False)
n=d.get("data",{}).get("issues",{}).get("nodes") or []
if not n: sys.exit(0)
i=n[0]
blob=(i.get("description") or "")
blob+="\n".join(c["body"] or "" for c in i["comments"]["nodes"])
blob+="\n".join(a["url"] or "" for a in i["attachments"]["nodes"])
seen=[]
for u in re.findall(r"https://uploads\.linear\.app/[^)\"'"'"'\s<>]+", blob):
    if u not in seen: seen.append(u)
print("\n".join(seen))
'
)

if [ -z "$URLS" ]; then
  echo "nenhum anexo em $IDENT"
  exit 0
fi

# So agora: ticket sem anexo nao deixa diretorio vazio para tras. A maioria dos
# tickets nao tem imagem, e a triagem chama isto em todos.
mkdir -p "$DEST"

ext_de() {
  case "$1" in
    image/png) echo png ;; image/jpeg) echo jpg ;; image/gif) echo gif ;;
    image/webp) echo webp ;; image/heic) echo heic ;; image/svg+xml) echo svg ;;
    application/pdf) echo pdf ;; *) echo bin ;;
  esac
}

i=0; ok=0
while IFS= read -r url; do
  [ -n "$url" ] || continue
  i=$((i+1))
  tmp="$DEST/.dl-$i"
  read -r code ctype < <(
    curl -sS -L -H "Authorization: $LINEAR_API_KEY" \
      -o "$tmp" -w '%{http_code} %{content_type}\n' "$url" || echo "000 -"
  )
  if [ "$code" != "200" ]; then
    rm -f "$tmp"
    echo "FALHOU  http=$code  $url" >&2
    continue
  fi
  base=$(basename "${url%%\?*}")
  case "$base" in
    *.*) nome="$IDENT-$i-$base" ;;
    *)   nome="$IDENT-$i.$(ext_de "${ctype%%;*}")" ;;
  esac
  mv -f "$tmp" "$DEST/$nome"
  printf '%s  %s  %s  <- %s\n' "$DEST/$nome" "${ctype%%;*}" \
    "$(du -h "$DEST/$nome" | cut -f1)" "$url"
  ok=$((ok+1))
done <<< "$URLS"

echo "$ok de $i anexo(s) em $DEST"
