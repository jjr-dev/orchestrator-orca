#!/usr/bin/env bash
# Resolve texto solto para a chave canonica de um repo ou de uma stack.
#
#   resolve-name.sh --repo  "witepay ui"        -> WitePay - UI
#   resolve-name.sh --stack "naturals api crm"  -> Naturals - API/CRM
#
# stdout: a chave canonica, exatamente uma. stderr: o motivo.
# saida 0 resolveu, 1 nao resolveu (ambiguo ou inexistente).
#
# Por que existe: a chave do registry precisa ser identica byte a byte a
# etiqueta `Repo/` do Linear — divergir num espaco deixa todo ticket daquele
# repo invisivel. Mas isso e uma exigencia entre o registry e o Linear, nao
# entre o registry e os seus dedos. Quem digita no chat nao deveria precisar
# lembrar se e "WitePay - UI" ou "WitePay UI".
#
# NUNCA adivinha entre dois candidatos. Ambiguidade sai como lista para quem
# chamou perguntar — criar ticket no repo errado custa uma leva inteira.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REG="$(cd "$DIR/.." && pwd)/registry.yaml"

TIPO=""
case "${1:-}" in
  --repo)  TIPO=repo ;;
  --stack) TIPO=stack ;;
  *) echo "uso: $(basename "$0") --repo|--stack \"<texto>\"" >&2; exit 2 ;;
esac
ALVO="${2:-}"
[ -n "$ALVO" ] || { echo "falta o texto a resolver" >&2; exit 2; }
[ -f "$REG" ] || { echo "registry.yaml nao existe" >&2; exit 2; }

python3 - "$REG" "$TIPO" "$ALVO" <<'PY'
import sys, re, yaml

reg, tipo, alvo = sys.argv[1], sys.argv[2], sys.argv[3]
d = yaml.safe_load(open(reg)) or {}

if tipo == "repo":
    chaves = [n for e in (d.get("companies") or {}).values() for n in (e.get("repos") or {})]
else:
    chaves = list(d.get("stacks") or {})

def normal(s):
    """so letras e digitos, minusculo: 'WitePay - UI' -> 'witepayui'"""
    return re.sub(r"[^a-z0-9]", "", s.lower())

def tokens(s):
    return [t for t in re.split(r"[^a-z0-9]+", s.lower()) if t]

if not chaves:
    print(f"nenhum {tipo} no registry", file=sys.stderr)
    sys.exit(1)

# Antes da escada: o texto e o nome exato de uma coisa do OUTRO tipo? Quem
# digita `--stack "Acme - API"` quase certamente trocou o flag. Resolver isso
# em silencio para "Acme - API/Web" despacharia dois workers em vez de um —
# uma diferenca que so apareceria depois, no Linear.
outro = (list(d.get("stacks") or {}) if tipo == "repo"
         else [n for e in (d.get("companies") or {}).values() for n in (e.get("repos") or {})])
outro_tipo = "stack" if tipo == "repo" else "repo"
for k in outro:
    if k == alvo or normal(k) == normal(alvo):
        print(f"'{alvo}' e o nome de um {outro_tipo}, nao de um {tipo}.", file=sys.stderr)
        print(f"  quis dizer --{outro_tipo} \"{k}\"?", file=sys.stderr)
        sys.exit(1)

# A escada para de descer no primeiro degrau que resolve. A ordem importa:
# "Partners UI" casa normalizado com "Partners - UI" e para ali, em vez de
# ficar ambiguo com "Partners - Admin UI" no degrau de tokens.
degraus = [
    ("exato",        lambda k: k == alvo),
    ("sem caixa",    lambda k: k.lower() == alvo.lower()),
    ("normalizado",  lambda k: normal(k) == normal(alvo)),
    ("por palavras", lambda k: all(t in tokens(k) for t in tokens(alvo))),
    ("por prefixo",  lambda k: all(any(p.startswith(t) for p in tokens(k)) for t in tokens(alvo))),
]

for nome, teste in degraus:
    achou = [k for k in chaves if teste(k)]
    if len(achou) == 1:
        print(achou[0])
        if nome != "exato":
            print(f"resolve-name: '{alvo}' -> '{achou[0]}' ({nome})", file=sys.stderr)
        sys.exit(0)
    if len(achou) > 1:
        print(f"'{alvo}' casa com {len(achou)} {tipo}s — seja mais especifico:", file=sys.stderr)
        for k in sorted(achou):
            print(f"    {k}", file=sys.stderr)
        sys.exit(1)

# nada casou: ofereca o mais parecido, para o humano nao ter que caçar
import difflib
perto = difflib.get_close_matches(alvo, chaves, n=3, cutoff=0.3)
print(f"nenhum {tipo} casa com '{alvo}'.", file=sys.stderr)
if perto:
    print("  talvez:", file=sys.stderr)
    for k in perto:
        print(f"    {k}", file=sys.stderr)
else:
    print(f"  os {tipo}s que existem:", file=sys.stderr)
    for k in sorted(chaves):
        print(f"    {k}", file=sys.stderr)
sys.exit(1)
PY
