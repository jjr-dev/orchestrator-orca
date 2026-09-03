#!/usr/bin/env bash
# Hook PreToolUse. Recebe JSON no stdin. Exit 2 bloqueia a chamada.
#
# Por que isto existe mesmo com auto mode:
# o classificador bloqueia o que e INSEGURO. Docker e teste e2e nao sao
# inseguros, sao caros e lentos. Essa politica e nossa, nao dele.
set -uo pipefail

block() {
  echo "BLOQUEADO pelo guard-commands.sh: $1" >&2
  echo "Nao contorne. Se o ticket precisa disto, registre no roteiro de verificacao manual do PR." >&2
  exit 2
}

# Falha fechada: sem jq nao da para inspecionar o comando, entao nao liberamos.
command -v jq >/dev/null 2>&1 || block "jq nao encontrado — instale jq (o hook nao libera sem conseguir ler o comando)"

INPUT="$(cat)"
TOOL="$(jq -r '.tool_name // empty' <<<"$INPUT")"
[ "$TOOL" = "Bash" ] || exit 0
CMD="$(jq -r '.tool_input.command // empty' <<<"$INPUT")"
[ -n "$CMD" ] || exit 0

# Politica de custo: nada que suba servico ou rode suite pesada.
grep -Eq '(^|[;&|(`[:space:]])docker([[:space:]]|$)'                    <<<"$CMD" && block "docker"
grep -Eq 'docker[-[:space:]]compose'                                    <<<"$CMD" && block "docker compose"
grep -Eq '(^|[;&|(`[:space:]])(podman|kubectl|helm)([[:space:]]|$)'     <<<"$CMD" && block "orquestrador de container"
grep -Eq 'playwright|cypress|(^|[[:space:]])k6([[:space:]]|$)'          <<<"$CMD" && block "suite e2e / carga"
grep -Eq 'test:e2e|test:integration|:e2e([[:space:]]|$)'                <<<"$CMD" && block "suite e2e / integracao"

# Este hook vale para o PAINEL, que nunca precisa rodar comando de projeto.
# O `gate` do registry e opt-in por repo e roda no WORKER, noutro worktree, onde
# este hook nao chega — entao ele nao conflita com gate nenhum.
# Motivo adicional: memoria. jest/vitest sobem ~1 worker por nucleo, e um
# servidor de dev fica vivo indefinidamente — com varios workers simultaneos
# isso derruba a maquina antes de qualquer docker.

# Runners de teste chamados direto (sem passar por script do package.json)
grep -Eq '(^|[;&|(`[:space:]/])(jest|vitest|phpunit|pytest|mocha)([[:space:]]|$)'  <<<"$CMD" && block "runner de teste"

# Servidores de desenvolvimento: sobem processo que nao morre sozinho
grep -Eq 'artisan[[:space:]]+serve'                                     <<<"$CMD" && block "sobe servico de desenvolvimento"
grep -Eq '(^|[;&|(`[:space:]/])(next|nuxt|vite|nest)[[:space:]]+(dev|start)' <<<"$CMD" && block "sobe servico de desenvolvimento"
grep -Eq 'artisan[[:space:]]+test'                                      <<<"$CMD" && block "teste (a verificacao e humana)"

# Instalar runtime ou ferramenta NA MAQUINA e mudanca de ambiente, nao trabalho
# de ticket. Esta maquina nao tem php, composer nem pnpm de proposito; se um
# comando falhar por isso, o worker documenta e segue — nao instala nada.
grep -Eq '(^|[;&|(`[:space:]])sudo([[:space:]]|$)'                      <<<"$CMD" && block "sudo"
grep -Eq '(^|[;&|(`[:space:]])(brew|apt|apt-get|port|dnf|yum|pacman|asdf|mise)[[:space:]]+(install|add|upgrade|reinstall)' <<<"$CMD" && block "instalacao de runtime/ferramenta na maquina"

# Toolchain mobile/nativo. Nao entra na regra de gerenciador de pacote abaixo
# porque nao sao npm-like, e sao os mais caros de todos:
#   flutter run    sobe app em emulador e fica vivo
#   flutter build  / gradlew / xcodebuild  compilam por minutos
#   eas build      builda na NUVEM e custa dinheiro
# flutter e dart estao instalados nesta maquina, entao isto executaria de verdade
# — diferente de composer, que falharia por falta de php.
grep -Eq '(^|[;&|(`[:space:]/])(flutter|dart|fvm|melos)[[:space:]]'         <<<"$CMD" && block "toolchain Flutter/Dart"
grep -Eq '(^|[;&|(`[:space:]/])(eas|expo)[[:space:]]'                       <<<"$CMD" && block "toolchain Expo/EAS"
grep -Eq '(^|[;&|(`[:space:]/])(pod|xcodebuild|gradle)[[:space:]]'          <<<"$CMD" && block "build nativo"
grep -Eq '(^|[;&|(`[:space:]/])\./gradlew'                                  <<<"$CMD" && block "build nativo"

# Code push / deploy de app: shorebird publica direto para o usuario final,
# sem passar por loja nem por review. E a coisa mais perigosa deste repositorio.
grep -Eq '(^|[;&|(`[:space:]/])shorebird[[:space:]]'                        <<<"$CMD" && block "code push / deploy de app"
grep -Eq '(^|[;&|(`[:space:]/])firebase[[:space:]]+(deploy|hosting|functions)' <<<"$CMD" && block "deploy Firebase"

# Gerenciador de pacote, INCLUSIVE instalar dependencia do projeto.
# Motivo: `npm install` reescreve package-lock.json e `yarn install` mexe no
# yarn.lock quando ha divergencia de versao — isso entraria no PR como mudanca
# que ninguem pediu. E o worker nao precisa: ele le codigo como texto e escreve
# codigo; sem typecheck e sem build, node_modules nao serve para nada aqui.
# Onde o repo precisa de deps, o hook de setup do Orca ja faz rsync.
grep -Eq '(^|[;&|(`[:space:]])(npm|yarn|pnpm|bun|npx|composer|pip|pip3|poetry|bundle|gem|cargo|go)[[:space:]]' <<<"$CMD" && block "gerenciador de pacote — o humano instala quando precisar"

# Politica de estado: o orquestrador e global, um worker nao pode zerar.
grep -Eq 'orca[[:space:]]+orchestration[[:space:]]+reset'               <<<"$CMD" && block "orca orchestration reset"
# `orca worktree rm` na mao continua BLOQUEADO de proposito: disco e recuperavel,
# codigo nao-pushado nao e, e um agente decidindo caso a caso e uma chance por dia
# de errar.
#
# O caminho sancionado e `bin/cleanup-worktrees.sh`, que confere as quatro
# condicoes (nada por commitar, nada fora do remoto, PR mergeado, ticket Done)
# antes de remover qualquer coisa. Ele passa por este hook porque a linha de
# comando dele nao contem "orca worktree rm" — isso e INTENCIONAL, nao um furo:
# a decisao mora num script auditavel e versionado, nao no julgamento do agente.
grep -Eq 'orca[[:space:]]+worktree[[:space:]]+rm'                       <<<"$CMD" && block "remocao de worktree na mao — use bin/cleanup-worktrees.sh"

# `terminal stop --worktree` derruba TODOS os terminais do worktree — inclusive o
# que esta rodando o comando. Uma limpeza que se mata no meio deixa o relatorio
# pela metade e o ticket sem quem o mova. Fechar um a um com `terminal close`
# continua liberado, e e o unico jeito seguro.
grep -Eq 'orca[[:space:]]+terminal[[:space:]]+stop'                     <<<"$CMD" && block "orca terminal stop (derruba o proprio terminal junto)"

# Migrations: o auto mode ja barra producao, aqui barramos qualquer uma.
grep -Eq '(migrate|migration).*(deploy|run|up|latest)'                  <<<"$CMD" && block "migration"
grep -Eq 'prisma[[:space:]]+migrate|drizzle-kit[[:space:]]+push'        <<<"$CMD" && block "migration"

# Migration exposta como script do package.json escapava dos dois padroes acima:
# "yarn prisma:migrate" nao tem espaco depois de prisma, e nao tem sufixo
# deploy/run/up/latest. E ainda assim roda `prisma migrate dev` e altera o banco.
grep -Eq '(prisma|db|typeorm|drizzle)[:_-]migrat'                       <<<"$CMD" && block "migration via script do package.json"
grep -Eq 'migrat(e|ion)[:_-](dev|deploy|run|up|latest)'                 <<<"$CMD" && block "migration via script do package.json"

# Laravel: `php artisan migrate` nao casa com nenhum padrao acima (nao tem
# sufixo nem separador). Cobre migrate, migrate:fresh, migrate:rollback,
# db:seed e db:wipe — este ultimo apaga o banco inteiro.
grep -Eq 'artisan[[:space:]]+(migrate|db:)'                             <<<"$CMD" && block "migration/db via artisan"

exit 0
