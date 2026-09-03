# Armadilhas que ja custaram caro

Nao redescubra estas. Cada uma custou horas, e nenhuma levantou erro.

## Do fluxo

- **`orca orchestration ask` e proibido neste fluxo.** Ele bloqueia por 10 min e
  ninguem le a caixa de entrada do coordenador. Um worker desistiu no timeout;
  outro entrou em loop de `--resume` ate a sessao estourar. O worker comenta no
  ticket e segue.
- **Reconciliacao antes de despachar, sempre.** A maquina dorme, o app reinicia,
  a sessao morre. Ticket preso sem worker e o estado que voce precisa cacar.
- **Prompt muito grande pode nao ser submetido.** O Claude Code trata colagem
  grande como bloco de paste e absorve o newline final; a sessao fica viva com o
  prompt parado no input. Sinal: `last_heartbeat_at: null` **e** nenhum agente
  em `working`. Conserto: mandar um Enter no terminal.
- **Os flags do Orca mudam entre versoes.** Ja mudaram duas vezes: `--cron`
  virou `--trigger`, `--agent` virou `--provider`, e `--reuse-session` saiu. Rode
  `--help` antes de agir; nao confie em script congelado.

## Do Linear

- **A API devolve o nome da etiqueta SEM o prefixo do grupo.** `Repo/Acme - API`
  e so como a interface exibe; via GraphQL vem `name: "Acme - API"` com
  `parent: { name: "Repo" }`. Filtre por `parent.name`. Um filtro
  `startswith("Repo/")` nunca casaria — e o sistema ficaria mudo.
- **`status` e nome reservado.** Criar um grupo chamado `Status` e recusado com
  *«The label name "status" is reserved»*. Por isso `Fast Track` e plana.
- **`position` ordena DENTRO do grupo de `type`, nao globalmente.** Marcar
  `Drafting` como `started` o jogaria para o grupo do `Scheduled` e ele
  apareceria no board depois de `Drafted`, com a ordem invertida.
- **Renomear estado mata o precheck.** Os scripts casam por nome exato. Crie o
  que falta em vez de renomear o que existe.

## Do ambiente

- **App de GUI nao enxerga o `~/.zshenv`.** O Orca herda o ambiente do launchd
  de quando foi aberto; chave criada depois nao chega nele. O
  `bin/linear-key.sh` contorna lendo o arquivo direto, mas so scripts nossos
  passam por ele.
- **`~/.zshenv`, nao `.zshrc`.** O `.zshrc` so e lido por shell interativo, e os
  prechecks do cron rodam em shell nao interativo.
- **`GID` e `path` sao variaveis especiais do zsh.** Atribuir a `GID` da
  *"failed to change group ID"*; atribuir a `path` destroi o `$PATH` e todo
  comando externo passa a falhar em silencio enquanto os builtins continuam
  funcionando. Use outros nomes.
- **`sed -E` do BSD (macOS) nao suporta `\b`.** A substituicao nao faz nada e
  nao avisa.
- **`timeout` nao existe no macOS.**
- **`jq`: `join(",") // "default"` nao dispara em array vazio** — `join` devolve
  `""`, que nao e `null`. Use `if (x|length)==0`.

## Do git

- **`base` PRECISA do prefixo `origin/`.** Sem ele o Orca usa a ref local sem
  tocar na rede, e o worker implementa em cima de codigo velho. O PR abre, passa
  no review, e so aparece como conflito no merge. Medido: 10 de 20 refs locais
  estavam atrasadas em relacao ao remoto.

## Sobre confiar em configuracao

Duas falhas reais, ambas descobertas por acaso semanas depois:

- o hook `guard-commands.sh` estava registrado num `settings.json` que o worker
  nunca leu. 258 comandos de projeto passaram sem barreira.
- o bloco `models` do registry era decoracao: nada lia aqueles valores, e tudo
  rodava no modelo padrao. Sonnet era 0,07% dos tokens de saida.

E por isso que existe `./bin/doctor.sh`. Valor de configuracao sem um lugar
concreto que o aplique nao faz nada — e nao avisa.
