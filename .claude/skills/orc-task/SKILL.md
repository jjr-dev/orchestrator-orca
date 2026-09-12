---
name: orc-task
description: |
  Cria uma demanda nova direto do chat, sem abrir o board: grava o
  registro (ou pai + um filho por repo), aplica Repo/, Risk/ e Stack/, redige
  a especificacao lendo o codigo, e **mostra o plano no chat para voce aprovar
  antes de despachar**. Ajustes sao pedidos na mesma conversa. Funciona com o
  backend Linear ou com o Orca, sem mudar nada no seu pedido.
  Use sempre que aparecer "/orc-task", "cria uma task", "nova demanda", "manda
  fazer X no repo Y", ou quando o humano descrever no chat um trabalho novo que
  ainda nao existe como ticket.
  Use TAMBEM quando o humano aprovar ou ajustar um plano que esta skill mostrou:
  "pode executar", "aprovado", "manda ver", "pode mandar", "muda X e executa",
  "/orc-task --go". Nesses casos pule para o Passo 5.
---

# Criar demanda pelo chat

## Ancore-se na raiz antes de qualquer comando

```bash
cd "${ORCH_ROOT:-.}" && [ -f registry.example.yaml ] \
  || echo "nao estou na raiz do orquestrador: defina ORCH_ROOT ou entre nela"
```

## Uso

```
/orc-task "<pedido>" --repo "<Nome do Repo>" [--repo "<outro>"...]
/orc-task "<pedido>" --stack "<Nome da Stack>"
/orc-task "<pedido>" --repo "<Nome>" --fast
/orc-task "<pedido>" --repo "<Nome>" --risk low
/orc-task --go
```

| Flag | Efeito |
|---|---|
| `--repo` | repetivel; nome aproximado basta — ver resolucao abaixo |
| `--stack` | expande para os membros daquela stack, e marca `Stack/` no pai |
| `--fast` | pula a spec **e o portao**: vai o pedido cru, com `Fast Track`, direto para execucao |
| `--risk` | sobrescreve o `risk_default` do repo, para todos os filhos |
| `--go` | despacha o que ja esta esperando aprovacao, sem criar nada |

## O portao: voce aprova antes de qualquer worker subir

🔴 **O padrao e PARAR e mostrar.** Voce redige a spec, imprime no chat, e
**encerra o turno**. Nenhum worker sobe, nenhuma worktree e criada. So depois de
o humano dizer que pode e que o Passo 5 acontece.

Isso e o fluxo `Draft -> Ready for Agent` do Linear, feito na conversa: a mesma
leitura e a mesma aprovacao, sem abrir o board.

A unica excecao e `--fast`, que existe para o trabalho obvio e pequeno: trocar
um texto, ajustar um valor. Ali o pedido no chat ja e a aprovacao, porque nao ha
o que ler antes.

## 1. Resolva os nomes antes de gravar qualquer coisa

**O humano nao precisa digitar o nome exato.** `WitePay UI`, `witepay ui` e
`witepayui` resolvem todos para `WitePay - UI`:

```bash
./bin/resolve-name.sh --repo  "<o que o humano escreveu>"
./bin/resolve-name.sh --stack "<o que o humano escreveu>"
```

Saida 0 imprime a chave canonica no stdout — **use essa**, nunca o texto
original. A partir daqui, byte a byte: no backend `linear` e o que casa com a
etiqueta `Repo/`, e no `orca` e o que casa com o campo `repo` do front-matter.
Divergir num espaco deixa o item invisivel nos dois.

Saida 1 e uma de duas coisas, e o stderr diz qual:

- **ambiguo** — casou com mais de um. O script lista os candidatos e **nao
  adivinha**. Pergunte, com a sua recomendacao colada (regra 34), e so siga
  depois. Criar ticket no repo errado custa uma leva inteira de worker.
- **inexistente** — nao casou com nada. O script sugere os parecidos. Proponha
  o mais provavel e **pare**.

🔴 **Resolva TODOS os nomes antes de criar qualquer ticket.** Meio ticket criado
e pior que nenhum: sobra lixo no board que ninguem sabe de onde veio.

Com `--stack`, expanda para os membros. Some com os `--repo`, sem duplicar.

Todos os repos tem que ser da **mesma empresa** — `wip_max` e por empresa, e uma
demanda que atravessa duas nao tem como respeitar os dois limites. Se o pedido
atravessar, pare e diga que precisa virar duas demandas.

## 2. Redija a especificacao ANTES de gravar qualquer coisa

Esta ordem nao e preferencia: no backend `orca` a spec de uma task e **imutavel
depois da criacao**. Se o registro nascesse antes da redacao, nao haveria como
ajustar antes de aprovar — e ajustar antes de aprovar e o proposito do portao.
Redigir primeiro funciona igual nos dois backends, entao e o caminho unico.

**Sem `--fast`:** invoque a skill `/orc-triage` no **modo sem ticket**, passando
o pedido e o repositorio de cada filho. Ela le o codigo de verdade e devolve o
caminho de um arquivo com a spec no formato executavel — escopo, fora de escopo,
arquivos afetados, criterios de aceite e roteiro de verificacao manual.

**Nao reimplemente a redacao aqui.** As regras dela sao maduras e moram la; duas
copias divergem, e a que diverge e sempre a que ninguem lembra de atualizar.

**Com `--fast`:** pule a redacao. O pedido cru vira o corpo, com a etiqueta
`Fast Track`. Se no meio do caminho ficar claro que nao era trivial, o worker
tem instrucao propria para parar e escrever o plano (worker-workflow, passo 2b).

## 3. Grave o rascunho

```bash
./bin/board.sh draft --team <TEAM> --title "<titulo>" --body-file <spec> \
  --label "<Nome do Repo>" --label "<nivel de risco>" --label "Queue Jump" \
  [--parent <ident do pai>] [--slug <apelido curto>]
```

**Use `board.sh`, nunca `linear.sh` nem `orca-board.py`.** E o que faz esta skill
funcionar igual nos dois backends. Onde o rascunho para depende de qual esta
ligado, e voce nao precisa saber qual:

| backend | onde o rascunho fica | por que ali |
|---|---|---|
| `linear` | ticket em `Drafted` | nenhum cron vigia esse estado |
| `orca` | arquivo em `state/drafts/` | a spec da task e imutavel; o arquivo nao |

**Dois ou mais repos:** grave o pai primeiro, depois um filho por repo passando
`--parent`. O pai leva `Stack/` e nao leva `Repo/` nem `Risk/` — ele nao e
despachado, e quem define o estado dele sao os filhos.

**`Queue Jump` em todo filho.** Ela e o registro de que aquele ticket veio do
chat e por isso passou na frente. Sem ela o furo de fila existe e nao aparece em
lugar nenhum. Ela tambem e como voce reencontra o que espera aprovacao.

Tres regras que vem da triagem, e valem igual aqui:

- **`Repo/` e `Risk/` vao nos filhos**, nunca no pai.
- **Um `Repo/` por filho.** No Linear o grupo e exclusivo; no Orca o
  front-matter so tem um campo `repo`.
- **`Stack/` so no pai**, e so quando o conjunto de repos casa exatamente com
  uma stack do registry. Conjunto parcial nao leva etiqueta.

O nivel de risco sai do `--risk`, se voce passou; senao do `risk_default` do
repo no registry. **Nao invente** — sem `risk_default`, o resolvedor cai no
fallback, que e o ajuste mais caro de proposito.

## 4. Mostre e PARE

Imprima no chat a arvore e a spec inteira de cada filho:

```
ACME-201  Checkout recorrente                    (pai, Stack/Acme - API/Web)
  ACME-202  Repo/Acme - API   Risk/high     opus/xhigh
  ACME-203  Repo/Acme - Web   Risk/medium   opus/high

ACME-202 — <titulo>
  Escopo:            <...>
  Fora de escopo:    <...>
  Arquivos afetados: <...>
  Criterios:         <...>
  Perguntas:         <cada uma com a recomendacao ao lado>

Nada foi despachado. Diga "pode executar" para eu subir os workers,
ou peca os ajustes aqui mesmo.
```

Transcreva tambem o motivo do roteamento de modelo, que sai no stderr do
`implementer-model.sh` — e o que deixa voce ver um `Risk/` errado antes de
gastar um worker.

🔴 **Termine o turno aqui.** Nao crie worktree, nao chame `worker-start`, nao
"adiante" nada. O portao e o produto deste passo.

### Se o humano pedir ajuste

Regrave o rascunho com **o mesmo `--slug`** (ou o mesmo IDENT, no Linear) e
mostre de novo. Diga em uma linha o que mudou, para ele nao reler tudo. Depois
pare de novo. Quantas voltas forem necessarias: o portao so abre com um
"pode executar".

Ajuste que muda o conjunto de repos volta ao Passo 1. Nao remende com etiqueta.

## 5. Aprovado: promova e despache

Chegou aqui quando o humano aprovou, ou chamou `/orc-task --go`.

**Quais.** Na mesma conversa voce ja sabe. Em conversa nova, pergunte ao board:

```bash
./bin/board.sh list-drafts --team <TEAM>
```

A saida tem o mesmo formato nos dois backends: `identifier`, `title`, `repo`,
`risk`, `stack`, `parent`, `queue_jump`, `fast`.

Se vier mais de uma demanda, **liste e pergunte qual**. Nunca promova tudo que
aparecer: rascunho pode ter sobrado de uma conversa que o humano nunca aprovou.

```bash
./bin/board.sh promote --team <TEAM> <ident-filho-1> <ident-filho-2>
```

No backend `linear` isso move de `Drafted` para `Scheduled`. No `orca`, cria a
task ja na fila `ready`. Nos dois casos o item passa a ser seu, e so entao vem a
worktree — inverter a ordem abre janela para o `/orc-dispatch` pegar o mesmo
item de novo.

```bash
./bin/resume-target.sh <IDENT>     # sempre FRESH aqui, mas confirme
```

Depois, um worker por filho. O prompt e o mesmo do `/orc-dispatch` — leia la a
montagem completa, inclusive a primeira linha com o caminho absoluto do
`worker-workflow.md` resolvido por `pwd`.

```bash
orca orchestration worker-start \
  --task <taskId> --run <runId> --from <seu terminal handle> \
  --worktree new-top-level --repo id:<orca_repo_id do registry> \
  --name <slug> --agent claude \
  $(./bin/implementer-model.sh <IDENT> --flags) \
  --setup run --json
```

**Voce ignora o `wip_max` da empresa.** O pedido veio do humano, agora, e passa
na frente da fila — e para isso que a `Queue Jump` existe.

🔴 **Mas `wip_max_global` voce respeita.** Os dois limites protegem coisas
diferentes: o da empresa e justica, e voce tem licenca para furar; o global e a
**maquina**, porque cada worker e uma sessao completa do Claude Code. Furar o
global derruba tudo no meio, e voce perde o seu pedido junto com os alheios.

Se o global nao comportar a demanda inteira, promova o que couber e **deixe o
resto como rascunho**, dizendo quais ficaram. Eles nao se perdem: continuam
aparecendo no `list-drafts`, e a proxima passagem promove.

## 6. Feche

```bash
./bin/sync-worktree-meta.sh <IDENT>
./bin/sync-parent-status.sh --apply <IDENT-do-pai>
```

E diga, em ate cinco linhas, o que subiu e com qual modelo.

## O que voce NAO faz aqui

- **Nao despacha sem aprovacao.** Salvo `--fast`. E a regra desta skill.
- **Nao mergeia.** Nunca.
- **Nao cria repo nem empresa.** Se falta, o caminho e `/orc-repo-add`.
- **Nao adivinha o repo pelo texto do pedido.** Nome de ticket engana; se o
  humano nao passou `--repo` nem `--stack`, pergunte com as opcoes e a sua
  recomendacao.
- **Nao roda comando de projeto.** Nem para "conferir se compila".
- **Nao despacha ticket que ja existe.** Se o pedido e sobre trabalho que ja
  virou codigo, o caminho e `/orc-adjust`.

## Quando algo falhar no meio

Se a promocao funcionou e o despacho falhou, **nao apague nada**. Diga no
relatorio o que ficou promovido sem worker: no backend `linear` o
`/orc-dispatch` pega no proximo ciclo, e no `orca` o item fica na fila `ready`,
que o `has-ready.sh` enxerga. O trabalho de redacao nao se perde.

Se o rascunho do pai funcionou e o de um filho falhou, grave o filho que falta
antes de promover qualquer um. Pai com filho faltando produz um
`sync-parent-status` que nunca fecha.

Se a sessao morrer entre o Passo 4 e o Passo 5, nada se perde. Os rascunhos
continuam onde estao — ticket em `Drafted` ou arquivo em `state/drafts/` — e a
proxima conversa os reencontra com `board.sh list-drafts`. Nenhum cron toca
neles nesse meio tempo, nos dois backends.
