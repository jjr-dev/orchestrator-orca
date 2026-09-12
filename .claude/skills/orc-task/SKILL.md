---
name: orc-task
description: |
  Cria uma demanda nova direto do chat, sem passar pelo Linear a mao: cria o
  ticket (ou pai + um filho por repo), aplica as etiquetas Repo/, Risk/ e
  Stack/, redige a especificacao lendo o codigo, e **mostra o plano no chat
  para voce aprovar antes de despachar**. Ajustes sao pedidos na mesma conversa.
  O Linear fica com o historico inteiro.
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

## 1. Resolva os nomes antes de tocar no Linear

**O humano nao precisa digitar o nome exato.** `WitePay UI`, `witepay ui` e
`witepayui` resolvem todos para `WitePay - UI`:

```bash
./bin/resolve-name.sh --repo  "<o que o humano escreveu>"
./bin/resolve-name.sh --stack "<o que o humano escreveu>"
```

Saida 0 imprime a chave canonica no stdout — **use essa**, nunca o texto
original. A partir daqui, byte a byte: e o que casa com a etiqueta `Repo/` no
Linear, e divergir num espaco deixa o ticket invisivel.

Saida 1 e uma de duas coisas, e o stderr diz qual:

- **ambiguo** — casou com mais de um. O script lista os candidatos e **nao
  adivinha**. Pergunte, com a sua recomendacao colada (regra 34), e so siga
  depois. Criar ticket no repo errado custa uma leva inteira de worker.
- **inexistente** — nao casou com nada. O script sugere os parecidos. Proponha
  o mais provavel e **pare**.

🔴 **Resolva TODOS os nomes antes de criar qualquer ticket.** Meio ticket criado
e pior que nenhum: sobra lixo no Linear que ninguem sabe de onde veio.

Com `--stack`, expanda para os membros. Some com os `--repo`, sem duplicar.

Todos os repos tem que ser da **mesma empresa** — `wip_max` e por empresa, e uma
demanda que atravessa duas nao tem como respeitar os dois limites. Se o pedido
atravessar, pare e diga que precisa virar duas demandas.

## 2. Crie no Linear

Use o `bin/board.sh`, **nao o `orca linear`**, para toda escrita. Ele cacheia os
UUID de estado e etiqueta e manda tudo numa requisicao: criar um ticket com
estado e tres etiquetas custa ~390 ms por aqui contra ~5,6 s por la, e N filhos
saem numa chamada so.

**Um repo:** um ticket so, com `Repo/` e `Risk/`.

```bash
./bin/board.sh create --team <TEAM> --title "<titulo>" --body-file <arquivo> \
  --label "<Nome do Repo>" --label "<nivel de risco>" --label "Queue Jump" \
  --state "Drafting"
```

**Dois ou mais:** ticket pai + um filho por repo, os filhos num lote so.

```bash
# pai — sem Repo/, sem Risk/, porque ele nao e despachado
./bin/board.sh create --team <TEAM> --title "<titulo>" --body-file <arquivo> \
  --label "<Nome da Stack>" --state "Drafting"

# filhos — uma requisicao para todos
cat > /tmp/filhos.json <<'JSON'
[ {"title": "<titulo A>", "body_file": "<arquivo A>",
   "labels": ["<Repo A>", "<risco>", "Queue Jump"], "state": "Drafting"},
  {"title": "<titulo B>", "body_file": "<arquivo B>",
   "labels": ["<Repo B>", "<risco>", "Queue Jump"], "state": "Drafting"} ]
JSON
./bin/board.sh create --team <TEAM> --parent <IDENT-do-pai> --batch /tmp/filhos.json
```

**`Queue Jump` em todo filho que voce criar.** Ela e o registro, no proprio
board, de que aquele ticket veio do chat e por isso passou na frente. Sem ela o
furo de fila existe e nao aparece em lugar nenhum — e a classe de coisa que este
sistema mais sofre. Ela tambem e como voce reencontra o que esta esperando
aprovacao, no Passo 5.

🔴 **`Drafting`, nunca `Draft`.** O precheck `has-triage.sh` vigia exatamente
`Draft`, a cada 2 minutos. Ticket criado la e visivel para o cron antes de voce
reivindicar — e o cron despacharia uma segunda triagem no mesmo ticket. O claim
resolveria o empate, mas um dos dois dispatches teria sido desperdicado.

Nascer em `Drafting` e nascer reivindicado: nenhum dos dois prechecks olha esse
estado, entao o ticket e seu do inicio ao fim.

Tres regras que vem da triagem, e valem igual aqui:

- **`Repo/` e `Risk/` vao nos filhos**, nunca no pai. O pai e derivado: quem
  define o estado dele sao os filhos, pelo `bin/sync-parent-status.sh`.
- **Um `Repo/` por filho.** O grupo e exclusivo no Linear.
- **`Stack/` so no pai**, e so quando o conjunto de repos casa exatamente com
  uma stack do registry. Conjunto parcial nao leva etiqueta.

O nivel de risco sai do `--risk`, se voce passou; senao do `risk_default` do
repo no registry. **Nao invente** — se o repo nao tem `risk_default`, o
resolvedor cai no fallback, que e o ajuste mais caro de proposito.

O pai descreve o contrato entre os repos quando houver — o que a API expoe e o
que o front consome. E o que impede os dois filhos de inventarem nomes
diferentes para o mesmo campo.

## 3. Redija a especificacao

**Sem `--fast`:** invoque a skill `/orc-triage` passando os `<IDENT>` dos filhos
que voce acabou de criar. Ela le o codigo de verdade e reescreve a descricao no
formato executavel — escopo, fora de escopo, arquivos afetados, criterios de
aceite e roteiro de verificacao manual.

**Nao reimplemente a redacao aqui.** As regras dela sao maduras e moram la; duas
copias divergem, e a que diverge e sempre a que ninguem lembra de atualizar.

**Com `--fast`:** pule esta etapa, aplique a etiqueta `Fast Track` nos filhos, e
deixe o pedido cru na descricao. Se no meio do caminho ficar claro que nao era
trivial, o worker tem instrucao propria para parar e escrever o plano
(worker-workflow, passo 2b).

## 4. Mostre e PARE

Mova tudo para `Drafted` e **encerre o turno**.

```bash
./bin/board.sh move --to "Drafted" <IDENT-do-pai> <IDENT-filho-1> <IDENT-filho-2>
```

**Por que `Drafted` e o lugar certo para esperar:** nenhum precheck olha esse
estado — o `has-triage.sh` vigia `Draft` e o `has-ready.sh` vigia
`Ready for Agent`. O `/orc-reconcile` tambem nao mexe nele; ele destrava
`Drafting`, que e outro estado. Entao o ticket fica parado ali o tempo que voce
precisar, sem nenhum cron pegando pelas costas.

Imprima no chat, com a spec inteira de cada filho:

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

ACME-203 — <...>

Nada foi despachado. Diga "pode executar" para eu subir os workers,
ou peca os ajustes aqui mesmo.
```

Transcreva tambem o motivo do roteamento de modelo, que sai no stderr do
`implementer-model.sh` — e o que deixa voce ver um `Risk/` errado antes de gastar
um worker.

🔴 **Termine o turno aqui.** Nao crie worktree, nao chame `worker-start`, nao
"adiante" nada. O portao e o produto deste passo.

### Se o humano pedir ajuste

Reescreva a spec e **mostre de novo**, sem sair de `Drafted`:

```bash
./bin/board.sh update --body-file <spec revisada> <IDENT>
```

Diga em uma linha o que mudou desde a versao anterior, para ele nao reler tudo.
Depois pare de novo. Quantas voltas forem necessarias — o portao so abre com um
"pode executar".

Ajuste que muda o conjunto de repos volta ao Passo 1: resolver nome, criar ou
apagar filho. Nao remende com etiqueta.

## 5. Aprovado: claim e despacho

Chegou aqui quando o humano aprovou, ou quando ele chamou `/orc-task --go`.

**Quais tickets.** Na mesma conversa voce ja sabe os IDENT. Em conversa nova,
ache os que estao esperando:

```bash
./bin/linear-query.sh '{ issues(filter:{
  team:{ key:{ eq:"<TEAM>" } },
  state:{ name:{ eq:"Drafted" } },
  labels:{ name:{ eq:"Queue Jump" } }
}, first:50){ nodes{ identifier title parent{ identifier } } } }'
```

Se vier mais de uma demanda, **liste e pergunte qual** antes de despachar. Nunca
despache tudo que aparecer: `Queue Jump` em `Drafted` pode ter sobrado de uma
conversa anterior que o humano nunca aprovou.

Mova para `Scheduled` **antes** de criar worktree. A ordem nao e estetica: o
estado e o unico registro de que alguem pegou o ticket, e inverter abre janela
para o `/orc-dispatch` despachar o mesmo ticket de novo.

```bash
./bin/board.sh move --to "Scheduled" <IDENT-filho-1> <IDENT-filho-2>
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

Se o global nao comportar a demanda inteira, despache o que couber e **deixe o
resto em `Ready for Agent`**, dizendo quais ficaram. Esse e o unico momento em
que voce usa esse estado, e o uso e deliberado: e o que o `has-ready.sh` vigia,
entao o cron pega no proximo ciclo sozinho. Ticket que sobra nao fica orfao.

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

Se a criacao no Linear funcionou e o despacho falhou, **nao apague o ticket**.
Deixe em `Ready for Agent` e diga isso no relatorio: o `/orc-dispatch` pega no
proximo ciclo, e o trabalho de redacao nao se perde.

Se a criacao do pai funcionou e a de um filho falhou, crie o filho que falta
antes de despachar qualquer um. Pai com filho faltando produz um
`sync-parent-status` que nunca fecha.

Se a sessao morrer entre o Passo 4 e o Passo 5, nada se perde: os tickets ficam
em `Drafted` esperando, e a proxima conversa os reencontra pela consulta do
Passo 5. Nenhum cron os toca nesse meio tempo.
