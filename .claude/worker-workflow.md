# Workflow do worker

Regras que valem para **todo** ticket. O que e especifico do seu — a
especificacao, os comandos do repo, a base branch — esta no prompt que voce
recebeu.

Este arquivo e a fonte da verdade. Se o prompt contradisser algo aqui, siga o
prompt (ele e mais especifico) e registre a divergencia no corpo do PR.

**`<ORCH_ROOT>` nos comandos abaixo** e a raiz do orquestrador, que veio na
primeira linha do seu prompt — a mesma que voce usou para ler este arquivo.
Troque pelo caminho real ao rodar. Nao existe variavel de ambiente com esse
valor: cada chamada de Bash e um shell novo, e um `export` nao sobreviveria de
uma para a outra.

---

## 1. Voce NAO executa comando nenhum do projeto

Nem lint, typecheck, build, teste, migration, servidor de dev — **nem instalar
dependencia** (`npm ci`, `yarn install`, `composer install`, `flutter pub get`).
O hook bloqueia todos, e tentar contornar tambem.

Este fluxo entrega **planejamento e codigo**. A verificacao e humana.

Se algo parecer quebrado, **descreva no PR** — nao rode para conferir.

**Liberado:** todo o git (`status`, `diff`, `add`, `commit`, `push`),
`gh pr create`, leitura de arquivo (`cat`, `grep`, `sed`, `ls`, `find`) e os
comandos `orca`.

## 2. Ambiente incompleto nao e motivo para parar

Esta maquina nao tem `php`, `composer` nem `pnpm`. O `node_modules` ou o
`vendor/` do seu worktree podem nao existir. Nada disso te impede de trabalhar:
voce le codigo como texto e escreve codigo como texto.

Quando esbarrar em algo assim — comando bloqueado, runtime ausente, dependencia
nao instalada, arquivo gerado que falta:

- **siga com a implementacao.** Nao pare, nao abra gate, nao pergunte.
- **nao tente contornar.** Nada de `brew install`, `sudo`, baixar binario ou
  editar PATH. E mudanca de maquina, nao trabalho de ticket.
- **anote** e publique no corpo do PR, em secao dedicada:

  ```markdown
  ## Acoes manuais necessarias
  - `composer install` — php/composer nao existem nesta maquina, `vendor/` ausente
  - `npx prisma generate` — o client do Prisma nao esta gerado
  ```

Se a falta impedir **escrever** o codigo com confianca — um tipo gerado que voce
precisa referenciar e nao consegue ler —, implemente assumindo o contrato
documentado e diga no PR o que assumiu e por que nao pode confirmar.

## 3. Autonomia de decisao

Voce decide sozinho por padrao. Perguntar e caro: ninguem fica lendo a caixa de
entrada, e a sessao que te despachou ja encerrou o turno. Errar de forma visivel
e barato — o humano ve no review do PR.

**Decida e documente** quando as tres valerem:

- a informacao para escolher esta no ticket, no repo ou no prompt
- a escolha aparece no diff
- errar e reversivel sem perder trabalho

Registre em duas linhas, no `PLAN.md` e no corpo do PR:

```
Decisao: <o que foi escolhido>.
Alternativa descartada: <o que> — <por que nao>.
```

**So levante duvida** quando uma destas valer:

- a acao e destrutiva ou irreversivel (apagar dado, migration, mudar contrato
  publico ja consumido)
- muda o ESCOPO do ticket — entregar mais ou menos do que foi pedido
- a informacao nao existe em lugar nenhum que voce alcance, e as opcoes sao
  igualmente plausiveis
- e trade-off de seguranca ou compliance que o humano tem que assumir

**Contradicao entre a spec e os criterios de aceite NAO e motivo para perguntar.**
Resolva pela intencao: escolha a leitura que preserva o criterio mais forte,
implemente, registre. O review do PR e o portao real.

### NUNCA use `orca orchestration ask`

Ele e **bloqueante**, com timeout de 10 min, e neste fluxo ninguem responde.
Observado em 30/07: um worker desistiu no timeout e seguiu, outro entrou em loop
de `--resume` queimando contexto ate a sessao estourar.

Quando um dos quatro casos acima acontecer, faca assim — sem bloquear:

1. comente a duvida no ticket, com a sua recomendacao ja formulada:
   `orca linear comment add <IDENT> --body "..." --json`
2. **siga trabalhando** no que nao depende da resposta
3. se a duvida impedir concluir, entregue o que da e reporte `worker_done` com
   `--outcome failed`, explicando em uma frase

Ficar ocioso esperando resposta nunca e a opcao certa.

---

## 4. Workflow de entrega

### 0. Se o prompt disser RETOMADA, leia o que ja existe antes de tudo

Voce esta num worktree onde um worker anterior — provavelmente voce, noutra
sessao — ja entregou codigo, e o PR esta aberto e revisado. Esta leva acrescenta
commit ali, no mesmo PR.

```bash
gh pr view <url-do-PR> --json title,body,state,headRefName
git log --oneline origin/<base>..HEAD
git status --short
```

Tres regras que valem so aqui:

- **NAO abra PR novo** e **nao crie branch**. Voce ja esta na branch certa.
- **NAO reimplemente o que ja esta feito.** O escopo desta leva e a secao
  `## Leva N`; o resto da descricao e o que ja foi entregue.
- **Se a base andou**, traga ela para dentro em vez de rebasear:

  ```bash
  git fetch origin <base>
  git merge origin/<base>
  ```

  Rebase esta fora de questao: force-push e bloqueado pelo hook global, e
  reescrever a branch invalidaria a revisao que o humano ja fez no PR.

Se houver conflito no merge e voce nao souber resolver com seguranca, pare,
comente no ticket e reporte `worker_done --outcome failed`. Nao invente
resolucao em codigo que voce nao escreveu.

### 1. Mova o ticket para `In Progress`

```bash
orca linear status set --id <IDENT> --to "In Progress" --json
```

### 1b. Se o ticket tem imagem, abra antes de planejar

O prompt avisa quando ha anexo. Se avisar:

```bash
<ORCH_ROOT>/bin/linear-assets.sh <IDENT>
```

Ele imprime o caminho local de cada arquivo. **Abra cada imagem com o Read
antes de escrever o plano.** Screenshot de bug e mockup de tela mudam o que voce
vai construir; planejar so pelo texto produz codigo que resolve outra coisa.

Nao tente abrir a URL `uploads.linear.app` direto: ela devolve 401 sem a chave
da API, e o `WebFetch` nao le imagem nem quando a URL abre.

Os arquivos ficam em `/Volumes/XPG_SSD/developer/.orch-assets/<IDENT>/`, **fora
do worktree**. Nao copie para dentro dele: fora do repositorio nao existe risco
de entrarem no commit, e nao ha nada para apagar depois.

Se o script parar com `volume nao esta montado`, o SSD externo caiu. Nao
improvise: comente no ticket que nao conseguiu ver o anexo e siga com o texto,
dizendo isso no corpo do PR.

Depois de mover, espelhe o estado no worktree — e o que faz o painel do Orca
mostrar em que pe esta cada aba:

```bash
<ORCH_ROOT>/bin/sync-worktree-meta.sh <IDENT>
```

Rode de novo depois de cada mudanca de estado sua (passo 7, e o 2b se ocorrer).

### 2. Escreva o plano em `PLAN.md`, antes de editar codigo

Garanta primeiro que ele nunca sera versionado:

```bash
EX="$(git rev-parse --git-common-dir)/info/exclude"
grep -qxF 'PLAN.md' "$EX" || echo 'PLAN.md' >> "$EX"
```

**Voce nao escreve este plano — o `orch-planner` escreve.** Chame o subagente
`orch-planner` com a especificacao do ticket, o `<IDENT>`, e o caminho do
worktree. Ele roda em Opus, le o codigo e deixa o `PLAN.md` na raiz.

Voce roda em Opus com o teto de raciocinio que o risco do ticket escolheu:
`xhigh` em `Risk/high`, um degrau abaixo em `medium`, dois em `low`. A divisao
nao muda com isso — quem planeja chega com contexto limpo, quem implementa segue
o plano. Medido em 30 dias, planejar e 24% do custo do worker e
implementar e 76% — inverter isso e pagar caro pela parte errada.

**Nao planeje por conta propria "para adiantar".** Se voce escrever o plano e
depois chamar o `orch-planner`, ele revisa a sua conclusao em vez de formar a
dele, e a diferenca de capacidade se perde. Chame primeiro.

Se o `orch-planner` nao existir nesta maquina, o `bin/install-agents.sh` nunca
rodou: **pare e reporte** — nao improvise o plano.

Use `info/exclude`, **nao** o `.gitignore`: o `.gitignore` e versionado e a
mudanca entraria no PR como ruido sem relacao com o ticket.

Publique o plano como comentario no ticket — e o que permite apagar o arquivo
depois, e deixa o plano revisavel do celular:

```bash
orca linear comment add <IDENT> --body-file PLAN.md --json
```

**Tamanho proporcional a mudanca.** Ticket de uma linha nao merece plano de
trinta. Com `Fast Track`, cinco linhas bastam: o que voce leu, o que vai mudar,
por que e seguro.

**Publicado o plano, siga direto para a implementacao.** Nao pare, nao abra
gate, nao espere aprovacao — a menos que o prompt diga que `plan_gate` esta
ligado para este repo.

### 2b. `Fast Track` que nao era trivial

Se o ticket tem `Fast Track` e, ao ler o codigo, voce concluir que **nao** e
trivial — mexe em mais arquivos que o esperado, tem migration escondida, muda
contrato publico, ou o enunciado admite duas leituras:

- **nao implemente**
- comente no ticket o que descobriu, em ate 5 linhas, dizendo por que precisa
  de plano
- devolva para a triagem:
  ```bash
  orca linear label remove <IDENT> --label "Fast Track" --json
  orca linear status set --id <IDENT> --to "Draft" --json
  ```

  `Draft` e a fila da triagem, nao `Drafting` — esse ultimo significa "uma
  triagem esta rodando agora neste ticket", e mandar para la faria o ticket
  ficar parado esperando uma sessao que nunca existiu.
- reporte `worker_done --outcome failed` com uma frase

Devolver custa um ciclo de 2 minutos; implementar errado custa um PR e o review
do humano.

### 3. Implemente somente o escopo do ticket

Leia os arquivos antes de editar. Antes de criar qualquer coisa nova — funcao,
helper, componente, hook, tipo — procure se ja existe no repo. Codigo duplicado
passa no review e apodrece.

#### Nao escreva comentario explicativo

**O codigo tem que se explicar sozinho.** Se voce sente vontade de comentar uma
linha, o problema quase sempre e a linha: renomeie a variavel, extraia a funcao,
quebre a condicao composta em duas com nome. Tente isso primeiro. Comentario e o
conserto que nao conserta.

**Nao escreva:**

- narracao do que o codigo faz — `// incrementa o contador`,
  `// valida o email`, `// retorna o usuario`
- justificativa da sua escolha — `// fiz assim porque o outro jeito quebrava`.
  O "porque" tem lugar proprio neste fluxo: o corpo do PR e o `PLAN.md`
  (secao 3). Em comentario ele apodrece — ninguem atualiza a linha de cima ao
  mudar a de baixo, e ai o comentario passa a mentir.
- cabecalho decorativo, separador, `// TODO`, codigo comentado

**Pode escrever:**

- **docblock** — PHPDoc, JSDoc, docstring — **quando o repo ja usa**. Siga o
  vizinho: se os metodos ao redor tem docblock, o seu tem; se nenhum tem, nao
  comece agora.
- o caso raro em que o fato **nao esta no codigo e nao tem como estar**: contorno
  de bug de terceiro, quirk de API externa, exigencia legal, ordem que parece
  arbitraria e nao e. Uma linha, com o fato — nao com a sua opiniao.

  ```php
  // A Cielo devolve 200 com corpo de erro; o status nao serve de check.
  ```

- o que o **ticket pedir explicitamente**. Pediu comentario, escreve comentario.

Na duvida, nao comente. Comentario que falta, o revisor pede; comentario errado
ele nao percebe.

**Nao mexa em comentario que ja existe** fora das linhas que voce esta alterando.
Limpar comentario alheio incha o diff com mudanca que ninguem pediu e esconde o
que o ticket realmente fez.

### 4. Nao rode nada — ver secao 1

### 4b. Review com contexto limpo, antes de commitar

Chame o subagente `orch-reviewer` (Opus) passando `<IDENT>` e o worktree. Ele le
o diff contra o ticket e devolve um veredito.

**Ele e a unica verificacao automatica que existe neste fluxo.** Com `gate: []`
ninguem roda lint, typecheck nem teste, e quem implementou foi voce, seguindo
plano de outro. Sem este passo o proximo par de olhos e o humano.

| Veredito | O que fazer |
|---|---|
| aprovado | siga para o passo 5 |
| aprovado com ressalvas | siga; transcreva as ressalvas no corpo do PR |
| reprovado | corrija os bloqueantes e chame o `orch-reviewer` **de novo** |

**No maximo duas rodadas de reprovacao.** Se na terceira ainda houver
bloqueante, **nao fique tentando**: abra o PR mesmo assim, transcreva os
bloqueantes abertos em `## Review automatico` e reporte `worker_done` com
`--outcome failed`. Um PR honesto com o problema escrito e util; um worker
girando em circulo consome a leva inteira e nao entrega nada.

Nao discuta o veredito com ele. Se voce acha que o bloqueante esta errado,
registre isso no corpo do PR e siga — quem arbitra e o humano, no review.

### 5. Antes de commitar, apague o `PLAN.md`

Ele ja esta no Linear.

```bash
rm -f PLAN.md
git status --short          # PLAN.md nao pode aparecer aqui
```

**NUNCA use `git add -A` nem `git add .`.** Adicione explicitamente os caminhos
que voce editou. Arquivo de trabalho versionado por engano vira ruido no review
e, no caso do `PLAN.md`, vaza o plano para o historico do repo.

### 6. Commit, push e PR

PR contra a base branch informada no prompt, com `gh pr create`.

Corpo do PR:

- resumo da mudanca
- a lista `manual` do repo, transcrita como roteiro — **comandos literais, SEM
  saida**, porque voce nao rodou nenhum
- o roteiro especifico do ticket
- o passo a passo do que observar para dizer que funcionou
- `## Acoes manuais necessarias`, se houver (secao 2)
- as decisoes que voce tomou (secao 3)
- `## Review automatico`: o veredito do `orch-reviewer`, com as ressalvas e os
  bloqueantes que sobraram. **Transcreva mesmo quando aprovado sem ressalva** —
  a ausencia da secao deve significar "o review nao rodou", nunca "passou".

### 7. Vincule o PR e mova para `In Review`

**Antes de abrir PR, cheque se ja existe um para a sua branch:**

```bash
gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --state open --json url --jq '.[0].url // empty'
```

Se voltar uma URL, **nao abra outro**. Empurre e comente no PR o que esta leva
mudou — e isso que mantem a revisao anterior viva no mesmo lugar:

```bash
git push
gh pr comment <url> --body "## Leva N
<o que mudou agora, em ate 10 linhas, e por que>
<se voce trouxe origin/<base> para dentro, diga>"
orca linear status set --id <IDENT> --to "In Review" --json
```

**Nao reanexe o PR no Linear.** O link ja esta la desde a primeira leva; anexar
de novo cria duplicata no ticket.

Se nao existir PR aberto, e a primeira leva — abra normalmente:

```bash
orca linear attach --current --url <pr-url> --title "PR link" --json
orca linear status set --id <IDENT> --to "In Review" --json
```

Se o seu ticket tem pai, atualize o pai depois de mover:

```bash
<ORCH_ROOT>/bin/sync-parent-status.sh --apply <IDENT-do-pai>
```

Ele so move o pai quando TODOS os irmaos aprovados chegaram no mesmo ponto —
se algum irmao ainda esta implementando, ele nao faz nada e voce segue. Nao
tente decidir isso na mao: a conta e do script.

### 8. NAO faca merge. Nunca. O merge e humano.

### 9. Reporte `worker_done` exatamente uma vez

Com `--outcome succeeded` ou `failed`, incluindo `taskId`, `dispatchId` e
`--files-modified`.

### 10. Heartbeat durante trabalho longo

A cada ~5 min enquanto estiver ativo. Nunca prompt local no terminal.
