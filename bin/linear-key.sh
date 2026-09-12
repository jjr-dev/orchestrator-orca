# Resolucao da chave do Linear. Sourceie, nao execute:
#
#     . "$(dirname "${BASH_SOURCE[0]}")/linear-key.sh"
#
# Ordem: ambiente -> .env -> ~/.zshenv. A primeira que tiver valor ganha.
#
# Por que o .env existe: o precheck roda como filho do processo do Orca, que e
# um app de GUI. Ele nao le ~/.zshenv e so herda o ambiente do launchd que
# existia QUANDO O APP SUBIU. Se o Orca foi aberto antes de a chave existir — ou
# depois de um reboot, ja que `launchctl setenv` e volatil — a variavel
# simplesmente nao chega aqui, e o precheck sai 4 em silencio: o Orca le isso
# como "nada a fazer" e a automation nunca dispara.
#
# Um arquivo no disco nao tem esse problema. Esta sempre la, nao depende de
# ordem de inicializacao, e e obvio onde olhar quando falha.
#
# O ~/.zshenv continua sendo lido por ultimo, para nao quebrar quem ja tinha.
#
# Em nenhum dos dois casos damos `source`: extraimos com sed, para nao executar
# configuracao de shell arbitraria vinda de um arquivo de credencial.
#
# Isto mora em arquivo proprio porque vale para todo script que fala com a API
# crua do Linear. Duplicar o bloco garante que um dia so metade e corrigida.

__orch_le_chave() {  # <arquivo> <nome da variavel>
  [ -r "$1" ] || return 1
  local v
  v=$(
    grep -E "^[[:space:]]*(export[[:space:]]+)?$2=" "$1" 2>/dev/null \
      | tail -1 \
      | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/; s/[[:space:]]+$//'
  )
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

if [ -z "${LINEAR_API_KEY:-}" ]; then
  __orch_raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  LINEAR_API_KEY=$(__orch_le_chave "$__orch_raiz/.env" LINEAR_API_KEY) \
    || LINEAR_API_KEY=$(__orch_le_chave "$HOME/.zshenv" LINEAR_API_KEY) \
    || LINEAR_API_KEY=""
  export LINEAR_API_KEY
fi

if [ -z "${LINEAR_API_KEY:-}" ]; then
  __orch_raiz="${__orch_raiz:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  {
    echo "LINEAR_API_KEY nao definida."
    if [ -f "$__orch_raiz/.env" ]; then
      echo "  o arquivo $__orch_raiz/.env existe, mas a linha LINEAR_API_KEY= esta vazia."
      echo "  abra e preencha. O token e gerado em:"
    else
      echo "  crie o arquivo a partir do template e preencha:"
      echo "      cp $__orch_raiz/.env.example $__orch_raiz/.env"
      echo "  o token e gerado em:"
    fi
    echo "      Linear -> Settings -> Security & access -> Personal API keys"
    echo "  (no backend 'orca' nada disso e necessario: ./bin/registry-edit.py set-backend orca)"
  } >&2
  return 4 2>/dev/null || exit 4
fi
