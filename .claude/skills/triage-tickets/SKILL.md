---
name: triage-tickets
description: |
  Pega tickets crus do Linear em "Draft", le o repositorio de verdade e
  reescreve a descricao no formato executavel por agente: escopo, fora de escopo,
  arquivos afetados, criterios de aceite e roteiro de verificacao manual. Quando o
  escopo atravessa frontend e backend, propoe a quebra em issue pai com contrato de
  API mais uma sub-issue por repositorio.
  Use sempre que aparecer "/triage-tickets", "redige os tickets", "tria os tickets",
  "transforma essa ideia em ticket", "esse ticket ta magro", ou quando uma automation
  do Orca disparar triagem para uma empresa.
---

# Triagem: de ideia solta para ticket executavel

## Ancore-se na raiz antes de qualquer comando

As chamadas abaixo sao relativas, e o diretorio de trabalho persiste entre elas.
Rode isto primeiro — uma vez, e vale para a skill inteira:

```bash
cd "${ORCH_ROOT:-.}" && [ -f registry.example.yaml ] \
  || echo "nao estou na raiz do orquestrador: defina ORCH_ROOT ou entre nela"
```

Se reclamar, **pare e resolva**. Sessao aberta fora da raiz carrega estas skills
mas nao acha o `bin/` — e a falha aparece no meio do trabalho, nao no comeco.


Argumento: `$ARGUMENTS` = chave da empresa no `registry.yaml`, para restringir a
uma so empresa. **Sem argumento, roda para todas** — e assim que a automation
chama. Nunca pergunte qual empresa: em execucao por cron nao ha ninguem para
responder.

Workspace unico: um so time no Linear. A empresa vem da etiqueta `Repo/` via
registry, nunca do time.

O usuario escreve tickets no celular, em duas ou tres linhas. Seu trabalho e
transformar isso em algo que um agente executa sem contexto implicito — e devolver
para ele aprovar do celular.

## Os tres estados da triagem

| Estado | Significa | Quem move para la |
|---|---|---|
| `Draft` | fila: alguem escreveu, ninguem redigiu | humano, ou o worker devolvendo |
| `Drafting` | voce esta trabalhando neste ticket agora | **voce**, no claim |
| `Drafted` | terminou, esperando leitura do humano | **voce**, ao fechar |

O estado **e** o claim. Nao existe etiqueta de controle: se o ticket esta em
`Drafting`, alguem o pegou, e ponto. Um fato so, que nao pode discordar de si
mesmo.

Voce **nunca** move ticket para `Ready for Agent`. Esse e o botao de start do
humano, e e a unica coisa que separa "redigido" de "vai virar codigo".

## Passo 0 - O que NAO carregar

**Nao rode `orca skills get orchestration --full`.** Sao 388 linhas que voce nao
vai usar: esta skill nao despacha worker e nao chama nenhum comando
`orca orchestration`. O guia ficaria no contexto sendo relido a cada turno.

Voce precisa de: `orca status --json`, o `registry.yaml`, e os comandos
`orca linear ...` que estao escritos aqui. **Nao rode `--help` para descobrir
sintaxe** — os comandos deste arquivo estao conferidos. Se algum falhar por flag
invalida, ai sim consulte o `--help` daquele comando especifico.

## Passo 1 - Selecionar

Tickets no estado `Draft`, no time `linear_team` do registry.

```bash
orca linear list-issues --team <TEAM_KEY> --state "Draft" --limit 50 --json
```

Nao filtre por etiqueta nenhuma. Ticket sem `Repo/` entra na triagem — descobrir
o repo e justamente o Passo 2. Ticket com `Fast Track` tambem entra: o normal e
ele nunca passar por aqui (o humano manda direto para `Ready for Agent`), mas se
esta em `Draft` e porque alguem quer que seja redigido. A coluna e a intencao.

### UM ticket por passagem

Mesmo que varios estejam elegiveis, **trie apenas um e encerre.** A automation
roda a cada 2 minutos: a fila esvazia sozinha, e cada passagem fica curta.

O motivo e custo. Contexto nao diminui dentro de uma sessao — tudo que voce leu
para o ticket 1 continua sendo relido enquanto voce trabalha no ticket 2. Tres
tickets na mesma sessao nao custam 3x: custam bem mais, porque o contexto do
terceiro carrega os dois primeiros. Medido em 03/08: uma passagem de 10,2 min
gastou 3,1 milhoes de tokens de cache-read.

Ordem de escolha:

1. **refacoes primeiro** — ticket em `Draft` que ja tem comentario seu de uma
   passagem anterior significa que o humano respondeu e devolveu. Ele esta
   esperando; tem prioridade sobre ticket novo.
2. depois, o mais antigo por `createdAt`.

No relatorio final, diga quantos ficaram na fila.

### CLAIM: mova para `Drafting` ANTES de comecar a trabalhar

Assim que escolher o ticket, e **antes de ler qualquer codigo**:

```bash
orca linear status set --id <IDENT> --to "Drafting" --json
```

Isso e claim, nao conclusao. Sem ele o ticket continua em `Draft` enquanto voce
trabalha, e a automation dispara **outra triagem no mesmo ticket** a cada 2
minutos — voce acaba com tres agentes lendo os mesmos repos e escrevendo por
cima uns dos outros. Aconteceu em 30/07.

Mesma regra do `pull-ready`, que move para `Scheduled` antes de criar worktree.
Claim primeiro, trabalho depois. Sempre.

Ja com o ticket escolhido, nomeie a sua aba — antes do claim nao havia o que
escrever nela:

```bash
./bin/name-terminal.sh "triagem <IDENT>"
```

Se a sua sessao morrer entre o claim e o fechamento, o ticket fica em `Drafting`
parado. O `/reconcile` detecta pelo tempo sem atualizacao e devolve para `Draft`
sozinho — voce nao precisa se preocupar com isso, so nao pule o claim.

### SEMPRE leia os comentarios antes de escrever

```bash
orca linear issue <IDENT> --comments --json
```

Um ticket em `Draft` pode ser **novo** ou pode ser um que voce ja redigiu e que
voltou para ca. Ele volta quando o humano arrasta de `Drafted` de volta para
`Draft` — e esse e o unico sinal de "refaz, eu respondi suas perguntas".

Distinguir e trivial: se a descricao ja tem as secoes que voce escreve
(`## Problema`, `## Escopo`, `## Criterios de aceite`), e refacao. Nesse caso
**revise, nao reescreva do zero** — preserve o que ninguem questionou e mexa so
no que os comentarios pedem.

### Ticket com PR e um TERCEIRO caso: nova leva

```bash
./bin/resume-target.sh <IDENT>
```

Se responder `RESUME` ou `RECREATE`, este ticket **ja virou codigo** e o PR esta
aberto. Ele nao voltou para ser redigido de novo: voltou para ganhar uma leva
nova dentro do mesmo escopo, no mesmo PR.

Aqui a regra muda de forma importante:

- **Nao toque no que ja foi entregue.** As secoes existentes descrevem codigo
  que existe e ja foi revisado. Reescrever faz o worker reimplementar tudo.
- **Acrescente uma secao `## Leva N`** no fim, com N sendo a proxima (a
  primeira leva nova e `## Leva 2`). So o delta: o que muda agora, quais
  arquivos, e criterios de aceite novos.
- **Nao repita criterio de aceite ja atendido** na secao nova. O worker le a
  `## Leva N` como escopo de trabalho; tudo que estiver ali ele vai fazer.

```markdown
## Leva 2

<o que o humano pediu, em uma ou duas frases>

### Muda
- caminho/do/arquivo.tsx — <o que muda>

### Criterios de aceite desta leva
- [ ] verificavel, e so sobre o que muda agora
```

Se responder `FRESH pr-fechado`, o PR anterior ja foi mergeado: o codigo daquela
leva esta na base. Escreva a `## Leva N` do mesmo jeito — o `pull-ready` e quem
cuida de cortar branch nova, isso nao e problema seu.

Se voce encontrar respostas as perguntas de uma passagem anterior:

- **incorpore todas na descricao** e diga, no comentario de fechamento, o que
  cada resposta mudou. Uma linha por resposta.
- **nao repita pergunta ja respondida.** Se a resposta foi ambigua, reformule
  uma vez, mais especifica, oferecendo as opcoes.
- **respeite a resposta mesmo que voce discorde.** Se ela criar um problema
  tecnico, implemente como pedido e registre a consequencia numa linha — nao
  reabra a discussao nem decida por conta propria.

Se nao houver comentario nenhum, e ticket novo: siga normalmente.

### SEMPRE baixe as imagens antes de escrever

Screenshot de bug, print de erro e mockup de tela mudam o escopo que voce vai
escrever. Ler a descricao sem olhar a imagem produz spec que descreve outra coisa.

```bash
./bin/linear-assets.sh <IDENT>
```

Ele varre descricao, comentarios e anexos, baixa tudo e imprime uma linha por
arquivo com o caminho local. **Abra cada imagem com o Read** antes de continuar.

Sem anexo ele diz `nenhum anexo em <IDENT>` e sai limpo — nao e erro, siga.

`uploads.linear.app` nao e URL publica: devolve 401 sem a chave. Nao adianta
tentar `WebFetch` na URL, nem colar a URL na descricao esperando que alguem
adiante consiga abrir. So o arquivo local funciona.

**Os arquivos vao para o SSD externo**, em ``$(bin/assets-root.sh)`/<IDENT>/`,
fora de qualquer repositorio git. E de proposito: nao ocupam o disco interno e
nao ha como serem commitados por acidente. Se o SSD estiver desmontado o script
para com exit 2 em vez de escrever no disco interno — se isso acontecer, reporte
e siga sem a imagem, dizendo no comentario que nao conseguiu ver o anexo.

## Passo 2 - Descobrir o repositorio

**Ordem de precedencia, da mais forte para a mais fraca:**

**1. Etiqueta `Stack/<nome>` — o mecanismo principal.** Se existir, resolva pelo
mapa `stacks:` do registry e use exatamente aqueles repos. Hoje:

```
Stack/Acme - API/Web        -> Acme - API      + Acme - Web
Stack/Beta - API/App  -> Beta - API + Beta - App
```

Dois ou mais repos no mapa significa quebrar (Passo 5), sem avaliar heuristica
nenhuma. Se a etiqueta existir no Linear mas nao no mapa `stacks:`, comente o
erro e pare — nao adivinhe quais repos ela cobre.

**2. Linha `Repos:` no corpo do ticket** — escotilha de emergencia, para
combinacao que ainda nao tem Stack. Se existir, e ORDEM, nao sugestao:

```
Repos: Beta - App, Beta - API
```

Use exatamente esses, na ordem escrita — o primeiro e o repo principal. Nao
deduza nada, nao acrescente, nao remova. Se um nome nao existir no registry,
nao invente o mais parecido: comente o erro listando os nomes validos daquela
empresa e pare.

Dois ou mais nomes nesta linha significam quebrar, igual ao `Stack/`.

Se `Stack/` e `Repos:` existirem e discordarem, a linha `Repos:` vence — ela e
especifica daquele ticket, a etiqueta e generica. Registre a divergencia numa
linha do comentario.

**Quando usar a linha `Repos:`, sugira a Stack.** Feche o comentario com:

> Essa combinacao ainda nao tem Stack. Se repetir, vale criar
> `Stack/<nome>` no Linear e mapear em `stacks:` no registry — ai basta a
> etiqueta, sem escrever no corpo.

O objetivo e que o texto seja excecao e a etiqueta seja a regra.

**3. Etiqueta `Repo/` ja aplicada.** Use ela. Um repo so, sem quebra.

**4. Deducao.** Sem nenhum dos anteriores, deduza pelo texto e pelo registry.

Se nao tem, deduza pelo texto e pelo registry, e **proponha** a etiqueta no
comentario. Nao aplique sozinho quando houver mais de um candidato plausivel:
pergunte no comentario, em uma linha, com as opcoes.

## Passo 3 - Ler o codigo antes de escrever

Um ticket escrito sem olhar o codigo produz lista de arquivos inventada, e isso
desperdica uma rodada inteira de agente. Mas ler o repo inteiro tambem custa: todo
arquivo aberto fica no contexto e e relido a cada turno seguinte.

**Comece dirigido, expanda quando precisar.**

Ordem sugerida:

1. `CLAUDE.md` do repo, se existir — e o mapa mais barato que existe
2. `grep -rn` pelos termos concretos do ticket (nome do endpoint, do componente,
   da mensagem, da coluna)
3. abra os arquivos que o grep apontou, nao a arvore inteira
4. pare quando conseguir listar "Arquivos afetados" com confianca

### Onde NAO economizar

Ler de menos tem um custo pior que o de tokens: **especificar do zero uma coisa
que ja existe.** Um ticket que manda "criar funcao de sanitizar" num repo que ja
tem `sanitizeInput()` produz codigo duplicado que passa no review e apodrece.

Entao, **antes de escrever qualquer criterio de aceite que crie algo novo** —
funcao, helper, componente, hook, endpoint, tipo, constante — procure se ja
existe:

```bash
grep -rni "sanitiz\|normaliz\|format" src/ --include="*.ts" | head -30
ls src/utils src/helpers src/lib src/common 2>/dev/null
```

Se achar algo parecido, **leia** e decida: reusar, estender ou realmente criar
novo. Escreva a decisao em "Detalhes tecnicos", com o caminho do arquivo.

**Expandir a leitura nunca esta errado quando a alternativa e duplicar codigo.**
O limite do Passo 3 e contra vagar sem rumo pela arvore, nao contra investigar
uma duvida concreta. Na duvida entre ler mais um arquivo ou chutar: leia.

O mesmo vale para padrao do repo. Antes de propor uma abordagem, confira como o
repo ja resolve um caso parecido — e siga o padrao dele, mesmo que voce faria
diferente. Ticket que contraria o padrao local vira discussao no review.

## Passo 4 - Reescrever a descricao

Substitua a descricao do ticket por esta estrutura, em portugues.

**Tamanho proporcional ao ticket.** Mudanca de uma linha nao precisa de tres
paragrafos de contexto. Escreva o que o worker precisa para executar sem voltar a
perguntar — nem uma frase a mais. Secao inflada custa tokens na escrita e na
leitura, e enterra o que importa.

### Sempre presentes

Estas seis o `pull-ready` exige no Definition of Ready. Sem qualquer uma delas o
ticket reprova e nao e despachado:

```markdown
## Problema
<o que esta ruim hoje e por que precisa ser resolvido>

## Escopo
<o que este ticket entrega>

## Fora de escopo
<o que NAO entra. Uma lista curta do que o worker poderia querer fazer junto
 e nao deve. Aqui o objetivo e travar escopo, nao ser exaustivo.>

## Comportamento esperado
<do ponto de vista de quem usa>

## Arquivos afetados
- caminho/real/do/arquivo.ts     <- caminhos que voce CONFIRMOU no Passo 3

## Criterios de aceite
- [ ] verificavel, nao subjetivo
```

### Condicionais — inclua so quando houver conteudo real

```markdown
## Detalhes tecnicos
<so quando houver decisao, padrao do repo a seguir ou armadilha conhecida.
 E aqui que entra "reusar X em vez de criar novo", com o caminho do arquivo.>

## Verificacao manual
<obrigatoria quando risk != low; opcional em low>
1. <comando exato>
2. <passo a passo>
3. <o que observar para dizer que funcionou>

## Rollout
<so quando houver risco de verdade: flag e kill switch.
 Feature arriscada nasce com flag OFF.>

## Anexos
<so quando o ticket tiver imagem. Repita o `![descricao](url)` de cada uma,
 com um alt que diga o que ela mostra.>
```

**Secao sem conteudo nao entra.** Escrever `## Rollout` seguido de "n/a" e pior
que omitir: ocupa espaco e treina quem le a pular secao.

### A imagem nao pode morrer na reescrita

Voce substitui a descricao inteira. Se o humano colou um screenshot e voce nao
repete o `![](https://uploads.linear.app/...)`, a imagem some do ticket — e some
antes do `pull-ready`, que nunca vai saber que existiu.

Entao, sempre:

- **transcreva a URL de toda imagem** para a secao `## Anexos`, ou inline na
  secao onde ela importa (um print de erro pertence ao `## Problema`)
- **descreva em texto o que a imagem mostra**, alem de linkar. O worker le a
  imagem, mas a descricao em texto e o que sobrevive a qualquer falha de
  download e o que torna os criterios de aceite verificaveis
- **nunca substitua a imagem so pela sua descricao.** Um mockup tem detalhe de
  espacamento e cor que nenhum paragrafo captura

Mantenha o ticket abaixo de ~5 pontos. Se nao couber, va para o passo 5.

## Passo 4b - Pai em `Draft`: rotear, nao executar

Pai nao tem repo, nao tem worker e nao tem PR. Quando ELE volta para `Draft`, o
pedido quase sempre e codigo — e codigo mora nos filhos.

Primeiro decida de quem e o pedido:

- **e do pai** quando muda contrato de API compartilhado ou o roteiro de
  verificacao ponta a ponta. Ajuste o pai e pare. Nenhum filho e tocado.
- **e de filho** quando muda comportamento, tela ou endpoint. Vai para os
  filhos afetados.

Sendo de filho, para CADA filho afetado:

1. escreva a secao `## Leva N` na descricao **dele**, com o delta que cabe ao
   repo dele
2. mova **ele** para `Draft`:
   `orca linear status set --id <FILHO> --to "Draft" --json`
3. no fim, devolva o **pai** para `Drafted` e comente ali quais filhos voce
   reabriu e por que — uma linha por filho

**Nao reabra filho que o pedido nao toca.** Reabrir custa uma leva inteira de
worker e polui um PR que ja estava pronto para merge. Se estiver em duvida entre
dois filhos, escolha pelo codigo que voce leu no Passo 3, e diga no comentario
do pai qual escolheu e por que.

Se o pedido atravessar dois filhos de verdade, reabra os dois — cada um com a
sua `## Leva N`, e o contrato compartilhado atualizado no pai antes.

O pai indo para `Drafted` e o filho para `Draft` e o que faz o
`sync-parent-status.sh` reconhecer filho reaberto e puxar o pai junto. Nao mova
o pai para `Draft`: ele cairia na fila da triagem a cada 2 minutos sem ter nada
a redigir.

## Passo 5 - Quebrar quando o escopo atravessa repos

Sinais, em ordem de forca:

1. **Linha `Repos:` com dois ou mais nomes** (Passo 2). Decisivo — quebre, sem
   avaliar heuristica nenhuma.
2. A ideia toca API e tela ao mesmo tempo.
3. O `pair` do repo deduzido aponta candidatos. `pair` aceita um nome ou uma
   lista; quando for lista, sao **candidatos**, nao certezas — escolha pelo texto
   e pelo codigo que voce leu, e diga qual escolheu e por que.

`pair` vazio nao significa "nao quebra": significa que nao ha candidato obvio
declarado. Se o texto deixar claro que atravessa dois ou mais repos, quebre
mesmo assim.

**Nao existe limite de dois.** Uma Stack pode mapear tres ou mais repos, e a
linha `Repos:` aceita quantos nomes voce escrever. Um filho por repo, sempre.

**Sempre declare a decisao** no comentario de fechamento, em uma linha: quais
repos entraram, e se veio da linha `Repos:`, do `pair` ou do texto. Sem isso o
humano nao tem como saber que voce escolheu errado.

Nesse caso, **execute a quebra** — nao proponha e espere. No fluxo por automation
nao existe canal de aprovacao: proposta em comentario fica sem leitor, e o ticket
morre ali. Quebrar e reversivel (apagar sub-issue e trivial); nao quebrar
produz um ticket que nenhum worker consegue executar.

Estrutura:

Um filho por repo, quantos forem:

```
PAI  <titulo>                     <- sem etiqueta Repo/, carrega os contratos
  |- FILHO  Repo/<repo 1>
  |- FILHO  Repo/<repo 2>
  |- FILHO  Repo/<repo 3>         <- e assim por diante
```

Com tres ou mais, o pai carrega **todos** os contratos compartilhados, e cada
filho inlina so as partes que ele consome ou expoe. Nao faca um filho ler o
contrato do outro: se A expoe e B e C consomem, o contrato mora no pai e os tres
o inlinam.

**Confira a capacidade antes.** Os filhos entram todos na mesma onda, entao N
filhos da mesma empresa ocupam N vagas do `wip_max` dela. Se N for maior que o
`wip_max`, os excedentes ficam na fila e entram nas rodadas seguintes — nao
quebra nada, so deixa de ser paralelo. Se isso acontecer, diga no comentario
quantos entram agora e quantos esperam.

O pai carrega o que e comum, e principalmente **o contrato de API como artefato
concreto** — bloco OpenAPI ou interface TypeScript, nao prosa. Cada filho inlina
esse contrato nos proprios criterios de aceite.

Regra que faz todos entrarem na mesma onda: **nao coloque `blockedBy` entre os
filhos.** Quem consome implementa contra mock, seguindo o contrato do pai — vale
para dois filhos ou para cinco. A integracao real e verificada depois, no pai.

O pai fica com o roteiro de verificacao ponta a ponta. Sem isso, ninguem e dono da
pergunta "e funciona junto?".

So crie um terceiro ticket de contrato quando ele virar codigo compartilhado de
verdade (pacote de tipos, client gerado). Contrato que e so especificacao mora no
pai — ticket a mais e um merge humano a mais no caminho.

### Como executar a quebra

O ticket original **vira o pai**: tire a etiqueta `Repo/` dele e reescreva a
descricao com o que e comum mais o contrato de API. Sem `Repo/`, o `pull-ready`
o ignora automaticamente — issue pai nao e despachavel.

Depois crie um filho por repositorio:

```bash
orca linear save-issue --team <TEAM_KEY> --parent-id <IDENT-do-pai> \
  --title "<titulo do filho>" --body-file <arquivo> \
  --label "<Nome do Repo>" --label "<nivel de risco>" \
  --state "Drafted" --json
```

Regras da quebra:

- **um `Repo/` por filho**, o do proprio repositorio. O grupo e exclusivo, entao
  duas etiquetas na mesma issue nao existe — e por isso que a quebra e necessaria.
- **nenhum `blockedBy` entre os filhos.** E o que faz todos entrarem na mesma
  onda e ganharem worktree simultaneo. Quem consome implementa contra mock,
  seguindo o contrato do pai.
- **cada filho inlina o contrato** nos proprios criterios de aceite. O worker nao
  volta ao pai para descobrir o formato.
- **`Risk/<nivel>` vai nos filhos**, nao no pai. O pai nao e despachado; ele so
  agrega.
- os filhos ja nascem em `Drafted`: voce escreveu os criterios de aceite deles
  agora, entao nao ha o que redigir depois. Quem aprova cada um, movendo para
  `Ready for Agent`, e o humano.
- **o pai tambem vai para `Drafted`** quando voce terminar a quebra. Ele fica la
  ate um filho comecar a andar — dai em diante quem o move e o `pull-ready`
  (ver "Issue pai" no Passo 1 daquela skill). Nao mova o pai para
  `Ready for Agent`: sem etiqueta `Repo/` ele nunca e despachado, e o estado so
  criaria a impressao de que alguem vai pegar.

Comente no ticket original explicando a quebra em no maximo 3 linhas, com os
identificadores dos filhos criados.

## Passo 6 - Fechar

1. Aplique `Risk/<high|medium|low>` conforme o `risk_default` do repo, ajustando
   para cima se o ticket mexe em pagamento, autenticacao, dados ou migration.

2. Se o ticket tinha `Fast Track`, **remova a etiqueta**:

   ```bash
   orca linear label remove <IDENT> --label "Fast Track" --json
   ```

   `Fast Track` significa "nao passou por triagem". Depois que voce redigiu, isso
   e falso — e deixar a etiqueta faria o worker aplicar o DoR reduzido e, pior,
   avaliar de novo se a tarefa e trivial, podendo devolver para `Draft` um ticket
   que acabou de ser redigido. Loop.

3. Comente no ticket, curto, em no maximo 5 linhas: o que voce assumiu e o que
   ficou em aberto. Perguntas em formato de lista, respondiveis com uma palavra —
   ele vai ler isso no celular.

   Quando houver pergunta, feche o comentario com a instrucao do ciclo:

   > Para eu incorporar: responda neste comentario e **mova o ticket de volta
   > para `Draft`**. Na proxima passagem da triagem eu leio e refaco.

4. **Mova para `Drafted`.** E o ultimo passo, depois do comentario:

   ```bash
   orca linear status set --id <IDENT> --to "Drafted" --json
   ```

   A ordem importa. `Drafted` e o sinal de "terminei, pode ler" — se voce mover
   antes de comentar, o humano abre o ticket e nao encontra o que voce assumiu
   nem as perguntas.

5. Encerre com um resumo de no maximo 5 linhas: qual ticket voce triou, os repos
   escolhidos e de onde veio a decisao, e **quantos ficaram na fila**. A proxima
   passagem sai em 2 minutos e pega o proximo — nao continue trabalhando.

## O que nunca fazer

- Nao mova o ticket para `Ready for Agent`, nem para nenhum estado alem dele.
  `Ready for Agent` e o botao de start do humano — e a unica coisa que separa
  "redigido" de "vai virar codigo".

  Seus movimentos permitidos sao exatamente estes:

  | Movimento | Quando |
  |---|---|
  | `Draft -> Drafting` | claim, no comeco |
  | `Drafting -> Drafted` | fechamento, no fim |
  | `<qualquer> -> Draft` **em filho** | roteando pedido do pai (Passo 4b) |

  O terceiro e novo e e a unica vez que voce mexe num ticket que nao e o que
  voce esta triando. Ele so vale para filho de um pai que VOCE esta triando
  agora, e so quando o pedido daquele pai e codigo. Nunca mova um ticket
  qualquer para `Draft` porque te pareceu incompleto.
- Nao escreva criterio de aceite pedindo comentario no codigo. O padrao e codigo
  sem comentario explicativo; so repasse o pedido se o humano tiver escrito isso
  no ticket.
- Nao invente criterio de aceite para preencher secao. Secao vazia com pergunta e
  melhor que secao preenchida com chute.
- Nao expanda o escopo do que ele pediu. Se voce acha que falta algo, sugira no
  comentario como ticket separado.
