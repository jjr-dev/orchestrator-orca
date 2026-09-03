# Resolucao da chave do Linear. Sourceie, nao execute:
#
#     . "$(dirname "${BASH_SOURCE[0]}")/linear-key.sh"
#
# O precheck roda como filho do processo do Orca, que e um app de GUI: ele nao
# le ~/.zshenv e so herda o ambiente do launchd que existia QUANDO O APP SUBIU.
# Se o Orca foi aberto antes de a chave existir — ou depois de um reboot, ja que
# `launchctl setenv` e volatil — a variavel simplesmente nao chega aqui, e o
# precheck sai 4 em silencio: o Orca le isso como "nada a fazer" e a automation
# nunca dispara.
#
# Por isso, quando o ambiente nao traz a chave, lemos do arquivo. Extraimos com
# sed em vez de dar `source`: assim nao executamos config de shell arbitraria.
#
# Isto mora em arquivo proprio porque vale para todo script que fala com a API
# crua do Linear. Duplicar o bloco garante que um dia so metade e corrigida.

if [ -z "${LINEAR_API_KEY:-}" ] && [ -r "$HOME/.zshenv" ]; then
  LINEAR_API_KEY=$(
    grep -E '^[[:space:]]*export[[:space:]]+LINEAR_API_KEY=' "$HOME/.zshenv" \
      | tail -1 \
      | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
  )
  export LINEAR_API_KEY
fi

: "${LINEAR_API_KEY:?defina LINEAR_API_KEY no ambiente ou em ~/.zshenv}"
