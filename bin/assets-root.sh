#!/usr/bin/env bash
# Onde os anexos baixados do Linear ficam. Imprime o caminho e nada mais.
#
# Ordem de resolucao:
#   1. $ORCH_ASSETS_ROOT             (override pontual)
#   2. defaults.assets_root          (o registry, que e a fonte da verdade)
#   3. $HOME/.orch-assets            (default portatil)
#
# Fica FORA de qualquer repositorio git de proposito: anexo nao pode ser
# commitado por acidente. Diferente do PLAN.md, que mora no worktree e por isso
# precisa do info/exclude.
#
# Se voce apontar para um volume externo, os scripts que escrevem aqui checam
# que ele esta montado antes de gravar — sem isso, uma montagem ausente criaria
# o ponto de montagem como diretorio comum e tudo pareceria funcionar.
set -uo pipefail

if [ -n "${ORCH_ASSETS_ROOT:-}" ]; then
  printf '%s\n' "$ORCH_ASSETS_ROOT"
  exit 0
fi

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DO_REGISTRY=$(python3 -c '
import sys, yaml
try:
    d = yaml.safe_load(open(sys.argv[1])) or {}
except Exception:
    d = {}
print(((d.get("defaults") or {}).get("assets_root") or "").strip())
' "$RAIZ/registry.yaml" 2>/dev/null)

if [ -n "${DO_REGISTRY:-}" ]; then
  printf '%s\n' "${DO_REGISTRY/#\~/$HOME}"
else
  printf '%s\n' "$HOME/.orch-assets"
fi
