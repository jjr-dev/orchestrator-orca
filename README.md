# Orquestrador multi-projeto — Claude Code + Orca

Um painel que despacha agentes autônomos do Claude Code em worktrees isolados de
vários repositórios e devolve pull requests. Você escreve a ideia no celular ou
no chat; o PR aparece.

Onde o trabalho fica registrado é **escolha sua**, feita na instalação e
reversível depois:

- **`linear`** — ticket, board, etiquetas e cronjobs vigiando as colunas. Exige
  um token do Linear.
- **`orca`** — o próprio Orca guarda a spec, o pai/filho e o status. Sem token,
  sem serviço externo, tudo pelo chat.

O resto do sistema não muda. As mesmas skills, os mesmos comandos, o mesmo
worker.

Este repositório é só o **painel de controle**: ele coordena o trabalho, mas o
código dos seus projetos continua nos repositórios deles. Nada é clonado para
cá, e o merge nunca é automático — essa decisão continua sua.

```
registry.yaml          SUA configuração (ignorada pelo git)
registry.example.yaml  o template versionado, comentado campo a campo
.env                   suas chaves (ignorado pelo git)
.env.example           o template das chaves, versionado e sem valor real
CLAUDE.md              as regras que o coordenador segue
bin/                   diagnóstico, edição do registry, prechecks dos cronjobs
bin/board.sh           a porta única para registrar trabalho (resolve o backend)
.claude/skills/        as operacionais e as seis de configuração
.claude/agents/        subagentes de planejamento e review
automations/           criação dos cronjobs do Orca
docs/                  armadilhas conhecidas
```

## Como funciona, em uma passada

Há duas portas de entrada. Pelo **Linear**, que é o caminho assíncrono:

```
voce escreve a ideia no Linear (estado Draft)
        v
/orc-triage    le o repo de verdade e reescreve o ticket em formato executavel
        v
voce aprova    arrastando para "Ready for Agent" — este e o unico Start
        v
/orc-dispatch  resolve o repo pela etiqueta Repo/, cria o worktree, despacha
        v
worker         planeja (subagente), implementa, revisa (subagente), abre o PR
        v
voce revisa e faz o merge              <- o merge nunca e automatico
```

Os cronjobs rodam a triagem e o despacho a cada 2 minutos, mas só acordam o
agente quando há trabalho: um precheck barato decide antes.

Ou pelo **chat**, quando você já sabe o que quer e não precisa da fila:

```
/orc-task "<pedido>" --repo "Acme - API" --repo "Acme - Web"
        v
cria o ticket no Linear (pai + um filho por repo), aplica Repo/, Risk/ e Stack/
        v
redige a spec lendo o codigo, e MOSTRA no chat            <- para aqui
        v
voce le, pede ajuste na conversa, e diz "pode executar"
        v
worker         (identico ao caminho de cima)
```

O ticket é criado de qualquer jeito — o Linear continua sendo o histórico de
execução. O que muda é que **a conversa substitui o board**: você lê a spec e
aprova no chat, sem abrir o Linear.

Enquanto espera, os tickets ficam em `Drafted`. Nenhum cronjob olha esse estado,
então eles aguardam o tempo que você precisar sem ninguém despachar por engano.
Se a conversa morrer, a próxima retoma de onde parou.

Ajustes são pedidos na mesma conversa, quantas voltas forem necessárias. O
portão só abre com um "pode executar".

Com `--fast` ele pula a redação **e o portão**: vai direto para execução, como um
`Fast Track`. Use para o que é obviamente pequeno, onde não há spec para ler.

---

# Instalação

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

## Passo 2 — Três decisões antes de instalar

**Onde o trabalho vai ficar registrado: `linear` ou `orca`.** É a primeira
pergunta do `/orc-setup`. A tabela em [Escolher o backend](#escolher-o-backend)
compara as duas. Em resumo: escolha `linear` se quer board visual, anexo de
imagem no ticket e a fila de triagem automática; escolha `orca` se quer começar
sem configurar serviço nenhum e trabalhar pelo chat.

Dá para trocar depois, mas a troca **não migra nada**, então decidir agora
poupa retrabalho.

As duas decisões abaixo só valem se você escolheu `linear`.

**Um workspace, um time no Linear.** Não crie um time por projeto. No Linear os
estados de workflow são por time: com três times você definiria os nove estados
três vezes, com grafia idêntica, e os scripts comparam string literal. Um acento
fora do lugar deixa aquele time silenciosamente morto. A separação por projeto e
feita pela etiqueta `Repo/`.

**Quais repositórios entram, e de qual branch saem as features.** Tenha a lista
com o caminho local de cada um. Se algum repo tem `main` e `develop`, saiba qual
é — errar faz todo worker daquele repo partir de código velho, e nada acusa.

## Passo 3 — Clonar e abrir

```bash
git clone <este-repo> orchestrator
cd orchestrator
claude
```

## Passo 4 — `/orc-setup`

```
/orc-setup
```

Ela diagnostica, mostra **um** plano, pede **uma** confirmacao, executa e
verifica. Rodar de novo só completa o que faltou — nunca refaz o que existe.

| Etapa | O que acontece |
|---|---|
| diagnóstico | `bin/doctor.sh` diz o que já existe e o que falta |
| registry | copia `registry.example.yaml` para `registry.yaml` se ainda não houver |
| **backend** | **pergunta `linear` ou `orca` e grava em `defaults.backend`** |
| **`.env`** | **copia `.env.example` para `.env` se não houver, e pede para você preencher** |
| Linear | só no backend `linear`: chama `/orc-linear` para token, 9 estados e grupos de etiqueta |
| repos | chama `/orc-repo-add` para cada um: Orca + etiqueta + registry |
| subagentes | `bin/install-agents.sh` copia para `~/.claude/agents/` |
| teste manual | roda os prechecks e um despacho de verdade, antes de qualquer cron |
| cronjobs | lê `orca automations create --help` e cria as três automations |
| checklist | lista o que só você consegue fazer no app |

### O arquivo `.env` e o token do Linear

Toda configuração que não cabe no `registry.yaml` mora num `.env`. O template
versionado é o `.env.example`; o `.env` em si é ignorado pelo git.

```bash
cp .env.example .env
```

O `/orc-setup` faz essa cópia sozinho quando o arquivo não existe. **Ele cria;
quem preenche é você.**

```
LINEAR_API_KEY=      # obrigatório só no backend `linear`
ORCH_ASSETS_ROOT=    # opcional: onde os anexos baixados ficam
ORCH_ROOT=           # opcional: para rodar as skills de outro diretório
```

O token sai de *Linear → Settings → Security & access → Personal API keys*.
No backend `orca`, deixe a linha vazia: nada lê essa variável lá.

**Nenhuma skill pede, lê ou grava o seu token.** Se ele faltar, elas mandam você
preencher o arquivo e param. Para saber se está configurado sem imprimir nada,
use `./bin/doctor.sh`.

Três detalhes que já custaram tempo:

- **Arquivo, não variável de ambiente.** Até 12/09 o caminho era gravar em
  `~/.zshenv` ou usar `launchctl setenv`. Os dois falham igual: os prechecks do
  cron rodam como filhos do app do Orca, que só herda o ambiente existente
  quando o app subiu, e `launchctl setenv` não sobrevive a reboot. O sintoma era
  o precheck sair 4 e a automation nunca disparar, em silêncio.
- **O `~/.zshenv` continua funcionando**, lido em último lugar, para não quebrar
  instalações antigas. A ordem é ambiente, depois `.env`, depois `~/.zshenv`.
- **Se você colar o token no chat, ele vazou** para o transcript. Revogue e gere
  outro.

## O que isso cria no seu Linear

O setup **escreve no seu workspace**. Nada é destrutivo e nada é apagado, mas
vale saber exatamente o que aparece antes de confirmar.

### Estados do workflow

Nove estados, criados no time que você escolher. Os que já existirem são
reaproveitados — nada é renomeado.

```
Draft -> Drafting -> Drafted -> Ready for Agent -> Scheduled
  -> In Progress -> In Review -> Manual QA -> Done
```

| Estado | `type` | Quem move |
|---|---|---|
| `Draft` | backlog | você — é onde a ideia entra |
| `Drafting` | backlog | a triagem, ao pegar o ticket |
| `Drafted` | backlog | a triagem, ao terminar |
| `Ready for Agent` | unstarted | **você — este é o Start** |
| `Scheduled` | started | o coordenador, ao despachar |
| `In Progress` | started | o worker |
| `In Review` | started | o worker, ao abrir o PR |
| `Manual QA` | started | o coordenador |
| `Done` | completed | **você**, depois do merge |

Os estados nativos do Linear (`Backlog`, `Todo`, `Canceled`, `Duplicate`)
continuam intactos e podem seguir em uso.

⚠️ **Nunca renomeie um desses estados depois.** Os prechecks casam por nome
exato — renomear pela interface mata o disparo do cron **em silêncio**, sem erro
em lugar nenhum.

### Etiquetas

Todas derivam do `registry.yaml`, e são criadas por um comando só:

```bash
./bin/sync-labels.sh            # mostra o que falta
./bin/sync-labels.sh --apply    # cria
```

| Grupo | Vem de | Exemplo |
|---|---|---|
| `Repo/` | uma por repo em `companies.*.repos` | `Repo/Acme - API` |
| `Stack/` | uma por chave em `stacks` | `Stack/Acme - API/Web` |
| `Risk/` | fixo: `high`, `medium`, `low` | `Risk/high` |
| `Fast Track` | fixo, **sem grupo** | — |

Grupos no Linear são exclusivos: um ticket tem no máximo um `Repo/`, um `Risk/`
e um `Stack/`. `Fast Track` é plana porque `Status` é nome reservado no Linear —
um grupo com esse nome é recusado pela API.

🔴 **O nome da etiqueta e a chave do registry precisam ser idênticos**, byte a
byte. É a chave da resolução inteira: divergir num espaço deixa todo ticket
daquele repo invisível para o coordenador, sem erro nenhum. É por isso que quem
cria é o script, e não você na interface.

### O que ele nunca faz

- **Não apaga etiqueta.** Uma etiqueta órfã — existe no Linear e não no registry
  — sai no relatório para você decidir. Apagar levaria junto o vínculo com os
  tickets que a usam, sem volta.
- **Não renomeia estado.** Se faltar um, ele cria; se houver um parecido com
  outro nome, ele reporta e deixa a migração com você.
- **Não mexe em ticket.** Só em estados e etiquetas.

Rodar de novo é seguro: ele compara e cria só o que falta.

## Passo 5 — O que só você consegue fazer

O setup termina aqui, e **sem estes itens o sistema fica mudo**:

- [ ] ligar o **auto mode** em `Settings → Agents` do Orca (o badge tem que aparecer)
- [ ] deixar o Orca como item de inicializacao
- [ ] impedir a máquina de dormir na janela de trabalho
- [ ] no Linear, desligar as automations nativas *PR aberto → In Progress* e
      *review → In Review*, que brigam com o worker movendo o mesmo ticket.
      **Manter** *PR merged → Done*

## Passo 6 — Testar antes de confiar

Nesta ordem, e só siga se cada uma passar:

1. `./bin/has-ready.sh <TEAM>` — deve sair 1 com a fila vazia
2. `/orc-reconcile` com tudo limpo — deve dizer "tudo consistente"
3. um ticket real com `/orc-dispatch <empresa>`, acompanhando na tela
   (com o argumento, para não puxar todas as empresas no primeiro teste)
4. **só então** deixe os cronjobs rodarem
5. teste de propósito: reinicie o Orca no meio de um ticket e rode `/orc-reconcile`.
   O ticket tem que voltar para `Ready for Agent` com comentário.

Ligar cron antes de o caminho manual funcionar transforma um erro de
configuração num bug intermitente que dispara a cada 2 minutos.

## Passo 7 — Confirmar que está tudo ligado

```bash
./bin/doctor.sh
```

Sai `0` se tudo passou, `1` se ha falha, `2` se ha só avisos. **Não considere a
instalação pronta com FALHA aberta.**

---

# Escolher o backend

Onde o orquestrador registra o trabalho. Mora em `defaults.backend`, no
`registry.yaml`, e vale para o sistema inteiro: skills, prechecks dos cronjobs e
diagnóstico leem essa mesma chave.

```bash
./bin/backend.sh --explica     # qual está ativo, e o que isso implica
```

## As duas opções, lado a lado

| | `linear` | `orca` |
|---|---|---|
| onde mora a spec | ticket do Linear | task do Orca |
| `Repo/`, `Risk/`, `Stack/` | etiquetas de verdade | bloco no topo da spec |
| estados | os 9 do workflow | 5 (`pending` `ready` `blocked` `dispatched` `completed`) |
| aprovação pelo chat | ticket parado em `Drafted` | rascunho em `state/drafts/` |
| triagem automática a cada 2 min | sim | **não** — não há coluna para largar pedido |
| execução automática a cada 2 min | sim | sim, via `task-list --ready` |
| board visual | sim | `orca orchestration task-list` |
| imagem no ticket | baixa do Linear e entrega ao agente | caminho local passado no chat |
| comentário por ticket | sim | não — plano fica no `PLAN.md`, veredito no PR |
| token / serviço externo | **exige** | não exige |
| histórico | no servidor do Linear | local, nesta máquina |

**Escolha `linear` se** você quer o quadro visual, quer largar pedido numa
coluna e ter o agente redigindo sozinho em dois minutos, ou precisa que outra
pessoa veja o andamento sem acesso à sua máquina.

**Escolha `orca` se** você quer começar sem configurar serviço nenhum, trabalha
sozinho, e o chat já é onde você pede as coisas.

## Trocar depois

```
/orc-backend
```

A skill mostra o estado atual, explica o que muda e conduz a troca. Por baixo
ela chama a porta única de escrita do registry, que prova que só
`defaults.backend` mudou:

```bash
./bin/registry-edit.py set-backend orca      # ou linear
```

Não edite o YAML à mão para isso. O valor é lido por scripts que rodam sem
sessão nenhuma aberta, e um erro de digitação para a fila em silêncio.

## 🔴 A troca não migra nada

O que já existe fica onde nasceu. Ticket no Linear continua no Linear; task no
Orca continua no Orca. Não há importação, e inventar uma seria pior: duplicaria
o registro de execução sem nenhuma forma de saber qual dos dois é verdade.

**Termine o que está em andamento antes de trocar.** Worker no ar reporta para o
backend em que nasceu. Depois da troca ninguém olha mais para lá, então o
trabalho não se perde, mas some da sua vista.

Ao sair do Linear, o token **pode ficar onde está**. Nada mais o lê, e apagar é
irreversível por nenhum ganho.

## Depois de trocar

**Para `orca`:** rode `./bin/doctor.sh`, que passa a checar o Orca e pula as
verificações do Linear sozinho. Desabilite a automation de triagem: o precheck
já sai 1 e ela nunca acorda, mas deixá-la habilitada é configuração que mente.

**Para `linear`:** rode `/orc-linear` se o token nunca foi configurado nesta
máquina, depois `/orc-sync` para criar estados e etiquetas que faltem, e
`./bin/doctor.sh` para confirmar. Reabilite a automation de triagem.

## Como os prechecks sabem

Os cronjobs consultam um precheck barato antes de acordar qualquer agente, e
esse precheck resolve o backend sozinho — ele roda sem sessão aberta, então não
pode perguntar a ninguém.

```bash
./bin/has-ready.sh <TEAM>     # backend linear: consulta "Ready for Agent"
                              # backend orca:   consulta task-list --ready
```

Quando o registry está ausente, ilegível ou com valor desconhecido, eles saem
com **código 6**, nunca 1. A diferença importa: 1 significa "fila vazia" e 6
significa "não sei ler a configuração". Colapsar os dois esconderia um registry
quebrado como se fosse um dia sem trabalho.

---

# Os comandos

Todos começam com `/orc-`. A lista viva é `/orc-help`, que a lê do disco — se
você criar uma skill nova, ela aparece lá sozinha.

## Dia a dia

**`/orc-task "<pedido>" --repo "<Nome>"`**
Começa uma demanda nova pelo chat. Resolve o nome do repositório, redige a
especificação lendo o código, mostra tudo e **para**. Só despacha quando você
aprova. Aceita vários `--repo`, ou um `--stack`. Com `--fast` pula a redação e o
portão, para o que é obviamente pequeno.

**`/orc-triage`**
Lê o código de verdade e reescreve a descrição de um ticket em `Draft` no
formato executável: escopo, fora de escopo, arquivos afetados, critérios de
aceite e roteiro de verificação manual. No backend `linear` roda sozinha a cada
dois minutos; no `orca` é chamada pela `/orc-task`.

**`/orc-dispatch`**
Puxa o que está pronto para execução, confere capacidade, cria o worktree e sobe
o worker. É o que os cronjobs chamam.

**`/orc-adjust "<o que mudar>"`**
Pede ajuste no que já virou pull request, sem abrir ticket novo. Reaproveita a
mesma branch e o mesmo PR.

**`/orc-project`**
Monta o grafo de ondas de um projeto: o que pode sair junto, o que depende de
quê, e em que ordem despachar.

**`/orc-reconcile`**
Destrava item órfão e limpa worktree morto. Rode quando algo ficou parado sem
explicação.

## Configuração

**`/orc-setup`**
Instala do zero, ou completa o que falta. Diagnostica, mostra **um** plano, pede
**uma** confirmação, executa e verifica. Rodar de novo nunca refaz o que existe.

**`/orc-backend`**
Escolhe onde o trabalho é registrado: `linear` ou `orca`. Mostra o estado atual,
explica o que muda e conduz a troca. Veja
[Escolher o backend](#escolher-o-backend).

**`/orc-linear`**
Só no backend `linear`: configura o token, os nove estados do workflow e os
grupos de etiqueta. Nunca pede nem grava o seu token — ela te entrega o comando
para você mesmo rodar.

**`/orc-repo-add "<Nome do Repo>"`**
Acrescenta um repositório em todas as pontas de uma vez: registra no Orca, cria
a etiqueta correspondente e escreve no `registry.yaml`.

**`/orc-sync`**
Reconcilia as três pontas — registry, backend e Orca — e cria o que estiver
faltando. Nunca apaga nada.

**`/orc-models`**
Mostra e ajusta qual modelo e qual `effort` cada etapa usa. O roteamento é por
nível de risco do item.

**`/orc-doctor`**
Verifica se tudo está **realmente** ligado, não apenas configurado. Roda
quarenta e poucas checagens executáveis e adapta o que checa ao backend ativo.
É o comando a rodar quando algo parece errado e você não sabe por onde começar.

**`/orc-help`**
Esta referência, sempre atualizada, direto do disco.

## Sem passar por skill

```bash
./bin/doctor.sh                              diagnóstico completo
./bin/backend.sh --explica                   qual backend está ativo
./bin/board.sh list-drafts --team <TEAM>     o que espera sua aprovação
./bin/registry-edit.py show                  o registry, legível
./bin/resolve-name.sh --repo "<texto>"       nome aproximado para chave canônica
./bin/implementer-model.sh <IDENT> --flags   qual modelo aquele item usaria
./bin/cleanup-worktrees.sh                   worktrees que já podem sair
```

## O kill switch

```bash
touch PAUSE    # para tudo, sem desabilitar automation nenhuma
rm PAUSE       # volta
```

Os prechecks conferem esse arquivo antes de qualquer outra coisa, nos dois
backends.

---

# Configuração no dia a dia

| Preciso... | Comando |
|---|---|
| não lembro o comando | `/orc-help` |
| começar uma demanda nova | `/orc-task` |
| acrescentar um repositório | `/orc-repo-add` |
| ver ou trocar modelo e effort | `/orc-models` |
| criar estado ou etiqueta que falta | `/orc-linear` |
| descobrir por que um ticket não anda | `/orc-sync` |
| conferir se está tudo ligado | `/orc-doctor` |

## Acrescentar um repositório

```
/orc-repo-add
```

Três sistemas precisam concordar — Orca (sabe clonar), Linear (tem a etiqueta) e
registry (liga os dois). Se um ficar de fora, o ticket some sem erro. A skill
descobre sozinha a base branch e o gerenciador de pacotes, e **pergunta** quando
o repo tem `main` e `develop`.

🔴 O nome da etiqueta é a chave do registry precisam ser idênticos byte a byte.
Divergir num espaço deixa todo ticket daquele repo invisível.

## Ajustar modelo e effort

```
/orc-models
```

Mostra qual modelo e qual `effort` cada etapa está usando de verdade, e aplica a
mudança no registry. Se preferir, edite `defaults.models` à mão — as duas formas
são equivalentes, e cada linha do bloco tem um comentário dizendo onde aquele
valor é aplicado.

## Quando as três pontas divergirem

```
/orc-sync
```

A divergência típica nasce de uma edição pela interface do Linear: alguém
renomeia uma etiqueta e o registry fica com o nome velho. Nada quebra, nenhum
erro aparece, e os tickets daquele repo simplesmente param de ser roteados.

---

# Editar a mão

As skills são **conveniência sobre o `registry.yaml`, nunca substituto dele**.
Tudo o que elas fazem você faz editando o arquivo, e o inverso também: edite a
mão e a próxima skill respeita. Nenhuma skill guarda estado em outro lugar.

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
texto de forma cirúrgica em vez de reserializar o YAML — um round-trip por
`yaml.safe_load`/`yaml.dump` derrubaria o arquivo de 551 para 343 linhas e
apagaria todos os comentários, que são a auditoria. Ele mostra o diff, valida o
resultado, e **aborta se a edição tocar qualquer chave além da pretendida**.

```bash
./bin/registry-edit.py show                     # o estado atual, legivel
./bin/registry-edit.py --dry-run set-model ...  # o diff, sem gravar
./bin/test-registry-edit.sh                     # 19 testes contra fixture
```

`registry.yaml` está no `.gitignore`. O template versionado é o
`registry.example.yaml` — **nunca tire o registry de la**: ele tem nome de
cliente, id de repo e a topologia inteira da sua operação.

---

# Quando algo não funciona

| Sintoma | Causa provável | Onde olhar |
|---|---|---|
| nenhum ticket é despachado | etiqueta `Repo/` faltando ou com nome divergente | `/orc-sync` |
| o cron não dispara | estado renomeado no Linear, ou precheck sem `+x` | `./bin/doctor.sh` |
| `orca` diz que não está rodando | o app está fechado | abra o Orca |
| a chave existe mas o Orca não a vê | criada depois de o app abrir | reinicie o Orca |
| worker parte de código velho | `base` sem prefixo `origin/` | `grep 'base:' registry.yaml` |
| o worker não seguiu as regras | primeira linha do prompt com caminho errado | `.claude/worker-workflow.md` |
| o subagente rodou no modelo errado | fonte editada sem reinstalar | `./bin/install-agents.sh` |
| `worker-start` diz `selector_not_found` | `orca_repo_id` velho | `orca repo list --json` |

Comece sempre pelo `./bin/doctor.sh`. A falha característica deste sistema não
levanta erro — o hook já passou semanas registrado num arquivo que o worker
nunca leu, e 258 comandos de projeto passaram sem barreira.

Mais em [`docs/armadilhas.md`](docs/armadilhas.md).

---

# Como o sistema se comporta

Referência curta do que o orquestrador faz sozinho. Nada aqui é passo de
instalação.

## O kill switch

```bash
touch PAUSE   # na raiz: para tudo, sem desabilitar as automations
rm PAUSE      # volta
```

## O worker sempre parte do código atualizado

O Orca busca o remoto antes de criar o worktree, então você não precisa dar
`pull` antes de mandar um ticket. Isso depende do prefixo `origin/` no campo
`base`: com `origin/main` o Orca faz fetch e corta do tip remoto; com `main` ele
usa a ref local, que pode estar dias atrás.

Escrever `development` em vez de `origin/development` faz o worker implementar
sobre código velho **sem nada acusar** — o PR abre, passa no review, e o
problema só aparece no conflito de merge. Por isso o `/orc-dispatch` recusa
despachar repo cuja `base` não comece com `origin/`, e o `doctor` checa.

## O código sai sem comentário explicativo

Se uma linha precisa de comentário para ser entendida, o worker melhora o nome
ou extrai a função. Continuam permitidos docblock onde o repo já usa, e o fato
que não cabe no código — contorno de bug de terceiro, quirk de API, exigência
legal.

O "porquê" de cada decisão vai para o `PLAN.md` e para o corpo do PR, que é onde
alguém procura depois. Em comentário de código ele apodreceria.

## Worktrees de ticket se limpam sozinhos

O `/orc-reconcile` diário roda a limpeza e remove worktree que fechou o ciclo. Ele
só olha branch do padrão do orquestrador — worktree que você criou na mão nunca
entra — e só remove quem passa nas quatro condições:

| # | Condição |
|---|---|
| 1 | nada por commitar |
| 2 | nenhum commit local fora do remoto |
| 3 | PR daquela branch está `MERGED` |
| 4 | ticket em `Done` |

```bash
bin/cleanup-worktrees.sh            # so lista
bin/cleanup-worktrees.sh --apply    # remove
```

Ele limpa também as pastas de anexo, por uma regra mais frouxa: sai o que está
`Done` ou sumiu do Linear. Apagar anexo não perde nada — o arquivo veio do
Linear e é baixado de novo quando precisar.

## Gates: comandos que precisam passar antes do PR

Por padrão o worker **não executa nada** do seu projeto — nem lint, nem teste,
nem build. Ele entrega planejamento e código, e a verificação fica com você. É
por isso que todo repo nasce com `gate: []`.

O campo `gate` liga isso por repositório. Com comandos na lista, o worker roda
exatamente aqueles antes de commitar, e **não pode reportar sucesso se algum
falhar**.

```yaml
"Acme - API":
  gate:                      # roda automaticamente, antes do commit
    - npm run lint
    - npm run typecheck
  manual:                    # roteiro para VOCE; o agente so transcreve no PR
    - npm test
    - docker compose up
    - npm run test:e2e
```

O resultado vai para o corpo do PR:

```
### Gate
| Comando | Resultado |
|---|---|
| npm run lint | ok |
| npm run typecheck | FALHOU — 2 erros, ver abaixo |
```

Se um comando falhar e o worker não conseguir consertar, ele abre o PR com a
falha transcrita e reporta `failed`. Um PR honesto com o problema escrito vale
mais que um worker girando em círculo — mas ele não passa por concluído.

### O que colocar no `gate`, e o que deixar no `manual`

| Vai no `gate` | Fica no `manual` |
|---|---|
| barato e rápido (segundos) | demorado (minutos) |
| determinístico | intermitente |
| não precisa de serviço externo | precisa de banco, container, rede |
| lint, typecheck, build | e2e, integração, migration, servidor de dev |

O motivo de e2e ficar de fora não é ideologia: cada worker é uma sessão
completa, e suítes que sobem um processo por núcleo derrubam a máquina quando
há vários workers ao mesmo tempo.

### Regras que o worker segue

- **Só os comandos da lista.** Ele não acrescenta um `npm ci` porque faltou
  dependência, e não varia o comando porque "faria mais sentido".
- **Falhou por causa do código?** Ele conserta o que for trivial e roda de novo.
  O que exige decisão de desenho vira pendência no PR.
- **Falhou por ambiente** — binário ausente, dependência não instalada? Ele
  marca `não rodou` com o motivo e segue. Não instala nada.
- **Nunca reporta ok sem ter rodado.** Em repo sem CI, esse bloco é o único
  registro de que algo foi verificado.

A ausência da seção `### Gate` no PR significa "este repo não tem gate", nunca
"rodou e passou".

### Ligar num repo existente

Gate não é modelo, então não passa pelo `/orc-models`. Edite
`gate` no `registry.yaml` direto. Depois confira:

```bash
./bin/registry-edit.py show
./bin/doctor.sh          # lista quais repos tem gate ativo
```

## Imagens do ticket chegam ao agente

Screenshot de bug e mockup de tela funcionam — mas não pelo caminho óbvio.

`uploads.linear.app` **não é URL pública**: devolve 401 sem a chave da API.
Colar a URL no prompt não adianta, e nenhum `WebFetch` leria a imagem mesmo que
a URL abrisse. O único caminho é baixar autenticado e abrir o arquivo local.

```bash
bin/linear-assets.sh <IDENT>
```

Varre descrição, comentários e anexos do ticket, baixa tudo, e imprime o caminho
local ao lado da URL de origem. Sem anexo, diz `nenhum anexo` e sai limpo.

Três pontos do fluxo olham a imagem, e a ordem importa:

| Onde | O que faz |
|---|---|
| triagem | baixa e **olha** antes de escrever a especificação |
| despacho | detecta imagem na descrição e manda a linha de download no prompt |
| worker | baixa e abre antes de planejar; o planner também vê |

**A triagem é o elo frágil.** Ela reescreve a descrição inteira — se não repetir
a marcação da imagem, o anexo some do ticket antes de o despacho saber que
existiu.

Onde os arquivos ficam sai de `defaults.assets_root` no registry. Precisa ser
**fora de qualquer repositório git**, para o anexo nunca ser commitado por
acidente:

```yaml
defaults:
  assets_root: ~/.orch-assets
```

Aceita `~` e pode apontar para um volume externo — nesse caso os scripts checam
se está montado antes de gravar. Sem essa checagem, um volume desmontado viraria
um diretório comum e tudo pareceria funcionar.

## Sub-tasks: um ticket por repositório

Quando um pedido atravessa mais de um repositório, a triagem propõe quebrar em
**ticket pai + uma sub-issue por repo**, com o contrato de API entre eles escrito
no pai.

```
ACME-138  "Checkout recorrente"          <- pai: contrato, sem worker, sem PR
   ACME-139  Repo/Acme - API             <- filho: worker proprio, PR proprio
   ACME-140  Repo/Acme - Web             <- filho: worker proprio, PR proprio
```

Cada filho tem sua etiqueta `Repo/`, seu worktree, seu worker e seu PR. O pai
não tem nenhum — ele é derivado.

### 🔴 Você aprova cada filho, não o pai

Este é o ponto que confunde: mover o **pai** para `Ready for Agent` não despacha
nada. O despacho olha os filhos, e cada filho precisa estar em
`Ready for Agent` por conta própria.

```
ACME-138  Drafted            <- o pai fica aqui, e tudo bem
   ACME-139  Ready for Agent <- este vai ser despachado
   ACME-140  Drafted         <- este NAO vai
```

É deliberado: cada repositório é uma decisão separada, e às vezes você quer a
API antes do front. Se quiser os dois juntos, mova os dois.

### O pai se move sozinho, a partir dos filhos

| Filhos (ignorando `Draft`/`Drafting`/`Drafted`) | Pai vai para |
|---|---|
| todos em `Scheduled` ou adiante | `In Progress` |
| todos em `In Review` ou adiante | `In Review` |
| todos em `Done` | `Done` |

Filho em `Ready for Agent` **segura** o pai: ele é "aprovado e ainda não
arrancou", então a onda não entrou em progresso. Filho em `Drafted` não conta —
não foi aprovado.

O pai **só anda para frente**. Se você reabrir um filho e a conta der para trás,
o script reporta e não mexe: voltar estado desfaria uma decisão sua.

### Etiqueta `Stack/` evita repetir

Quando a mesma combinação de repos se repete, crie uma `Stack/`:

```yaml
stacks:
  "Acme - API/Web":
    - "Acme - API"
    - "Acme - Web"
```

Aí um toque na etiqueta, do celular, já diz "este ticket atravessa estes repos"
— sem escrever nada no corpo do ticket. Lembre que os filhos entram todos na
mesma onda e ocupam as vagas do `wip_max` da empresa.

## Push para branch protegida

Um hook global bloqueia push para `main`, `master`, `production`, `develop` e
afins, além de qualquer force-push. Pega as formas que uma regra de prefixo
deixaria passar (`HEAD:main`, `--all`, `git -C <path> push`, comando escondido
depois de `&&`).

**Só limita agente** — push que você der no seu terminal não passa por ali. Não
substitui branch protection no GitHub, que é server-side; cobre o caso de agente
rodando sozinho de madrugada.

## Nova leva no mesmo PR, em vez de ticket novo

Pedir ajuste em algo que já está em PR não cria ticket novo. O ciclo volta para
o mesmo ticket, o worker retoma no worktree que já existe, e o commit novo vai
para o **mesmo PR**:

```
ACME-140  In Review  PR #58
   voce comenta e move para Draft
ACME-140  Draft -> Drafting -> Drafted -> Ready for Agent
   worker retoma no worktree existente, mesmo PR #58
ACME-140  In Review
```

A triagem, nesse caso, **não reescreve a descrição** — acrescenta uma seção com
só o delta. Reescrever faria o worker reimplementar o que já está pronto.

## Pedir ajuste falando

```
/orc-adjust <IDENT> <o que voce quer>
```

O painel lê a árvore, lê o código para descobrir quais repos o pedido toca,
escreve a nova leva nos filhos certos e despacha — sem passar por
`Ready for Agent`. O pedido no chat **é** a aprovação humana, e por isso só o
`/orc-adjust` pode despachar direto: nenhuma automation ganha esse direito.

## Modelos por etapa

Cada papel — orquestrar, planejar, implementar, revisar — tem um modelo próprio,
e o implementador ainda varia por nível de risco do ticket. Tudo isso vive em
`defaults.models` no `registry.yaml`, com um comentário por linha explicando
onde cada valor é aplicado.

Para ver o que está valendo e mudar:

```
/orc-models
```

Ou edite o registry direto — as duas formas são equivalentes.

---

# O que continua sendo seu

Escrever a ideia, aprovar a especificação, revisar o PR, rodar a verificação
manual e fazer o merge. **O merge nunca é automático**, e é ele que libera a
próxima onda.

# Licença

MIT. Veja [LICENSE](LICENSE).
