#!/usr/bin/env bash
# Monta o prompt do `orch-planner` ou do `orch-reviewer`.
#
#   subagent-prompt.sh planner  <IDENT> [--worktree <path>] [--repo "<Nome>"]
#   subagent-prompt.sh reviewer <IDENT> [--worktree <path>] [--repo "<Nome>"]
#
# Existe porque montar isto com o modelo custava caro e nao comprava nada.
# Medido no JJR-294 (12/09): o worker gastou 44 s em Opus/xhigh para escrever
# 228 tokens de prompt do planner, e mais 25 s para o do reviewer. O conteudo e
# mecanico — IDENT, caminho, repo, base branch, risco, regras do ambiente e a
# spec colada — e sai inteiro do registry mais o ticket.
#
# Efeito colateral que vale tanto quanto o tempo: o prompt para de variar entre
# execucoes. Antes, cada worker redigia o seu, e duas sessoes no mesmo ticket
# davam prompts diferentes para o planner sem ninguem perceber.
#
# Roda no worktree do CLIENTE, entao resolve tudo por caminho absoluto a partir
# da propria localizacao.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "$DIR/.." && pwd)"

PAPEL="${1:-}"; IDENT="${2:-}"; shift 2 2>/dev/null || true
case "$PAPEL" in planner|reviewer) ;; *)
  echo "uso: $(basename "$0") planner|reviewer <IDENT> [--worktree <path>] [--repo \"<Nome>\"]" >&2; exit 2 ;;
esac
[ -n "$IDENT" ] || { echo "falta o IDENT" >&2; exit 2; }

WORKTREE="$(pwd)"; REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree) WORKTREE="${2:?}"; shift 2 ;;
    --repo)     REPO="${2:?}";     shift 2 ;;
    *) echo "flag desconhecida: $1" >&2; exit 2 ;;
  esac
done

export ORCH_SUBAGENT_RAIZ="$RAIZ" ORCH_SUBAGENT_WT="$WORKTREE" \
       ORCH_SUBAGENT_REPO="$REPO" ORCH_SUBAGENT_PAPEL="$PAPEL" ORCH_SUBAGENT_IDENT="$IDENT"

python3 "$DIR/subagent-prompt.py"
