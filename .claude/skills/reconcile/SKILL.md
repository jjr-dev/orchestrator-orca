---
name: reconcile
description: |
  Varre todas as empresas procurando trabalho travado: tickets orfaos em
  "Scheduled" ou "In Progress" sem dispatch vivo (devolve para "Ready for Agent"),
  triagens travadas em "Drafting" (devolve para "Draft"), portoes esperando
  resposta humana e worktrees que ja podem ser removidos. Roda no boot do Orca e
  sob demanda.
  Use sempre que aparecer "/reconcile", "reconcilia", "tem ticket travado?",
  "limpa os orfaos", depois de reiniciar a maquina ou o app, ou quando um ticket
  parecer parado sem worker.
---

# Reconciliacao

## Ancore-se na raiz antes de qualquer comando

As chamadas abaixo sao relativas, e o diretorio de trabalho persiste entre elas.
Rode isto primeiro — uma vez, e vale para a skill inteira:

```bash
cd "${ORCH_ROOT:-.}" && [ -f registry.example.yaml ] \
  || echo "nao estou na raiz do orquestrador: defina ORCH_ROOT ou entre nela"
```

Se reclamar, **pare e resolva**. Sessao aberta fora da raiz carrega estas skills
mas nao acha o `bin/` — e a falha aparece no meio do trabalho, nao no comeco.


Sem argumento: roda para todas as empresas do `registry.yaml`.

## Por que isto existe

O fluxo roda na maquina local. Ela dorme, o app reinicia, e o auto mode aborta a
sessao depois de bloqueios repetidos do classificador (3 seguidos ou 20 no total —
em modo nao interativo isso encerra a sessao, porque nao ha ninguem para responder
ao prompt).

Nada disso e bug. Sao estados esperados de um sistema que roda numa maquina de
trabalho. O que seria bug e ficar com ticket preso sem ninguem trabalhando nele.

## Procedimento

Antes de tudo, nomeie a sua aba:

```bash
./bin/name-terminal.sh "reconcile"
```


Para cada empresa, para cada ticket em `Scheduled` ou `In Progress`:

1. Tem task no Orca? (`orca orchestration task-list --json`)
2. Tem dispatch vivo? (`orca orchestration dispatch-show --task <id> --json`)
3. Tem worktree correspondente? (`orca worktree ps --json`)
4. Ultimo heartbeat ou atualizacao ha menos de 30 minutos?

Se qualquer resposta for nao:

- `orca orchestration task-update --id <taskId> --status failed --result '{"reason":"orfao"}'`
- mova o ticket para `Ready for Agent`
- comente no Linear: horario, estado encontrado, causa provavel
- se sobrou worktree com trabalho dentro, **nao remova**. Liste no relatorio para
  o humano decidir. Perder codigo aqui e pior que acumular worktree.

## Worker que nunca arrancou

Modo de falha distinto do orfao, e que os quatro testes acima **nao** pegam:
existe task, existe dispatch, existe worktree, existe terminal — mas o agente
nunca comecou.

Acontece porque o prompt tem centenas de linhas e o Claude Code trata colagem
grande como bloco de paste: o newline final e absorvido como texto em vez de
virar submit. A sessao fica viva com `[Pasted text #1 +N lines]` parado no input.
Observado em 30/07 no ACME-26. E intermitente — o ACME-25, mesma leva e mesmo
tamanho de prompt, submeteu normal.

O que denuncia, e as duas condicoes tem que valer juntas:

1. **`last_heartbeat_at` e `null`** no `orca orchestration dispatch-show --task <id> --json`
2. **nenhum agente em `working`** no worktree correspondente

```bash
orca worktree ps --json | jq -r '.result.worktrees[]
  | select(.path|test("workspaces"))
  | [.agents[]?.state] as $s
  | "\(.displayName)  agentes=\(if ($s|length)==0 then "NENHUM" else ($s|join(",")) end)"'
```

Cuidado com `// "nenhum"`: `join` num array vazio devolve `""`, que nao e `null`,
entao o operador de default nao dispara e o campo sai em branco. Use `length==0`.

Heartbeat nulo sozinho nao basta: worker recem-despachado ainda nao mandou o
primeiro. Por isso exija tambem que o dispatch tenha mais de ~5 minutos.

Diferente dos outros casos desta skill, aqui **voce pode agir**: mandar um Enter
e nao-destrutivo e resolve na hora.

```bash
orca terminal send --terminal <handle> --text "" --enter --json
```

Confira depois se apareceu agente em `working`. Se sim, resolvido — registre no
relatorio como `DESTRAVADO`. Se nao, **nao redespache**: worktree e terminal ja
existem e um `worker-start` novo duplicaria o worker. Liste como
`WORKER PARADO` com o handle, e deixe para o humano.

## Triagem que morreu no meio

A triagem faz claim movendo o ticket de `Draft` para `Drafting`, antes de ler
codigo — e o que impede duas triagens no mesmo ticket. Se a sessao morrer no
meio, o ticket fica em `Drafting` sem ninguem trabalhando nele.

E ai ele desaparece. O `has-triage.sh` so olha `Draft`, entao ele nunca mais
volta para a fila sozinho. Fica na coluna de "sendo redigido" com a descricao
crua que o humano escreveu.

Este modo de falha nao passa por dispatch nenhum, entao os quatro testes acima
tambem nao o pegam — como o "worker que nunca arrancou", ele precisa de teste
proprio.

```bash
orca linear list-issues --team <linear_team> --state "Drafting" --limit 50 --json
```

O sinal e **tempo parado**: uma triagem viva mexe no ticket o tempo todo
(comentario, etiqueta, descricao), e cada mexida atualiza o `updatedAt`. Uma
triagem morta congela.

E orfao quando `updatedAt` tem **mais de 30 minutos**. Uma passagem inteira
levou 10,2 min no pior caso medido; 30 min e o triplo disso.

Diferente do claim orfao antigo — que era heuristica sobre o formato da
descricao — **aqui voce age**:

```bash
orca linear status set --id <IDENT> --to "Draft" --json
```

Pode agir porque devolver para `Draft` nao destroi nada. O ticket volta para a
fila com o que quer que tenha, e a proxima passagem melhora. No maximo voce
interrompeu uma triagem excepcionalmente lenta, que seria redespachada — custo de
uma passagem de 2 minutos.

Comente no ticket dizendo o horario e que foi devolvido por sessao travada, e
registre no relatorio:

```
TRIAGEM TRAVADA  <IDENT>  parado em Drafting ha 4h12  ->  devolvido para Draft
```

Ticket em `Draft` nunca aparece aqui, por mais velho que seja: ele esta na fila,
nao travado. Se a fila nao anda, o problema e a automation — cheque o `PAUSE` e
o `state/triage.lock`.

## Terminais acumulados no painel

As automations usam `--reuse-session`, mas o reuso so acontece se a sessao
anterior ainda existir. Quando ela encerra, o Orca cria uma nova — e elas
acumulam no worktree do painel. Em 03/08 havia **9** ali, 8 ja terminadas.

Sao sessoes de coordenacao, nao de worker: o relatorio ja foi impresso e todo o
estado que importa esta no Linear e no git. Descartaveis.

Feche as que satisfizerem TODAS:

1. estao no worktree do **painel** (`a raiz do orquestrador`)
2. `lastOutputAt` e `null`, ou mais velho que **60 minutos**
3. **nao** sao a de `lastOutputAt` mais recente

```bash
orca terminal list --worktree "path:$(pwd)" --json | jq -r '
  (.result.terminals | max_by(.lastOutputAt // 0) | .handle) as $atual
  | .result.terminals[]
  | select(.handle != $atual)
  | select((.lastOutputAt == null) or ((now*1000 - .lastOutputAt) > 3600000))
  | .handle'
```

Para cada handle: `orca terminal close --terminal <handle> --json`

**A regra 3 e a que protege voce de si mesmo.** Nao existe `terminal current` nem
variavel de ambiente que diga qual e o seu terminal. Mas a sessao que esta
rodando este comando e, por definicao, a que produziu output agora — entao ela e
sempre o `max_by(lastOutputAt)`. A regra 2 e a segunda barreira: uma sessao viva
nunca tem 60 minutos de silencio.

**NUNCA use `orca terminal stop --worktree`.** Ele derruba todos de uma vez,
inclusive o seu — a limpeza se mataria no meio, deixando o relatorio pela metade.
O hook bloqueia, mas a razao importa mais que o bloqueio.

**So o painel.** Terminal em worktree de worker nao entra aqui: ele guarda o
transcript do trabalho, que voce pode querer ler se o PR estiver estranho. Esses
saem junto com o worktree, pela secao de limpeza abaixo.

Reporte em uma linha: `TERMINAIS  N fechados no painel`. Se nao fechou nenhum,
nao escreva nada.

## Worktrees de ticket que ja podem sair

Isto e a maior fonte de lixo do fluxo: **43 worktrees de ticket / 49 GB** na
medicao de 17/08, acumulando desde julho sem nunca sair sozinhos.

Voce **nao** decide worktree a worktree. Rode o script:

```bash
./bin/cleanup-worktrees.sh --apply
```

Ele varre todos os repos, considera **so** as branches do padrao
`acme-dev/acme-<N>-` — worktree que voce criou na mao nunca entra — e remove
apenas quem passa nas quatro condicoes:

| # | Condicao | Comando |
|---|---|---|
| 1 | nada por commitar | `git status --short` vazio |
| 2 | nenhum commit local fora do remoto | `git log HEAD --not --remotes` vazio |
| 3 | PR daquela branch `MERGED` | `gh pr list --state merged` |
| 4 | ticket em `Done` | consulta em lote no Linear |

Falhou qualquer uma, ele mantem e diz o motivo em uma palavra.

**Por que script e nao voce fazendo na mao:** as quatro condicoes sao objetivas e
nao pedem julgamento. Script e auditavel, idempotente e testavel; agente
decidindo caso a caso, toda manha, e uma chance por dia de apagar codigo que
ninguem tinha empurrado. Por isso `orca worktree rm` continua bloqueado no hook —
o script e o unico caminho sancionado.

Sem `--apply` ele so lista. Use assim se quiser conferir antes.

Ele tambem apaga, no fim, as pastas de anexo baixadas pelo `linear-assets.sh`
para tickets que ja estao `Done` ou sumiram do Linear — regra separada, porque a
triagem baixa anexo de ticket que talvez nunca vire worktree.

Reporte a ultima linha da saida, literal:

```
LIMPEZA  43 do orquestrador · 31 seguros para remover · 4 pasta(s) de anexo
```

Se algum falhar na remocao, transcreva a linha `-> FALHOU ao remover` junto.
Nao tente remover pelo `orca worktree rm` — o hook barra, e com razao.

## Ticket pai fora de sincronia com os filhos

Quando o escopo atravessa repos, o ticket vira pai com uma sub-issue por
repositorio. O pai nao tem worker e nao tem PR — ninguem nunca o move, entao ele
fica em `Drafted` enquanto os filhos passam por todo o ciclo. No quadro parece
que aquilo esta parado.

O `pull-ready` e o worker ja atualizam o pai nos momentos em que agem. Mas o
ultimo passo, `Done`, e sempre humano e acontece fora de qualquer sessao de
agente: voce mergeia os dois PRs, move os dois filhos, e o pai fica para tras.
Por isso a varredura mora aqui.

```bash
./bin/sync-parent-status.sh --apply
```

Sem argumento varre todos os pais do time. A regra e do script, nao sua:

| Filhos (ignorando os em Draft/Drafting/Drafted) | Pai vai para |
|---|---|
| todos em `Scheduled` ou adiante | `In Progress` |
| todos em `In Review` ou adiante | `In Review` |
| todos em `Done` | `Done` |

Um filho em `Ready for Agent` segura o pai: ali o humano ja aprovou e o trabalho
so nao arrancou ainda. E o script **nunca volta estado** — se a conta der para
tras, ele reporta e nao mexe, porque voltar desfaria acao humana deliberada.

Transcreva as linhas com `-> movido`:

```
PAI  ACME-84  In Review -> Done
```

## Metadata dos worktrees fora de sincronia

O nome, o link do ticket e a coluna do board de cada worktree sao gravados no
despacho — mas o estado no Linear muda depois disso, o dia inteiro. Uma varredura
por dia realinha tudo:

```bash
./bin/sync-worktree-meta.sh
```

Sem argumento varre todos os worktrees de ticket. So escreve metadata do Orca:
nao mexe no Linear, nao toca em codigo, e por isso nao tem dry-run.

Worktree cujo ticket foi apagado ele pula com uma linha, sem falhar.

Reporte so o total: `METADATA  19 worktrees sincronizados`.

## Portoes abertos esperando humano

Orfao nao e o unico jeito de um ticket travar. Um worker que abriu decision gate
ou `orca orchestration ask` fica **vivo e parado** — dispatch existe, heartbeat
recente, worktree no lugar. Os quatro testes acima passam e o procedimento nao
acusa nada, mas ninguem esta trabalhando no ticket.

Por isso, sempre liste as perguntas pendentes:

```bash
orca orchestration check --terminal <handle do coordenador> --peek --json
```

Uma linha por mensagem `type: question`, com o comando pronto:

```
GATE  <msg_id>  <ticket>  <resumo em <=10 palavras>
      responder: orca orchestration reply --id <msg_id> --body "<...>" --json
```

**Nao responda voce mesmo** e **nao devolva o ticket para `Ready for Agent`** —
o worker esta vivo e tem contexto que voce nao tem. Devolver mataria trabalho
feito. Seu papel aqui e so tornar o portao visivel.

## Relatorio

| Ticket | Estado encontrado | Acao | Worktree orfao |
|---|---|---|---|

Depois da tabela, nesta ordem e so o que existir:

1. `DESTRAVADO` / `WORKER PARADO` — worker que nunca arrancou
2. `TRIAGEM TRAVADA` — triagem que morreu no meio, devolvida para `Draft`
3. `PAI` — tickets pai movidos para acompanhar os filhos
4. `METADATA` — worktrees realinhados com o Linear
5. `GATE` — portoes abertos esperando resposta
6. `TERMINAIS` — quantos fechados no painel
7. `LIMPEZA` — worktrees de ticket e pastas de anexo removidos

Secao vazia nao aparece. Este relatorio roda todo dia util as 8h e e a primeira
coisa que o humano le no dia: "nada a limpar" tres vezes treina a pessoa a nao
ler mais.

Se nao houver nada em nenhuma das sete categorias, responda `tudo consistente`
e pare.
