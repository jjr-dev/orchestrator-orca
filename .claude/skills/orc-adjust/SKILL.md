---
name: adjust
description: |
  Recebe um pedido em texto livre sobre um ticket que ja virou codigo, descobre
  quais repositorios ele toca, escreve a nova leva na descricao dos filhos
  certos e despacha os workers — retomando o worktree e o PR que ja existem.
  Cria filho novo quando o pedido toca um repo que ainda nao tem um.
  Use sempre que aparecer "/ajustar", "/adjust", "pede pro <ticket> tambem
  fazer X", "manda ajustar o <ticket>", ou quando o humano descrever no chat uma
  mudanca sobre trabalho que ja esta em PR.
---

# Ajustar do painel

## Ancore-se na raiz antes de qualquer comando

As chamadas abaixo sao relativas, e o diretorio de trabalho persiste entre elas.
Rode isto primeiro — uma vez, e vale para a skill inteira:

```bash
cd "${ORCH_ROOT:-.}" && [ -f registry.example.yaml ] \
  || echo "nao estou na raiz do orquestrador: defina ORCH_ROOT ou entre nela"
```

Se reclamar, **pare e resolva**. Sessao aberta fora da raiz carrega estas skills
mas nao acha o `bin/` — e a falha aparece no meio do trabalho, nao no comeco.


Argumento: `/ajustar <IDENT> <pedido em texto livre>`

`<IDENT>` e o **pai** de uma arvore, ou o proprio ticket quando ele nao tem
filhos. O pedido e o que voce escreveria num comentario do Linear — so que aqui
ele vira trabalho despachado na mesma passagem.

## Por que isto existe

Havia dois jeitos de pedir ajuste, e os dois eram ruins.

Comentar no Linear e mover para `Draft` funciona, mas custa uma passagem de
triagem e um `Ready for Agent` seu. Falar direto com o worker no worktree e
imediato, mas o worker esta calibrado para implementar seguindo um plano, nao
para decidir escopo — e ele so enxerga o proprio repo, entao nao teria como
descobrir qual outro muda.

Aqui voce fala com o coordenador, que ve a arvore inteira, e ele despacha.

## O que voce NAO faz aqui

- **Nao mergeia.** Nunca. Continua sendo humano.
- **Nao reabre filho que o pedido nao toca.** Reabrir custa uma leva inteira de
  worker e suja um PR que ja estava pronto.
- **Nao adivinha o repo pelo nome do ticket.** Voce le codigo (Passo 2).

## Passo 0 - Contexto

1. `orca status --json` deve responder.
2. `orca skills get orchestration --full` — esta skill despacha worker, entao os
   flags precisam vir da versao instalada, nao de memoria.
3. Leia o `registry.yaml`: `linear_team`, `wip_max`, e o mapa
   etiqueta -> `{orca_repo_id, base, setup, gate, manual, pair, risk_default}`.
4. **Confira que todo `base` que voce for usar comeca com `origin/`.** Mesma
   regra do `pull-ready`, mesmo motivo: sem o prefixo o Orca corta da ref local,
   que pode estar dias atras.

5. Nomeie a sua aba, para ela nao virar mais uma "Claude Code" no painel:

```bash
./bin/name-terminal.sh "ajuste <IDENT>"
```

## Passo 1 - Ler a arvore

```bash
orca linear issue <IDENT> --children --comments --json
```

Guarde, por filho: identificador, estado, etiqueta `Repo/`, e se tem PR.

```bash
./bin/resume-target.sh <IDENT-do-filho>
```

Se `<IDENT>` nao tem filho nenhum, ele proprio e o alvo — trate-o como o unico
"filho" no resto do procedimento.

**Se o ticket tem imagem**, baixe antes de decidir qualquer coisa:

```bash
./bin/linear-assets.sh <IDENT>
```

## Passo 2 - Descobrir quais repos o pedido toca

**Este e o unico julgamento real desta skill, e ele exige ler codigo.**

Todo o resto do fluxo virou script justamente para tirar julgamento do caminho.
Aqui nao da: so se sabe qual repo muda abrindo os arquivos. Nome de ticket e
nome de repo enganam.

Para cada repo candidato — os que ja tem filho, mais os que o `pair` do registry
sugere — abra os arquivos que o pedido descreve e confirme que o comportamento
citado mora ali. Se o pedido fala de uma tela, ache a tela. Se fala de um
endpoint, ache a rota.

Na duvida entre dois repos, **escolha pelo codigo que voce leu** e diga qual
escolheu e por que, no comentario do Passo 6. Nunca reabra os dois "por
seguranca": cada um custa uma leva de worker.

Se o pedido nao tocar repo nenhum que voce consiga confirmar, **pare** e diga
isso no chat. Nao invente alvo.

## Passo 3 - Rotear por repo

A decisao e por **repositorio**, nunca por "isso e correcao ou e escopo novo" —
essa distincao nao muda nada de concreto e so gera discussao.

| Repo que o pedido toca | O que fazer |
|---|---|
| ja tem filho, `resume-target` diz `RESUME`/`RECREATE` | `## Leva N` nesse filho |
| ja tem filho, `resume-target` diz `FRESH pr-fechado` | `## Leva N` nesse filho |
| nao tem filho nenhum | **cria** filho novo |

Filho novo nasce como no Passo 5 do `/triage-tickets`: etiqueta `Repo/`, o
contrato do pai inlinado, e sem `blockedBy` para os irmaos.

## Passo 4 - Escrever a leva

Em cada filho afetado, **acrescente** ao fim da descricao:

```markdown
## Leva N

<o pedido, em uma ou duas frases, na sua leitura>

### Muda
- caminho/real/do/arquivo — <o que muda>

### Criterios de aceite desta leva
- [ ] verificavel, e so sobre o que muda agora
```

N e a proxima: se ja existe `## Leva 2`, a sua e a 3.

**Nao toque no que ja esta escrito acima.** Aquelas secoes descrevem codigo que
existe e ja foi revisado; reescrever faz o worker reimplementar tudo e dobra o
diff do PR sem motivo.

**Nao repita criterio ja atendido** dentro da secao nova. O worker le a
`## Leva N` como escopo de trabalho: tudo que estiver ali, ele vai fazer.

## Passo 5 - Claim e despacho

**Capacidade primeiro.** Conte quantos tickets da empresa ja estao em
`Scheduled` ou `In Progress` e compare com o `wip_max` dela. O que nao couber
**nao fica de fora**: mova para `Ready for Agent` e diga no chat que o poller
pega nas proximas rodadas.

Para cada filho que cabe, **nesta ordem**:

1. `orca linear status set --id <FILHO> --to "Scheduled" --json`
2. so entao crie qualquer coisa no Orca

Inverter gera worker duplicado se algo falhar no meio — mesma regra do
`pull-ready`, mesmo motivo.

Escreva o prompt como o `pull-ready` manda (Passo 5 daquela skill): comece com o
`cat` do `worker-workflow.md`, e quando for retomada, com o bloco `RETOMADA.`
antes de tudo. Transcreva **so a `## Leva N`** como escopo; o resto da descricao
vai como contexto do que ja existe.

Despache pelo que o `resume-target.sh` respondeu:

```bash
# RESUME / RECREATE
orca orchestration worker-start --task <taskId> \
  --worktree "path:<worktree>" --agent claude $(./bin/implementer-model.sh <IDENT> --flags) --json

# FRESH
orca orchestration worker-start --task <taskId> \
  --worktree new-top-level --repo id:<orca_repo_id> \
  --name <slug> --agent claude $(./bin/implementer-model.sh <IDENT> --flags) --setup run --json
```

Em retomada, **nao passe flag de criacao** (`--repo`, `--base-branch`, `--name`,
`--setup`). O Orca rejeita, e e essa rejeicao que impede cortar de
`origin/<base>` por acidente.

**Confirme que o worker arrancou** — `input_accepted` nao significa que o agente
comecou. Mesma checagem do `pull-ready`: veja se aparece agente em `working` no
worktree. Se nao aparecer, mande um Enter com `orca terminal send --text ""
--enter`, e **nao redespache**.

Depois de cada despacho:

```bash
./bin/sync-worktree-meta.sh <FILHO>
```

## Passo 6 - Fechar

Comente **no pai**, uma linha por filho:

```
ACME-140  Leva 2  ->  retomado em acme-140-checkout-recorrente, PR #58
ACME-146  novo    ->  worktree e PR novos (repo sem filho ate agora)
ACME-139  intocado -> o pedido nao alcanca a API
```

Diga tambem, em uma linha, **por que** voce escolheu esses repos — foi o arquivo
que voce leu, nao a intuicao. E o que permite o humano perceber que voce errou o
alvo antes de o worker terminar.

Depois:

```bash
./bin/sync-parent-status.sh --apply
```

## Relatorio no chat

Curto, porque o humano esta olhando:

```
ACME-138 "Checkout recorrente"
  toca: App (confirmado em src/context/run-tracker.tsx)
  ACME-140  Leva 2, retomado no PR #58   worker working
  ACME-139  intocado
  1 despachado, 0 na fila
```

Se nao despachou nada, diga o que faltou e pare. Nao invente trabalho para ter
o que reportar.
