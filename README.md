# Orquestrador multi-projeto — Claude Code + Orca + Linear

Um painel que lê tickets do Linear, despacha agentes autônomos do Claude Code em
worktrees isolados de vários repositórios, e devolve pull requests. Você escreve
a ideia no celular; o PR aparece.

Este repositório é só o **painel de controle**: ele coordena o trabalho, mas o
código dos seus projetos continua nos repositórios deles. Nada é clonado para
cá, e o merge nunca é automático — essa decisão continua sua.

```
registry.yaml          SUA configuração (ignorada pelo git)
registry.example.yaml  o template versionado, comentado campo a campo
CLAUDE.md              as regras que o coordenador segue
bin/                   diagnóstico, edição do registry, prechecks dos cronjobs
.claude/skills/        as operacionais e as seis de configuração
.claude/agents/        subagentes de planejamento e review
automations/           criação dos cronjobs do Orca
docs/                  armadilhas conhecidas
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

Os cronjobs rodam a triagem e o despacho a cada 2 minutos, mas só acordam o
agente quando ha trabalho: um precheck barato decide antes.

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

## Passo 2 — Duas decisoes antes de instalar

**Um workspace, um time no Linear.** Não crie um time por projeto. No Linear os
estados de workflow são por time: com três times você definiria os nove estados
três vezes, com grafia idêntica, e os scripts comparam string literal. Um acento
fora do lugar deixa aquele time silenciosamente morto. A separação por projeto e
feita pela etiqueta `Repo/`.

**Quais repositórios entram, e de qual branch saem as features.** Tenha a lista
com o caminho local de cada um. Se algum repo tem `main` e `develop`, saiba qual
e — errar faz todo worker daquele repo partir de código velho, e nada acusa.

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
verifica. Rodar de novo só completa o que faltou — nunca refaz o que existe.

| Etapa | O que acontece |
|---|---|
| diagnóstico | `bin/doctor.sh` diz o que já existe é o que falta |
| registry | copia `registry.example.yaml` para `registry.yaml` se ainda não houver |
| Linear | chama `/orchestrator-linear`: token, 9 estados, grupos de etiqueta |
| repos | chama `/orchestrator-repo-add` para cada um: Orca + etiqueta + registry |
| subagentes | `bin/install-agents.sh` copia para `~/.claude/agents/` |
| teste manual | roda os prechecks e um despacho de verdade, antes de qualquer cron |
| cronjobs | lê `orca automations create --help` e cria as três automations |
| checklist | lista o que só você consegue fazer no app |

### O token do Linear

**A skill nunca pede seu token é nunca o grava.** Quando falta, ela te entrega
um comando para você mesmo rodar — o `!` no início executa na sua sessão:

```
! umask 077 && printf 'export LINEAR_API_KEY="COLE_AQUI"\n' >> ~/.zshenv && chmod 600 ~/.zshenv
```

O token sai de *Linear → Settings → Security & access → Personal API keys*.

Três detalhes que já custaram tempo:

- **`~/.zshenv`, não `.zshrc`.** O `.zshrc` só é lido por shell interativo, e os
  prechecks do cron rodam em shell não interativo.
- **Reinicie o Orca depois de criar a chave.** Ele é app de GUI e herda o
  ambiente do launchd de quando abriu; chave criada depois não chega nele.
- **Se você colar o token no chat, ele vazou** para o transcript. Revogue e gere
  outro.

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
2. `/reconcile` com tudo limpo — deve dizer "tudo consistente"
3. um ticket real com `/pull-ready <empresa>`, acompanhando na tela
   (com o argumento, para não puxar todas as empresas no primeiro teste)
4. **só então** deixe os cronjobs rodarem
5. teste de propósito: reinicie o Orca no meio de um ticket e rode `/reconcile`.
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

# Configuração no dia a dia

| Preciso... | Comando |
|---|---|
| acrescentar um repositório | `/orchestrator-repo-add` |
| ver ou trocar modelo e effort | `/orchestrator-models` |
| criar estado ou etiqueta que falta | `/orchestrator-linear` |
| descobrir por que um ticket não anda | `/orchestrator-sync` |
| conferir se está tudo ligado | `/orchestrator-doctor` |

## Acrescentar um repositório

```
/orchestrator-repo-add
```

Três sistemas precisam concordar — Orca (sabe clonar), Linear (tem a etiqueta) e
registry (liga os dois). Se um ficar de fora, o ticket some sem erro. A skill
descobre sozinha a base branch e o gerenciador de pacotes, e **pergunta** quando
o repo tem `main` e `develop`.

🔴 O nome da etiqueta é a chave do registry precisam ser idênticos byte a byte.
Divergir num espaço deixa todo ticket daquele repo invisível.

## Ajustar modelo e effort

```
/orchestrator-models
```

Mostra qual modelo e qual `effort` cada etapa está usando de verdade, e aplica a
mudança no registry. Se preferir, edite `defaults.models` à mão — as duas formas
são equivalentes, e cada linha do bloco tem um comentário dizendo onde aquele
valor é aplicado.

## Quando as três pontas divergirem

```
/orchestrator-sync
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
| nenhum ticket é despachado | etiqueta `Repo/` faltando ou com nome divergente | `/orchestrator-sync` |
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
problema só aparece no conflito de merge. Por isso o `/pull-ready` recusa
despachar repo cuja `base` não comece com `origin/`, e o `doctor` checa.

## O código sai sem comentário explicativo

Se uma linha precisa de comentário para ser entendida, o worker melhora o nome
ou extrai a função. Continuam permitidos docblock onde o repo já usa, e o fato
que não cabe no código — contorno de bug de terceiro, quirk de API, exigência
legal.

O "porquê" de cada decisão vai para o `PLAN.md` e para o corpo do PR, que é onde
alguém procura depois. Em comentário de código ele apodreceria.

## Worktrees de ticket se limpam sozinhos

O `/reconcile` diário roda a limpeza e remove worktree que fechou o ciclo. Ele
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

Gate não é modelo, então não passa pelo `/orchestrator-models`. Edite
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
/ajustar <IDENT> <o que voce quer>
```

O painel lê a árvore, lê o código para descobrir quais repos o pedido toca,
escreve a nova leva nos filhos certos e despacha — sem passar por
`Ready for Agent`. O pedido no chat **é** a aprovação humana, e por isso só o
`/ajustar` pode despachar direto: nenhuma automation ganha esse direito.

## Modelos por etapa

Cada papel — orquestrar, planejar, implementar, revisar — tem um modelo próprio,
e o implementador ainda varia por nível de risco do ticket. Tudo isso vive em
`defaults.models` no `registry.yaml`, com um comentário por linha explicando
onde cada valor é aplicado.

Para ver o que está valendo e mudar:

```
/orchestrator-models
```

Ou edite o registry direto — as duas formas são equivalentes.

---

# O que continua sendo seu

Escrever a ideia, aprovar a especificação, revisar o PR, rodar a verificação
manual e fazer o merge. **O merge nunca é automático**, e é ele que libera a
próxima onda.

# Licença

MIT. Veja [LICENSE](LICENSE).
