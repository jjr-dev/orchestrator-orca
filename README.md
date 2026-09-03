# Orquestrador multi-projeto — Claude Code + Orca + Linear

Um painel que le tickets do Linear, despacha agentes autonomos do Claude Code em
worktrees isolados de varios repositorios, e devolve pull requests. Voce escreve
a ideia no celular; o PR aparece.

Nao contem codigo de cliente. Nunca faz merge — essa decisao continua sua.

```
registry.yaml          SUA config: etiqueta do Linear -> repo, base, modelos
                       (ignorada pelo git; o template e registry.example.yaml)
CLAUDE.md              regras do coordenador
bin/                   prechecks, resolvedor de modelo, diagnostico, edicao do registry
.claude/skills/        operacionais + as 6 de configuracao
.claude/agents/        orch-planner, orch-reviewer (fonte; instalados em ~/.claude)
automations/           criacao dos cronjobs do Orca
docs/                  armadilhas que ja custaram caro
```

## Como funciona, em uma passada

```
voce escreve a ideia no Linear (estado Draft)
        v
/triage-tickets   le o repo de verdade e reescreve o ticket em formato executavel
        v
voce aprova       arrastando para "Ready for Agent" — este e o unico Start
        v
/pull-ready       resolve o repo pela etiqueta Repo/, cria o worktree, despacha
        v
worker            planeja (subagente), implementa, revisa (subagente), abre o PR
        v
voce revisa e faz o merge                    <- o merge nunca e automatico
```

Os cronjobs rodam a triagem e o despacho a cada 2 minutos, mas so acordam o
agente quando ha trabalho: um precheck barato decide antes.

---

# Instalacao

## Passo 1 — Pre-requisitos

| O que | Para que | Conferir |
|---|---|---|
| [Orca](https://orca.computer) | worktrees, terminais, cronjobs | `orca status --json` |
| Claude Code | os agentes | `claude --version` |
| `jq` | tudo que fala com API | `jq --version` |
| `python3` + `pyyaml` | registry e prechecks | `python3 -c 'import yaml'` |
| `git` | worktrees | `git --version` |
| `gh` autenticado | o worker abrir PR | `gh auth status` |
| conta no Linear | os tickets | — |

```bash
brew install jq gh
python3 -m pip install pyyaml
gh auth login
```

## Passo 2 — Duas decisoes antes de instalar

**Um workspace, um time no Linear.** Nao crie um time por projeto. No Linear os
estados de workflow sao por time: com tres times voce definiria os nove estados
tres vezes, com grafia identica, e os scripts comparam string literal. Um acento
fora do lugar deixa aquele time silenciosamente morto. A separacao por projeto e
feita pela etiqueta `Repo/`.

**Quais repositorios entram, e de qual branch saem as features.** Tenha a lista
com o caminho local de cada um. Se algum repo tem `main` e `develop`, saiba qual
e — errar faz todo worker daquele repo partir de codigo velho, e nada acusa.

## Passo 3 — Clonar e abrir

```bash
git clone <este-repo> orchestrator
cd orchestrator
claude
```

## Passo 4 — `/orchestrator-setup`

```
/orchestrator-setup
```

Ela diagnostica, mostra **um** plano, pede **uma** confirmacao, executa e
verifica. Rodar de novo so completa o que faltou — nunca refaz o que existe.

| Etapa | O que acontece |
|---|---|
| diagnostico | `bin/doctor.sh` diz o que ja existe e o que falta |
| registry | copia `registry.example.yaml` para `registry.yaml` se ainda nao houver |
| Linear | chama `/orchestrator-linear`: token, 9 estados, grupos de etiqueta |
| repos | chama `/orchestrator-repo-add` para cada um: Orca + etiqueta + registry |
| subagentes | `bin/install-agents.sh` copia para `~/.claude/agents/` |
| teste manual | roda os prechecks e um despacho de verdade, antes de qualquer cron |
| cronjobs | le `orca automations create --help` e cria as tres automations |
| checklist | lista o que so voce consegue fazer no app |

### O token do Linear

**A skill nunca pede seu token e nunca o grava.** Quando falta, ela te entrega
um comando para voce mesmo rodar — o `!` no inicio executa na sua sessao:

```
! umask 077 && printf 'export LINEAR_API_KEY="COLE_AQUI"\n' >> ~/.zshenv && chmod 600 ~/.zshenv
```

O token sai de *Linear → Settings → Security & access → Personal API keys*.

Tres detalhes que ja custaram tempo:

- **`~/.zshenv`, nao `.zshrc`.** O `.zshrc` so e lido por shell interativo, e os
  prechecks do cron rodam em shell nao interativo.
- **Reinicie o Orca depois de criar a chave.** Ele e app de GUI e herda o
  ambiente do launchd de quando abriu; chave criada depois nao chega nele.
- **Se voce colar o token no chat, ele vazou** para o transcript. Revogue e gere
  outro.

## Passo 5 — O que so voce consegue fazer

O setup termina aqui, e **sem estes itens o sistema fica mudo**:

- [ ] ligar o **auto mode** em `Settings → Agents` do Orca (o badge tem que aparecer)
- [ ] deixar o Orca como item de inicializacao
- [ ] impedir a maquina de dormir na janela de trabalho
- [ ] no Linear, desligar as automations nativas *PR aberto → In Progress* e
      *review → In Review*, que brigam com o worker movendo o mesmo ticket.
      **Manter** *PR merged → Done*

## Passo 6 — Testar antes de confiar

Nesta ordem, e so siga se cada uma passar:

1. `./bin/has-ready.sh <TEAM>` — deve sair 1 com a fila vazia
2. `/reconcile` com tudo limpo — deve dizer "tudo consistente"
3. um ticket real com `/pull-ready <empresa>`, acompanhando na tela
   (com o argumento, para nao puxar todas as empresas no primeiro teste)
4. **so entao** deixe os cronjobs rodarem
5. teste de proposito: reinicie o Orca no meio de um ticket e rode `/reconcile`.
   O ticket tem que voltar para `Ready for Agent` com comentario.

Ligar cron antes de o caminho manual funcionar transforma um erro de
configuracao num bug intermitente que dispara a cada 2 minutos.

## Passo 7 — Confirmar que esta tudo ligado

```bash
./bin/doctor.sh
```

Sai `0` se tudo passou, `1` se ha falha, `2` se ha so avisos. **Nao considere a
instalacao pronta com FALHA aberta.**

---

# Configuracao no dia a dia

| Preciso... | Comando |
|---|---|
| acrescentar um repositorio | `/orchestrator-repo-add` |
| ver ou trocar modelo e effort | `/orchestrator-models` |
| criar estado ou etiqueta que falta | `/orchestrator-linear` |
| descobrir por que um ticket nao anda | `/orchestrator-sync` |
| conferir se esta tudo ligado | `/orchestrator-doctor` |

## Acrescentar um repositorio

```
/orchestrator-repo-add
```

Tres sistemas precisam concordar — Orca (sabe clonar), Linear (tem a etiqueta) e
registry (liga os dois). Se um ficar de fora, o ticket some sem erro. A skill
descobre sozinha a base branch e o gerenciador de pacotes, e **pergunta** quando
o repo tem `main` e `develop`.

🔴 O nome da etiqueta e a chave do registry precisam ser identicos byte a byte.
Divergir num espaco deixa todo ticket daquele repo invisivel.

## Ajustar modelo e effort

```
/orchestrator-models
```

Ela resolve o mapa **de verdade**, rodando o resolvedor, em vez de so ler o YAML
— por semanas esse bloco foi decoracao, com os valores la e nada os lendo.

Antes de aplicar, ela diz a consequencia de custo. O resumo desconfortavel:
`effort` **nao** e alavanca de custo. Ele alcanca so a saida, ~15% da conta;
quem manda sao as leituras de contexto, 56%, e essas seguem o preco do modelo.

## Quando as tres pontas divergirem

```
/orchestrator-sync
```

A divergencia tipica nasce de uma edicao pela interface do Linear: alguem
renomeia uma etiqueta e o registry fica com o nome velho. Nada quebra, nenhum
erro aparece, e os tickets daquele repo param de ser roteados.

---

# Editar a mao

As skills sao **conveniencia sobre o `registry.yaml`, nunca substituto dele**.
Tudo o que elas fazem voce faz editando o arquivo, e o inverso tambem: edite a
mao e a proxima skill respeita. Nenhuma skill guarda estado em outro lugar.

```yaml
defaults:
  models:
    orchestrator: opus              # o painel
    planner: opus                   # o subagente que escreve o PLAN.md
    implementer_by_risk:            # quem implementa, pelo risco do ticket
      high:   { model: opus, effort: xhigh }
      medium: { model: opus, effort: high }
      low:    { model: opus, effort: medium }
    implementer_fallback: { model: opus, effort: xhigh }
    reviewer: opus                  # o subagente que le o diff

companies:
  acme:
    linear_team: ACME
    wip_max: 3                      # workers simultaneos; dimensione pela RAM
    repos:
      "Acme - API":                 # identico a etiqueta Repo/ no Linear
        slug: api-acme
        orca_repo_id: <uuid do `orca repo add`>
        base: origin/main           # 🔴 o prefixo origin/ nao e cosmetico
        setup: npm ci               # documentacao; o agente nunca executa
        gate: []                    # politica de execucao zero
        manual: [npm run lint, npm run build]
        risk_default: high
```

Quando uma skill escreve, ela passa por `bin/registry-edit.py`, que edita o
texto de forma cirurgica em vez de reserializar o YAML — um round-trip por
`yaml.safe_load`/`yaml.dump` derrubaria o arquivo de 551 para 343 linhas e
apagaria todos os comentarios, que sao a auditoria. Ele mostra o diff, valida o
resultado, e **aborta se a edicao tocar qualquer chave alem da pretendida**.

```bash
./bin/registry-edit.py show                     # o estado atual, legivel
./bin/registry-edit.py --dry-run set-model ...  # o diff, sem gravar
./bin/test-registry-edit.sh                     # 19 testes contra fixture
```

`registry.yaml` esta no `.gitignore`. O template versionado e o
`registry.example.yaml` — **nunca tire o registry de la**: ele tem nome de
cliente, id de repo e a topologia inteira da sua operacao.

---

# Quando algo nao funciona

| Sintoma | Causa provavel | Onde olhar |
|---|---|---|
| nenhum ticket e despachado | etiqueta `Repo/` faltando ou com nome divergente | `/orchestrator-sync` |
| o cron nao dispara | estado renomeado no Linear, ou precheck sem `+x` | `./bin/doctor.sh` |
| `orca` diz que nao esta rodando | o app esta fechado | abra o Orca |
| a chave existe mas o Orca nao a ve | criada depois de o app abrir | reinicie o Orca |
| worker parte de codigo velho | `base` sem prefixo `origin/` | `grep 'base:' registry.yaml` |
| o worker nao seguiu as regras | primeira linha do prompt com caminho errado | `.claude/worker-workflow.md` |
| o subagente rodou no modelo errado | fonte editada sem reinstalar | `./bin/install-agents.sh` |
| `worker-start` diz `selector_not_found` | `orca_repo_id` velho | `orca repo list --json` |

Comece sempre pelo `./bin/doctor.sh`. A falha caracteristica deste sistema nao
levanta erro — o hook ja passou semanas registrado num arquivo que o worker
nunca leu, e 258 comandos de projeto passaram sem barreira.

Mais em [`docs/armadilhas.md`](docs/armadilhas.md).

---

# Como o sistema se comporta

As secoes abaixo sao referencia: o que o orquestrador faz sozinho, e por que faz
assim. Nada aqui e passo de instalacao.

## O kill switch

```bash
touch PAUSE   # na raiz do orquestrador: para tudo, sem desabilitar automation
rm PAUSE      # volta
```

## O worker sempre comeca do codigo atualizado

O Orca busca o remoto antes de criar o worktree — voce nao precisa dar `pull` na
maquina antes de mandar um ticket.

Mas isso depende do prefixo `origin/` no campo `base` do registry. Medido em
10/08, num repo real, com a `main` local 5 dias atras do remoto:

| `base` | O que o Orca faz | Onde a branch nasce |
|---|---|---|
| `origin/main` | `fetch --no-tags origin +refs/heads/main:...` | `4bfe5162` — tip do remoto ✅ |
| `main` | nada, usa a ref local | `e4496745` — 5 dias velho ❌ |

Na mesma medicao, **10 dos 20** `origin/<base>` locais estavam atrasados em
relacao ao remoto. O fetch do Orca e o que fecha essa lacuna.

Escrever `development` em vez de `origin/development` faz o worker implementar
sobre codigo velho **sem nada acusar**: o PR abre, passa no review, e o problema
so aparece no conflito de merge. Por isso o `/pull-ready` recusa despachar repo
cuja `base` nao comece com `origin/`.

Conferir na mao:

```bash
grep -n '^\s*base:' registry.yaml | grep -v 'base: origin/'   # nao pode sair nada
```

## Como o codigo sai

Sem comentario explicativo. Nada de `// incrementa o contador` nem de
`// fiz assim porque o outro jeito quebrava` — se uma linha precisa de
comentario para ser entendida, o worker e instruido a melhorar o nome ou extrair
a funcao em vez de comentar.

O que continua permitido: **docblock** (PHPDoc, JSDoc, docstring) onde o repo ja
usa, e o fato que nao cabe no codigo — contorno de bug de terceiro, quirk de API
externa, exigencia legal. Se voce quiser comentario em algum ticket especifico,
peca no proprio ticket; ai ele escreve.

O "porque" de cada decisao nao some — ele vai para o `PLAN.md` (publicado como
comentario no Linear) e para o corpo do PR, que e onde alguem vai procurar
depois. Em comentario de codigo ele apodreceria: ninguem atualiza o comentario
ao mudar a linha de baixo.

O reviewer aponta comentario sobrando como **ressalva**, nunca como bloqueante.

## Worktree de ticket se limpa sozinho

O `/reconcile` das 8h roda `bin/cleanup-worktrees.sh --apply` e remove os
worktrees de ticket que ja fecharam o ciclo. Antes disso eles se acumulavam para
sempre: **43 worktrees / 49 GB** na medicao de 17/08, desde julho.

Ele so olha branch do padrao `acme-dev/acme-<N>-` — worktree que voce criou na mao
nunca entra — e so remove quem passa nas quatro:

| # | Condicao |
|---|---|
| 1 | `git status --short` vazio — nada por commitar |
| 2 | `git log HEAD --not --remotes` vazio — nenhum commit local fora do remoto |
| 3 | PR daquela branch esta `MERGED` |
| 4 | ticket em `Done` |

Falhou uma, ele mantem e diz o motivo. Rode sem `--apply` para so listar:

```bash
bin/cleanup-worktrees.sh
```

A condicao 2 tem uma sutileza que custou uma medicao errada: **nao** compare o
HEAD local com o SHA do PR por igualdade. O worktree costuma ficar *atras* do PR
— alguem empurrou commit depois, pela UI ou de outra maquina — e igualdade
reprovaria 3 dos 43 sem motivo. A pergunta certa e "existe commit aqui que nao
esta em nenhuma ref remota?".

No fim ele limpa tambem as pastas de anexo (`.orch-assets/<IDENT>/`), por uma
regra propria e mais simples: sai o que esta `Done` ou sumiu do Linear. Sao duas
fontes de acumulo independentes — a triagem baixa anexo de ticket que talvez
nunca vire worktree, entao a lista de pastas nao e a mesma dos worktrees e exige
consulta separada.

Apagar anexo nao perde nada: o arquivo veio do Linear e o `linear-assets.sh`
baixa de novo. Por isso a regra pode ser mais frouxa que a dos worktrees, que
guardam codigo.

`orca worktree rm` na mao continua bloqueado pelo hook, de proposito: a decisao
mora num script versionado, nao no julgamento do agente da vez.

## Imagem anexada no ticket

Screenshot de bug e mockup de tela chegam ate o worker. Nao chegavam antes de
28/08: o fluxo era inteiramente cego a imagem.

O que impedia e que `uploads.linear.app` **nao e URL publica** — devolve 401 sem
a chave da API. Colar a URL no prompt nao adianta, e o `WebFetch` nao leria
imagem nem se a URL abrisse. O unico caminho e baixar autenticado e apontar o
arquivo local, que o Read do Claude Code le como imagem de verdade.

```bash
bin/linear-assets.sh ACME-129
```

Varre descricao, comentarios e anexos, baixa tudo e imprime o caminho local de
cada arquivo ao lado da URL de origem. Sem anexo diz `nenhum anexo` e sai 0.

Tres pontos do fluxo mudaram, e a ordem importa:

| Onde | O que faz |
|---|---|
| triagem | baixa e **olha** antes de escrever a spec, e repete a URL na secao `## Anexos` |
| `pull-ready` | detecta imagem na descricao e manda a linha de download no prompt |
| worker | baixa e abre antes de planejar (passo 1b), e o planner tambem le |

**A triagem e o elo fragil.** Ela substitui a descricao inteira; se nao repetir o
`![](...)`, a imagem some do ticket antes de o `pull-ready` saber que existiu.

Os arquivos vao para `/Volumes/XPG_SSD/developer/.orch-assets/<IDENT>/`: SSD
externo, fora de qualquer repositorio git. Nao ocupam disco interno e nao ha como
serem commitados por acidente — diferente do `PLAN.md`, que mora no worktree e
por isso precisa do `info/exclude`. Se o SSD estiver desmontado o script sai 2 em
vez de escrever no disco interno.

## Ticket pai acompanha os filhos

Quando o escopo atravessa repos, o ticket vira pai com uma sub-issue por
repositorio. O pai nao tem worker e nao tem PR, entao ninguem nunca o movia: ele
ficava em `Drafted` enquanto os filhos rodavam o ciclo inteiro, e no quadro
parecia trabalho parado.

```bash
bin/sync-parent-status.sh            # dry run
bin/sync-parent-status.sh --apply
```

| Filhos (ignorando os em `Draft`/`Drafting`/`Drafted`) | Pai vai para |
|---|---|
| todos em `Scheduled` ou adiante | `In Progress` |
| todos em `In Review` ou adiante | `In Review` |
| todos em `Done` | `Done` |

**Filho em `Ready for Agent` segura o pai.** Essa e a distincao que faz a regra
valer a pena: `Drafted` e "ainda nao aprovado", entao nao representa trabalho
pendente da onda; `Ready for Agent` e "aprovado e ainda nao arrancou", e o pai
so deve entrar em progresso quando a onda inteira entrou.

**So anda para frente.** Se voce reabrir um filho e a conta der para tras, o
script reporta e nao mexe — voltar estado desfaria uma decisao sua.

Roda em tres momentos: o `pull-ready` chama depois de despachar a onda, o worker
chama ao mover para `In Review`, e o `/reconcile` varre todo dia. O terceiro nao
e redundancia: o passo para `Done` e sempre humano e acontece fora de qualquer
sessao de agente, entao so a varredura pega.

## Push para branch protegida e impossivel, nao proibido

Desde 29/08 existe um hook **global** em `~/.claude/hooks/git-push-guard.sh`,
ligado no `~/.claude/settings.json`. Ele vale para toda sessao do Claude Code,
worker incluido — diferente do `bin/guard-commands.sh`, que so vale neste
diretorio.

Bloqueia push para `main`, `master`, `production`, `develop`, `development`,
`sandbox`, `staging`, `release` (lista editavel em
`~/.claude/hooks/protected-branches.txt`) e qualquer force-push.

Pega as formas que uma regra de prefixo deixaria passar: `git push origin
HEAD:main`, `git push -u origin main`, `git push --all`, `git push origin :main`,
`git push` sem argumento estando em `main`, aspas, `git -C <path> push`, e o
comando escondido depois de um `&&`.

**So limita agente.** Hook intercepta a ferramenta Bash do Claude Code; push que
voce der no seu terminal nao passa por ali.

Nao substitui branch protection no GitHub, que e server-side e vale para todo
mundo. Cobre o caso que importa aqui: agente rodando sozinho de madrugada.

## Nova leva no mesmo PR, em vez de ticket novo

Ate 29/08, pedir ajuste em algo que ja estava em PR criava uma sub-issue nova.
Ela nascia num worktree novo, cortado de `origin/<base>` — que ainda nao tinha o
codigo do PR anterior. Na pratica isso obrigava a **mesclar o PR anterior antes
de poder ajustar**, e a revisao ja feita ficava num PR e o ajuste noutro.

Agora o ciclo volta para o mesmo ticket:

```
ACME-140  In Review  PR #58
   voce comenta e move para Draft
ACME-140  Draft -> Drafting -> Drafted -> Ready for Agent
   worker retoma no worktree que ja existe
   commit novo na mesma branch, no MESMO PR #58
ACME-140  In Review
```

**Um ticket = um worktree = um PR.** Quem decide retomar ou comecar do zero e um
script, nao o julgamento do agente da vez:

```bash
bin/resume-target.sh ACME-140
```

| Worktree | PR | Resultado |
|---|---|---|
| existe | aberto | `RESUME` — despacha no worktree |
| sumiu | aberto | `RECREATE` — recria da propria branch |
| — | mergeado | `FRESH pr-fechado` — branch nova com sufixo, PR novo, mesmo ticket |
| — | nenhum | `FRESH primeira-vez` |

A fonte da verdade do PR e o **anexo no Linear**, nao busca por nome de branch:
o anexo e o link que o proprio worker registrou. Buscar por padrao acharia PR de
ticket com numero parecido.

O que torna a retomada segura: `--worktree "path:..."` faz o Orca **rejeitar**
`--repo`, `--base-branch`, `--name` e `--setup`. Sem `--base-branch` nao existe
caminho para cortar de `origin/<base>`. Passar um deles quebra o comando inteiro
em vez de fazer a coisa errada calado.

### Pedido no pai desce para os filhos

Pai nao tem repo nem PR. Pai em `Draft` faz a triagem decidir de quem e o
pedido: se for contrato de API ou roteiro ponta a ponta, ela ajusta o pai; se
for codigo, ela escreve a `## Leva N` nos filhos afetados, move **esses** para
`Draft` e devolve o pai para `Drafted`.

Voce comenta num lugar so e nao precisa saber qual repo mexe.

### O pai passa a poder recuar

Um filho que volta para `Draft` **com PR** e um filho reaberto — diferente de um
filho que nunca foi aprovado, que continua sendo ignorado. Filho reaberto conta e
puxa o pai para `Drafted`.

Essa e a unica excecao a regra "o pai so anda para frente", e ela e coerente:
reabrir um filho e uma acao sua, entao seguir o pai para tras obedece voce em vez
de desfazer. Fora desse caso o script continua recusando andar para tras.

`Drafted` e nao `Draft` de proposito: `Draft` e a fila da triagem, e o pai
cairia nela a cada 2 minutos sem ter nada a redigir.

## Pedir ajuste falando, em vez de comentar e mover estado

```
/ajustar ACME-138 ao fechar o app no meio da corrida o objetivo some
```

O painel le a arvore, **le o codigo** para descobrir quais repos o pedido toca,
escreve a `## Leva N` nos filhos certos e despacha — retomando worktree e PR
que ja existem. Sem passar por `Ready for Agent`.

Havia dois caminhos antes, e os dois eram ruins. Comentar no Linear e mover para
`Draft` custa uma passagem de triagem e um clique seu. Falar com o worker no
worktree e imediato, mas o worker so enxerga o proprio repo — bom para
implementar um plano, nao para decidir escopo. O painel ve a arvore inteira.

**O pedido no chat E a aprovacao humana.** E por isso que so o `/ajustar`
despacha direto; automation nenhuma ganha esse direito.

Roteia por **repositorio**, nunca por "e correcao ou e escopo novo":

| Repo que o pedido toca | O que acontece |
|---|---|
| tem filho com PR aberto | `## Leva N` nele, retoma no mesmo PR |
| tem filho com PR fechado | `## Leva N` nele, branch nova |
| nao tem filho | cria filho novo, despacha |

Respeita o `wip_max`: o que nao couber vai para `Ready for Agent` e o poller
pega depois.

**Este e o unico julgamento que sobrou no fluxo.** Todo o resto virou script
para tirar decisao do agente da vez; aqui nao da, porque so se sabe qual repo
muda lendo o codigo. A contencao e ele reportar o roteamento no chat e no
comentario do pai, com o arquivo que leu — voce ve na hora se ele errou o alvo.

## O painel diz de que ticket e cada aba

Antes de 29/08 o painel era ilegivel: worktrees chamados `acme-140-checkout-recorrente`,
`linkedLinearIssue` **nulo em todos**, `workspaceStatus` preso em `in-progress`
para sempre, e os terminais do painel sem nome nenhum — 8 abas "Claude Code"
identicas.

```bash
bin/sync-worktree-meta.sh            # todos
bin/sync-worktree-meta.sh ACME-140    # um
```

Grava tres coisas a partir do estado no Linear: nome legivel
(`ACME-140 · Checkout recorrente: fluxo no app`), o link do ticket, e a coluna do
board (`todo` / `in-progress` / `in-review` / `completed`).

A fonte da verdade e sempre o Linear — o script le e espelha, nunca decide. Roda
no despacho, a cada mudanca de estado do worker, e uma vez por dia no
`/reconcile` para pegar o que mudou fora de sessao.

Diferente dos outros scripts, **nao tem dry-run**: so escreve metadata do Orca,
nao mexe em Linear nem em codigo.

Nao use `--display-name` no `worker-start`: e flag de criacao, entao funciona no
despacho novo e e **rejeitada** na retomada. Um comando depois vale para os dois.

### As abas do painel

```bash
bin/name-terminal.sh "triagem ACME-138"
```

Cada skill nomeia a propria no comeco. Como ela sabe qual aba e a sua: **nao
sabe, deduz.** Nao existe `orca terminal current` nem variavel com o handle, e a
sessao que roda o comando e, por definicao, a que produziu output agora — o
`max_by(lastOutputAt)` do painel. E a mesma deducao que o `/reconcile` usa para
nao se matar ao fechar terminais velhos.

Se duas sessoes do painel arrancarem no mesmo segundo, uma pode renomear a aba
da outra. O estrago e um titulo errado. **Nunca use essa deducao para nada
destrutivo.**

## Um papel por lugar, e o risco decide o teto de quem implementa

Ate 02/09 isto era so um bloco no `registry.yaml` que ninguem lia: **tudo rodava
Opus**. Medido em 30 dias de transcript, o Sonnet era 0,07% dos tokens de saida.
Agora cada papel tem um lugar concreto onde e ligado.

| Papel | Modelo e effort | Onde e ligado |
|---|---|---|
| orquestrar, triar, rotear | Opus 5, `xhigh` | `"model": "opus"` no `.claude/settings.json` do painel |
| planejar dentro do worktree | Opus 5, `xhigh` | subagente `orch-planner` |
| implementar | Opus 5, effort pelo risco | `bin/implementer-model.sh`, no `worker-start` |
| revisar o diff | Opus 5, `xhigh` | subagente `orch-reviewer` |

O `xhigh` de tres das quatro linhas nao esta escrito em lugar nenhum do repo: e
o `effortLevel` do `~/.claude/settings.json`, configuracao de sessao que desce
para todos de uma vez. So o implementador o sobrescreve, porque so ele tem um
eixo — o risco do ticket — para variar.

### Por que nesta ordem

A medicao contradiz a intuicao em dois pontos, e os dois mudam a decisao.

**O custo e leitura, nao escrita.** Na conta do worker: cache read 56%, cache
write 28%, saida 15%. Trocar o modelo muda o preco do token de **entrada**, e e
por isso que Sonnet cortava 60% — nao porque "pensa menos".

A consequencia pratica e desconfortavel: **`effort` nao e alavanca de custo.**
Ele so afeta a saida, ou seja 15% da conta. Baixar o teto de raciocinio de um
ticket de risco baixo e uma escolha de qualidade proporcional ao risco, nao uma
economia — quem economizava era o modelo mais barato, e essa opcao foi trocada
de proposito por uniformidade.

**Planejar e barato.** Dentro do worker, ler-e-planejar e 24% do custo e
implementar e 76% (284 sessoes). Por isso colocar o modelo mais caro no
planejamento sai barato, e o modelo mais barato na implementacao rende muito.

### `effort` nao mora aqui

Fica em `effortLevel` no `~/.claude/settings.json`, e ja esta em **`xhigh`** —
um degrau acima de `high`. Vale para painel, worker e subagentes, porque e
configuracao de sessao, nao de papel.

Nao duplique no registry nem no despacho. `orca worker-start` aceita `--effort`,
mas exige `--model` junto e sobrescreveria o global: dois lugares para divergir,
e o sintoma seria silencioso.

E lembre da proporcao: `effort` mexe na **saida**, que e ~15% da conta. E
alavanca de qualidade, nao de custo — subir effort nao aparece na fatura, e
baixar nao economiza.

### Os subagentes moram fora do repo

`~/.claude/agents/orch-planner.md` e `orch-reviewer.md`, instalados por
`bin/install-agents.sh`.

Nao e preferencia. Quem chama estes agentes e o **worker**, que roda no worktree
do cliente (`/Volumes/XPG_SSD/developer/workspaces/...`). O Claude Code so
enxerga `.claude/agents/` do projeto atual e de `~/.claude` — e escrever dentro
do repo do cliente esta proibido. Sobra o global.

Efeito colateral aceito: os dois aparecem em qualquer sessao sua, nao so nas do
orquestrador. Sao inertes ate serem chamados pelo nome, e o prefixo `orch-`
existe para isso ficar obvio na lista.

A fonte da verdade continua sendo `.claude/agents/orch-*.md` neste repo. Depois
de editar qualquer um:

```bash
./bin/install-agents.sh
```

Ele recusa instalar arquivo sem `model:` — sem esse campo o subagente herdaria
modelo e effort de quem o chamou, inclusive o teto rebaixado de um ticket
`Risk/low`, e a divisao de papeis viraria decoracao de novo, exatamente como
estava antes.

### O reviewer deixou de ser opcional

Com `gate: []` em todos os repos, o `orch-reviewer` e a **unica** verificacao
automatica entre o codigo e voce. Ele roda no passo 4b do `worker-workflow.md`,
antes do commit, com contexto limpo — e o contexto limpo e metade do valor: ele
le o diff sem a memoria de ter escrito aquilo. Fica sempre no `effortLevel`
global, nunca no teto rebaixado do ticket.

Limite de duas rodadas de reprovacao. Na terceira o worker abre o PR mesmo
assim, transcreve os bloqueantes abertos em `## Review automatico` e reporta
`failed` — PR honesto com o problema escrito vale mais que worker girando em
circulo.

O veredito vai sempre para o corpo do PR, inclusive quando aprovado sem
ressalva: a ausencia da secao significa "o review nao rodou", nunca "passou".

### O implementador sai do risco, nao e fixo

Todos implementam em Opus; o que o risco escolhe e o **teto de raciocinio**:
`Risk/high` em `xhigh`, `medium` em `high`, `low` em `medium`. Quem resolve e
`bin/implementer-model.sh`, que devolve os dois flags de uma vez:

```bash
$(bin/implementer-model.sh <IDENT> --flags)     # --model opus --effort high
```

**Sem aspas, de proposito.** Sao dois pares de argumentos, e aspas entregariam
uma palavra so. O efeito colateral e bom: saida vazia deixa de ser catastrofe —
o worker so herda os padroes, que sao o extremo caro.

Ordem de resolucao, e cada degrau existe porque o anterior pode faltar:

| # | Fonte | Quando entra |
|---|---|---|
| 1 | etiqueta `Risk/` do ticket | caso normal; a triagem poe e voce ajusta |
| 2 | `risk_default` do repo | ticket que a triagem nao marcou |
| 3 | `implementer_fallback` do registry | falta dado — e Opus **de proposito** |

O degrau 3 e o mais caro por escolha: se a informacao sumiu, o erro aceitavel e
gastar demais, nunca entregar de menos. E o script **nunca** imprime vazio —
vazio dentro de `$(...)` viraria `--model` sem valor e derrubaria o despacho
inteiro por causa de uma etiqueta faltando.

O motivo vai para o stderr (`ACME-139 -> opus (etiqueta Risk/high)`), o que
deixa voce ver um `Risk/` errado antes de o worker terminar.

**Isto e script e nao tabela na skill de proposito.** Regra que depende de o
agente da vez lembrar de aplicar e regra que um dia nao e aplicada — e o sintoma
seria um ticket de risco alto rodando com o teto rebaixado, sem erro nenhum.

### Por que o risco e o criterio certo

Medido em 140 sessoes de worker:

```
mediana    86 turnos    11 edicoes    57 tool calls
p90       234 turnos
p99       780 turnos   126 edicoes   395 tool calls

>200 turnos:  13,6% das sessoes  =  79% do custo de leitura
```

Isso nao e geracao de codigo, e loop agentico longo — e loop longo e onde a
diferenca de capacidade aparece: nao como linha errada, mas como perder o fio
no turno 200. Uma minoria de sessoes carrega quase todo o risco e quase todo o
custo, entao e nela que o modelo caro se paga.

### O que o sanduiche NAO cobre

Plano forte e review forte reduzem muito a superficie de erro, mas tres coisas
atravessam os dois:

- **Codigo correto porem pior.** O reviewer le o diff, nao o diff que nao foi
  escrito. Duplicar um helper em vez de achar o que ja existe passa no review —
  e o proprio `worker-workflow.md` avisa: *codigo duplicado passa no review e
  apodrece*.
- **Deriva no loop longo.** O review julga o resultado, nao os 300 turnos
  desperdicados chegando nele. Worker que trava nao vira PR ruim, vira leva
  perdida.
- **Nao perceber que o plano esta errado.** Modelo mais capaz questionaria no
  meio do caminho; o menos capaz tende a seguir ate a parede. Por isso o
  `orch-reviewer` julga o codigo contra o **ticket**, e trata o `PLAN.md` como
  evidencia e nao como gabarito: desvio com resultado correto e ressalva, nao
  falha.

### Onde a conta ficou

Medido em 30 dias, com 68% dos tickets em `Risk/high`:

```
painel em Opus          $1.410    igual a antes
planejar em Opus        $  869    igual a antes
implementar tudo Opus  ~$2.780    era $2.265 com Sonnet em medium/low
review em Opus          $260 a $520   novo

total  $5.319 a $5.579   vs $5.093 antes   =  +4% a +10%
```

O `~$2.780` e estimativa, nao medicao: o desconto de effort so alcanca os 15%
de saida de um terco dos tickets, entao vale algumas dezenas de dolares. Vai
ficar medido depois de alguns dias rodando.

**Isto custa mais do que antes, e de proposito.** O que se compra nao e
economia: e um reviewer que antes nao existia, planejamento isolado em subagente
(o que ele le nao volta a ser cobrado 60x na implementacao) e teto de raciocinio
proporcional ao risco. A versao com Sonnet em `medium`/`low` custava ~$500/mes
menos e foi abandonada por qualidade uniforme, nao por nao funcionar.

Se quiser que caia de verdade, o lever nao e modelo — e a etiqueta `Risk/`.
`high` em dois tercos dos tickets sugere que ela virou default em vez de
julgamento. Reclassificar metade para `medium` desloca ~$500/mes sem tocar em
nada aqui.

### Por que nao Fable

Ficou em Fable por algumas horas em 02/09 e voltou. No preco por token a conta
fechava (o cache read do Fable e $0,25/MTok contra $0,50 do Opus, e as leituras
dominam). Mas quem paga a conta aqui e a **cota do plano**, nao o preco por
token — e a cota nao segue o preco. O consumo subiu rapido demais no plano 5x.

Fica registrado porque a analise estava certa e a conclusao estava errada:
projecao de preco nao substitui observar o consumo real por alguns dias.

### Se precisar reverter

Tres lugares, independentes: tire o `"model"` do `.claude/settings.json`, tire
o `$(... --flags)` dos cinco `worker-start` (tres em `pull-ready` — incluindo o
da secao de armadilhas — e dois em `adjust`), e apague
`~/.claude/agents/orch-*.md`. Nada disso tem estado persistido — a proxima
rodada ja pega o padrao.

Para mudar so o roteamento sem desmontar nada, mexa em `implementer_by_risk` no
`registry.yaml`. Cada nivel aceita modelo e effort:

```yaml
    medium: { model: sonnet, effort: high }   # devolve os ~$500/mes
    low:    { model: opus,   effort: low }    # so abaixa o teto
```

O script le o registry a cada despacho, entao a mudanca vale na rodada seguinte
sem reinstalar nada.

## O que continua sendo seu

Escrever a ideia, aprovar a especificacao, revisar o PR, rodar a verificacao
manual e mergear. O merge libera a proxima onda sozinho.
