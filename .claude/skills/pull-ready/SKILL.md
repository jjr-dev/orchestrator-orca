---
name: pull-ready
description: |
  Puxa os tickets do Linear que estao em "Ready for Agent", valida se estao
  realmente prontos, faz o claim movendo para "Scheduled" e despacha um worker
  autonomo por ticket no worktree do repositorio correto. Roda em loop pela
  automation do Orca, mas tambem pode ser chamada na mao.
  Use sempre que aparecer "/pull-ready", "puxa os tickets prontos", "roda o
  poller", "tem algo pronto para agente?", ou quando uma automation do Orca
  disparar com o nome de uma empresa como argumento.
---

# Puxar tickets prontos e despachar

Argumento: `$ARGUMENTS` = chave da empresa no `registry.yaml` (ex: `acme`), para
restringir a execucao a uma so empresa.

**Sem argumento, roda para todas as empresas do registry.** E assim que a
automation chama. Nunca pergunte qual empresa: em execucao por cron nao ha
ninguem para responder, e a sessao trava ate o timeout.

Workspace unico: existe um so time no Linear (`linear_team`, igual nas tres
empresas). A empresa de um ticket nao vem do time — vem da etiqueta `Repo/`,
resolvida pelo `registry.yaml`. Cada etiqueta `Repo/` pertence a exatamente uma
empresa, entao a resolucao e sempre determinista.

Voce e o coordenador. Nao escreve codigo de ticket nenhum.

## Passo 0 - Contexto

1. `orca status --json` deve responder. Se nao responder, pare e reporte.
2. `orca skills get orchestration --full` — os flags mudam por versao do app.
   Siga a saida desse comando, nao exemplos memorizados.
3. Leia `registry.yaml` e guarde: `linear_team`, `wip_max`, e o mapa
   etiqueta -> `{orca_repo_id, base, setup, gate, manual, ci, pair, plan_gate, risk_default}`.

4. **Confira que todo `base` comeca com `origin/`.** Repo cujo `base` nao
   comece assim: **nao despache**, liste no relatorio e siga com os outros.

   O Orca so busca o remoto quando a base e uma ref de rastreamento. Com
   `origin/development` ele roda
   `fetch --no-tags origin +refs/heads/development:refs/remotes/origin/development`
   e corta a branch do tip recem-buscado. Com `development` puro ele usa a ref
   local, que pode estar dias atras — medido em 10/08: 10 dos 20 `origin/<base>`
   locais estavam atrasados em relacao ao remoto.

   Falha silenciosa: o worker implementa sobre codigo velho, o PR abre normal, e
   so aparece no conflito de merge. Por isso a checagem e aqui, antes de qualquer
   despacho, e nao no worker.

### Nomeie a sua aba antes de trabalhar

```bash
./bin/name-terminal.sh "despacho"
```

Os terminais do painel nasciam todos sem nome — com as automations mais o chat,
davam 8 abas identicas. Renomeie de novo no fim do Passo 6, ja com os tickets:
`"despacho ACME-140 +2"`.

## Passo 1 - Reconciliar (sempre primeiro, sem excecao)

Antes de despachar qualquer coisa nova, limpe o que ficou pendurado.

Para cada ticket em `Scheduled` ou `In Progress`, de todas as empresas no escopo:

- Existe dispatch vivo? (`orca orchestration task-list --json` e
  `orca orchestration dispatch-show --task <id> --json`)
- Existe worktree correspondente? (`orca worktree ps --json`)

Se nao existir nenhum dos dois, ou se o ultimo heartbeat tiver mais de 30 minutos:

1. Mova o ticket de volta para `Ready for Agent`.
2. Comente no Linear o que aconteceu, com o horario e a causa provavel.
3. Marque o dispatch como `failed` se ele ainda existir.

Causas esperadas e normais: a maquina dormiu, o app reiniciou, ou o auto mode
abortou a sessao depois de bloqueios repetidos. Nao trate como bug, trate como
estado.

### Issue pai: quem move

Issue pai nao tem etiqueta `Repo/`, entao nunca e despachada — e por isso
tambem nunca sai do lugar sozinha. Sem esta regra ela fica pendurada para sempre.

Para cada issue pai que nao esteja em `Done`, olhe os filhos:

```bash
orca linear issue <IDENT-do-pai> --children --json
```

O pai espelha o conjunto dos filhos. Avalie de baixo para cima e pare na primeira
que casar:

| Condicao nos filhos | Pai vai para |
|---|---|
| TODOS em `Done` | **`Manual QA`** |
| TODOS em `In Review` ou alem | **`In Review`** |
| ALGUM em `In Progress` ou alem | **`In Progress`** |
| nenhum comecou | fica onde esta |

Mova so quando o alvo for diferente do estado atual, e **nunca para tras** — se
o pai ja esta em `In Review` e um filho voltou para `In Progress` por
reconciliacao, deixe o pai onde esta e registre no relatorio.

**`Done` dos filhos, nao `In Review`, e o que libera o `Manual QA` do pai.** A
verificacao que o pai carrega e de integracao: rodar isso com os dois PRs ainda
abertos testaria duas branches nao mergeadas, o que nao prova nada. Quando os
dois estao `Done`, o codigo esta na base e a integracao e real.

Ao mover para `Manual QA`, comente listando os PRs dos filhos e lembre que o
roteiro ponta a ponta esta na descricao do pai.

**Algum filho `Canceled`** → nao mova o pai. Comente que a quebra mudou e siga.
Nao decida sozinho se o escopo restante ainda faz sentido.

Quem move o pai para `Done` e sempre o humano, depois de rodar a integracao.

## Passo 2 - Elegibilidade

Busque os tickets em `Ready for Agent` no time `linear_team`. Resolva a
empresa de cada um pela etiqueta `Repo/`, via registry.

**Leia SEMPRE os comentarios junto com a descricao:**

```bash
orca linear issue <IDENT> --comments --json
```

A descricao e o que a triagem escreveu; os comentarios sao onde o humano
corrigiu, respondeu duvida ou mudou de ideia depois. Um ticket cuja descricao
esta incompleta pode estar completo no comentario — avaliar so a descricao
reprova ticket que na verdade esta pronto.

Ordem de precedencia quando divergirem: **comentario humano mais recente vence a
descricao.** Se a divergencia mudar o escopo de forma relevante, diga isso em uma
linha no relatorio.

Ignore comentarios que sao ruido: link de PR, notificacao de integracao,
comentario do proprio agente numa passagem anterior.

Um ticket so e elegivel se TODAS as condicoes valerem:

- Tem exatamente uma etiqueta do grupo `Repo/`, e ela existe no registry.
- Todos os `blockedBy` estao `Done`. Blocker fora do projeto conta igual.

  Direcao importa: quem bloqueia ESTE ticket aparece em `inverseRelations` com
  `type: "blocks"`, nao em `relations` (esse e o lado de quem ele bloqueia).
  Olhar o lado errado deixa passar ticket com bloqueador aberto.

  ```graphql
  { issue(id: "<IDENT>") {
      inverseRelations { nodes { type issue { identifier state { name } } } } } }
  ```
- Nao e issue pai (issue pai nao tem etiqueta `Repo/`, entao ja cai fora).
- Passa no Definition of Ready abaixo.

### Fast Track: DoR reduzido

Ticket com a etiqueta **`Fast Track`** pula o Definition of Ready completo. E o
humano declarando "isso e trivial, nao precisa de plano": ele escreve o ticket e
manda direto para `Ready for Agent`, sem passar por `Draft`. Chega aqui com a
descricao crua, do jeito que foi escrita no celular.

Para esses, exija so:

- exatamente uma etiqueta do grupo `Repo/`, existente no registry
- `blockedBy` todos `Done`
- descricao que diga **o que fazer**, mesmo que em uma linha

Nao exija fora de escopo, arquivos afetados, criterios de aceite nem roteiro de
verificacao. Se faltarem, **dispare mesmo assim**.

Por que isso e seguro: o worker le o codigo de qualquer jeito — a triagem nunca
foi a unica a descobrir o arquivo. E com `gate: []` nada executa, entao o pior
caso e um PR errado que o humano fecha. O plano protege contra escopo indefinido,
e em tarefa trivial nao ha escopo a definir.

**A valvula de escape vai no prompt do worker** (Passo 5): se ao ler o codigo ele
concluir que a tarefa NAO e trivial, nao implementa — comenta o que descobriu e
devolve o ticket para `Draft` removendo `Fast Track`, para a triagem fazer o
trabalho completo. O risco real nao e a tarefa trivial, e a que *parece* trivial.

### Definition of Ready

A descricao precisa conter, de forma que um agente sem contexto implicito consiga
executar:

- o problema e por que precisa ser resolvido
- escopo e o que esta explicitamente fora do escopo
- comportamento esperado
- arquivos ou modulos afetados (pode ser aproximado)
- criterios de aceite verificaveis
- roteiro de verificacao manual, quando `risk` nao for `low`

Reprovou? **Nao dispare.** Comente no ticket exatamente o que falta, em uma lista
curta, e deixe o ticket parado onde esta. Nao mova, nao invente o que falta, nao
tente adivinhar o escopo.

## Passo 3 - Capacidade

Conte os dispatches vivos **por empresa**. A empresa que ja atingiu seu `wip_max`
sai desta rodada, mas as outras continuam — nunca pare tudo porque uma encheu,
isso deixaria as demais famintas. Respeite tambem `wip_max_global` somando todas
as empresas: quando ele estourar, ai sim pare.

Ordene os elegiveis por: prioridade do Linear, depois numero de tickets que cada
um desbloqueia (quem desbloqueia mais vai primeiro), depois data de criacao.
A ordenacao atravessa empresas — um P0 de uma passa na frente de um P3 de outra.

## Passo 4 - Claim

Para cada ticket que vai entrar, **nesta ordem**:

1. Mova para `Scheduled` no Linear.
2. So depois crie qualquer coisa no Orca.

Se inverter, uma falha no meio gera ticket duplicado no proximo tick.

## Passo 5 - Escrever o prompt do worker

Escreva um arquivo de prompt por ticket, em portugues, autocontido. O worker nao
deve precisar reconsultar o Linear para saber o que construir.

O prompt contem:

- a especificacao completa do ticket, inline
- **as decisoes e esclarecimentos que vieram dos comentarios, inline**, numa
  secao propria. O prompt tem que ser autocontido: se a decisao mora so no
  comentario e voce nao a transcreve, ela se perde — o worker nao volta ao
  Linear para descobrir o que construir. Quando um comentario contradisser a
  descricao, escreva a versao que vale e diga que veio de comentario posterior.
- o contrato de API do ticket pai, inline, quando existir
- a lista `manual` do repo, literal, com a instrucao explicita de NAO executar
  nenhum deles — ela vai para o corpo do PR como roteiro de verificacao
- a instrucao de que `gate` esta vazio de proposito: o worker nao roda nada
- o workflow de entrega (abaixo)
- quando o ticket consome codigo de um irmao ja mergeado: diga isso em uma linha
  ("origin/main ja contem X de ACME-411 — reutilize, nao reimplemente")
- **quando a descricao ou os comentarios tiverem imagem**: a linha de comando
  que baixa os anexos, e o aviso de que ele deve abrir cada um antes de planejar
  (veja abaixo)

### Ticket que e retomada: diga isso no prompt, em primeiro lugar

Quando o `resume-target.sh` do Passo 6 responder `RESUME` ou `RECREATE`, o
prompt muda de natureza — o worker vai encontrar codigo dele mesmo no worktree,
nao um repo limpo. Comece o bloco especifico com, literal:

```
RETOMADA. Este ticket ja tem PR aberto: <url>
Voce esta no worktree onde o trabalho anterior foi feito, na branch dele.
NAO abra PR novo. NAO crie branch. Leia o PR e o ultimo commit antes de planejar.
O que muda nesta leva esta na secao `## Leva N` da especificacao abaixo — o
resto da descricao ja foi entregue e esta no PR.
```

**Transcreva so a `## Leva N` como escopo de trabalho.** O resto da descricao
vai junto como contexto do que ja existe, marcado como tal. Se voce mandar a
descricao inteira como se fosse trabalho a fazer, o worker reimplementa o que ja
esta pronto e o diff do PR dobra de tamanho sem motivo.

### Ticket com imagem: mande o worker baixar, nao copie a URL

`uploads.linear.app` devolve 401 sem a chave da API. URL colada no prompt e
inutil — nem o `WebFetch` abre, e ele nao leria imagem de qualquer jeito.

Quem baixa e o **worker**, nao voce. O worktree so nasce no Passo 6, entao no
momento em que voce escreve o prompt ainda nao existe destino; e baixar aqui
gastaria o tempo do coordenador com arquivo que talvez nem seja olhado.

Quando o ticket tiver `![](https://uploads.linear.app/...)` em qualquer lugar,
inclua no prompt, literal:

```
Este ticket tem imagem. ANTES de planejar, rode e abra cada arquivo com o Read:
  ./bin/linear-assets.sh <IDENT>
Os arquivos vao para /Volumes/XPG_SSD/developer/.orch-assets/<IDENT>/, fora do
worktree — nao copie para dentro dele e nao ha nada para apagar antes do commit.
```

Nao inclua isso em ticket sem imagem: sao cinco linhas de prompt que so gastam
contexto e treinam o worker a rodar comando que devolve `nenhum anexo`.

### O workflow do worker mora em arquivo, nao no prompt

As regras que valem para TODO ticket — politica de execucao, ambiente
incompleto, autonomia de decisao e os 10 passos de entrega — estao em:

    <ORCH_ROOT>/.claude/worker-workflow.md

**Nao copie esse conteudo para o prompt.** Sao 150 linhas identicas em todo
despacho: o coordenador gastava output reescrevendo texto que nunca muda, e o
prompt inchado (438 linhas no ACME-26) e o que faz o Claude Code tratar a entrada
como bloco de paste e engolir o Enter.

Comece o prompt com estas duas linhas, **resolvendo `<ORCH_ROOT>` para o
caminho absoluto de verdade** — rode `pwd` e substitua:

```
LEIA ISTO PRIMEIRO, antes de qualquer outra coisa:
  cat /caminho/absoluto/do/orquestrador/.claude/worker-workflow.md
```

Nao deixe `<ORCH_ROOT>` literal no prompt e nao use `~` nem caminho relativo: o
worker roda no worktree do CLIENTE, onde relativo aponta para outro lugar. Essa
primeira linha e a unica coisa que liga o worker de volta ao orquestrador — se
ela estiver errada, ele comeca sem nenhuma das regras e nada acusa.

Depois vem o que e especifico deste ticket: a especificacao, os comandos do repo,
a base branch, o contrato do pai.

### Repita no prompt so o que nao pode falhar

Redundancia proposital, para o caso de o worker nao ler o arquivo:

```
Regras que valem mesmo que voce nao leia mais nada:
- NAO execute comando nenhum do projeto: lint, build, teste, migration,
  servidor de dev, nem instalar dependencia. O hook bloqueia.
- NAO faca merge. Nunca.
- NUNCA use `orca orchestration ask` — bloqueia por 10 min e ninguem responde.
- Antes de commitar: rm -f PLAN.md, e nunca `git add -A`.
- Reporte worker_done exatamente uma vez.
```

Se voce mudar uma regra do worker, mude no arquivo. Prompt ja despachado fica com
a versao velha; arquivo vale para todo worker que ainda vai ler.

## Passo 6 - Despachar

### Antes de qualquer coisa: e retomada ou e novo?

```bash
./bin/resume-target.sh <IDENT>
```

Ticket que volta para `Draft` depois de ja ter PR e uma **nova leva no mesmo
escopo**, nao um ticket novo. Despachar `new-top-level` nele cortaria branch
nova de `origin/<base>` e abriria PR novo — jogando fora a revisao que o humano
ja fez. O script decide isso por dados, nao por leitura sua:

| Saida | O que fazer |
|---|---|
| `RESUME <wt> <branch> <pr>` | despache **no worktree existente** (abaixo) |
| `RECREATE <repo> <branch> <pr>` | worktree sumiu; recrie da propria branch com `--base-branch origin/<branch>` |
| `FRESH primeira-vez` | fluxo normal |
| `FRESH pr-fechado <branch>` | PR ja mergeado; fluxo normal, mas com `--name` da branch sugerida |

### Retomada

```bash
orca orchestration worker-start \
  --task <taskId> \
  --worktree "path:<worktree que o script imprimiu>" \
  --agent claude \
  $(./bin/implementer-model.sh <IDENT> --flags) \
  --json
```

**Sem `--repo`, sem `--base-branch`, sem `--name`, sem `--setup`.** O Orca
rejeita esses flags em worktree existente — e e essa rejeicao que torna
impossivel cortar de `origin/main` por acidente. Se voce passar um deles, o
comando falha inteiro em vez de fazer a coisa errada em silencio.

**`--model` e `--effort` nao estao nessa lista, e por isso o `$(... --flags)`
vai aqui tambem.** A rejeicao vale so para os flags de criacao (`--name`,
`--repo`, `--base-branch`, `--display-name`, `--comment`, `--setup`) — foi o
que derrubou o `--display-name` e obrigou a virar comando separado. Os dois
agem no terminal do agente, que nasce novo a cada despacho inclusive na
retomada. Esquecer deles aqui faz a retomada herdar o `effortLevel` global em
vez do teto que o risco escolheu, sem aviso nenhum.

**O `$(...)` vai sem aspas, de proposito.** Ele rende dois pares de argumentos
(`--model opus --effort high`), e aspas entregariam isso como uma palavra so,
que o Orca recusaria. Sem aspas, saida vazia tambem nao quebra nada: o worker
so herda os padroes, que sao o extremo caro.

Setup nao roda de novo (o worktree ja passou por ele) e um terminal novo nasce
sozinho. No prompt, diga que e retomada e passe a URL do PR — o resto esta no
`worker-workflow.md`.

### Despacho novo

```bash
orca orchestration task-create \
  --task-title "<IDENT> <titulo>" \
  --spec "$(cat <arquivo-de-prompt>)" --json

orca orchestration worker-start \
  --task <taskId> \
  --worktree new-top-level \
  --repo id:<orca_repo_id do registry> \
  --name <slug-do-ticket> \
  --agent claude \
  $(./bin/implementer-model.sh <IDENT> --flags) \
  --setup run \
  --json
```

Nunca `new-child`: filho herda o repo deste worktree, que e o painel, nao o repo
do cliente.

Registre worktree id e terminal handle na sua tabela de estado.

### CONFIRME que o worker arrancou — `worker-start` mentir e comum

`worker-start` responder `input_accepted` e o dispatch ficar `dispatched`
significa que o Orca entregou o prompt no terminal. **Nao significa que o agente
comecou.**

O prompt destes tickets tem centenas de linhas. O Claude Code trata colagem
grande como bloco de paste, e o newline final as vezes e absorvido como parte do
texto em vez de virar submit. Resultado: sessao viva, prompt carregado no input,
`[Pasted text #1 +438 lines]` na tela, e **nada rodando**. Observado em 30/07 no
ACME-26; o ACME-25, da mesma leva e com prompt do mesmo tamanho, submeteu normal —
e intermitente, nao deterministico.

Isso e invisivel para o `/reconcile` e para o proprio Passo 1: existe dispatch,
existe worktree, existe terminal. Os quatro testes passam.

Depois de CADA `worker-start`:

```bash
# 1. espere a TUI ficar pronta (limite curto — nao trave a rodada)
orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 90000 --json

# 2. o agente esta mesmo trabalhando?
orca worktree ps --json \
  | jq -r --arg n "<name-que-voce-passou>" '.result.worktrees[]
      | select(.displayName==$n) | [.agents[]?.state] | join(",")'
```

Se **nenhum agente estiver em `working`**, o prompt ficou parado no input.
Mande um Enter vazio e confira de novo:

```bash
orca terminal send --terminal <handle> --text "" --enter --json
```

Confirme uma segunda vez. Se ainda assim nao houver agente em `working`:

- **nao redespache** — worktree e terminal ja existem, e um segundo
  `worker-start` cria worker duplicado no mesmo ticket
- registre no relatorio como `despachado (NAO confirmado)` com o handle do
  terminal, para o humano olhar
- deixe o ticket em `Scheduled`: o `/reconcile` vai reencontra-lo

O sinal que denuncia esse estado, e que vale checar quando houver duvida, e
`last_heartbeat_at = null` no `dispatch-show` combinado com nenhum agente em
`working`. Dispatch vivo sem heartbeat nenhum e sessao que nunca comecou.

### Dois desvios do CLI observados (Orca 1.4.162)

Confirme no `orca agent-context --json` se ainda valem — mas nao redescubra do
zero, custou 7 minutos de tentativa e erro na primeira execucao real.

**1. `worker-start` exige `--from` e `--run` explicitos.** Sem eles devolve
`selector_not_found` generico, mesmo com task, repo e agent validos. A ordem que
funciona:

```bash
orca orchestration run-create --objective "<descricao>" --json   # guarde o run_id
orca orchestration worker-start \
  --task <taskId> --run <runId> --from <seu terminal handle> \
  --worktree new-top-level --repo id:<orca_repo_id> \
  --name <slug> --agent claude $(./bin/implementer-model.sh <IDENT> --flags) --setup run --json
```

**2. `runtime_unavailable` NAO significa que falhou.** O comando pode devolver
erro enquanto a mutacao ja aplicou — worktree, terminal e dispatch passam a
existir. **Nunca retente as cegas: isso cria um segundo worker no mesmo ticket.**
Antes de qualquer retry:

```bash
orca orchestration dispatch-show --task <taskId> --json
orca worktree ps --json    # procure pelo --name que voce passou
```

Se qualquer um dos dois existir, o despacho deu certo. Siga em frente.

O mesmo padrao vale no Linear: `save-issue` devolve `linear_write_unconfirmed`
com alguma frequencia, e `linear_network_error` intermitente some no retry
imediato. Em ambos, releia o recurso antes de reescrever.

### Depois de despachar a onda, atualize os pais

```bash
./bin/sync-parent-status.sh --apply
```

Sem argumento ele varre o time inteiro, entao roda **uma vez no fim**, nao um
por ticket. Ticket pai fica em `Drafted` enquanto os filhos trabalham, o que da
a impressao errada de que ninguem pegou aquilo — este comando fecha essa lacuna.

Transcreva no relatorio so as linhas com `-> movido`. Se nao moveu nenhum, nao
escreva nada.

### Depois de despachar, espelhe o ticket no worktree

```bash
./bin/sync-worktree-meta.sh <IDENT> [<IDENT> ...]
```

Poe no worktree o nome legivel (`ACME-140 · Checkout recorrente: fluxo no app` em vez
do slug), o link do ticket — que estava **nulo em todos** ate 29/08 — e a coluna
do board conforme o estado no Linear.

Faca com este script e nao com `--display-name` no `worker-start`:
`--display-name` e flag de criacao, entao funciona no despacho novo e e
rejeitada na retomada. Um comando depois vale para os dois casos.

E renomeie a aba com o que voce despachou:

```bash
./bin/name-terminal.sh "despacho ACME-140 +2"
```

## Passo 7 - Relatorio

Uma tabela curta:

| Ticket | Repo | Acao | Motivo |
|---|---|---|---|

Acoes possiveis: despachado, reprovado no DoR, bloqueado, sem vaga, reconciliado.

### Portoes abertos esperando humano

Antes de encerrar, liste as perguntas pendentes na sua caixa:

```bash
orca orchestration check --terminal <seu handle> --peek --json
```

Para cada mensagem `type: question`, acrescente UMA linha ao relatorio:

```
GATE  <msg_id>  <ticket>  <resumo em <=10 palavras>
      responder: orca orchestration reply --id <msg_id> --body "<...>" --json
```

Isto existe porque ninguem fica lendo a caixa de entrada: a sessao que despachou
encerra o turno e o worker fica bloqueado ate alguem responder. Sem esta linha o
portao e invisivel, e o `reconcile` tambem nao acusa — o dispatch esta vivo, so
parado.

Fora isso, nao escreva mais nada. Esta skill roda dezenas de vezes por dia;
relatorio longo polui o historico da sessao reutilizada.

## Quando nao ha nada a fazer

Responda em uma linha: `nada elegivel`. Nao explique, nao sugira, nao pergunte.
