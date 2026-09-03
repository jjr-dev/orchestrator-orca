#!/usr/bin/env bash
# Instala os subagentes do orquestrador em ~/.claude/agents/.
#
# Por que global e nao no repo: quem invoca estes agentes e o WORKER, e o worker
# roda no worktree do cliente (/Volumes/XPG_SSD/developer/workspaces/...). O
# Claude Code so enxerga `.claude/agents/` do projeto atual e de ~/.claude —
# e escrever dentro do repo do cliente esta proibido. Sobra o global.
#
# Efeito colateral aceito: estes dois agentes aparecem em QUALQUER sessao sua,
# nao so nas do orquestrador. Sao inertes ate serem chamados pelo nome, e o
# prefixo `orch-` existe para isso ficar obvio na lista.
#
# Fonte de verdade e o repo. Rode depois de mexer em .claude/agents/orch-*.md.

set -euo pipefail

ORIGEM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude/agents"
DESTINO="$HOME/.claude/agents"

mkdir -p "$DESTINO"

mudou=0
for src in "$ORIGEM"/orch-*.md; do
  [ -e "$src" ] || { echo "nenhum orch-*.md em $ORIGEM" >&2; exit 1; }
  nome="$(basename "$src")"
  dst="$DESTINO/$nome"

  # o `model:` e a razao de existir deste arquivo — se sumir, o agente herda o
  # modelo e o effort da sessao que o chamou, e a divisao de papeis vira
  # decoracao. O planner herdaria ate o teto rebaixado de um ticket `Risk/low`.
  modelo="$(sed -n 's/^model: *//p' "$src" | head -1)"
  if [ -z "$modelo" ]; then
    echo "ERRO: $nome nao declara 'model:' — abortando sem instalar nada" >&2
    exit 1
  fi

  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    printf '  =  %-22s %s\n' "$nome" "$modelo"
  else
    cp "$src" "$dst"
    printf '  ok %-22s %s\n' "$nome" "$modelo"
    mudou=$((mudou + 1))
  fi
done

echo "$mudou arquivo(s) atualizado(s) em $DESTINO"
