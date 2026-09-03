#!/usr/bin/env bash
# Helper minimo de GraphQL do Linear. Sem modelo, custo zero.
# Uso: linear-query.sh '<query graphql>'
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/linear-key.sh"

QUERY="$1"
curl -sS https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H 'Content-Type: application/json' \
  --data "$(jq -nc --arg q "$QUERY" '{query:$q}')"
