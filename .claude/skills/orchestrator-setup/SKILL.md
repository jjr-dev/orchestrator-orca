---
name: orchestrator-setup
description: |
  Instala o orquestrador do zero numa maquina nova: confere pre-requisitos, cria
  o registry a partir do template, configura o Linear, registra os repos no Orca,
  instala os subagentes, cria os cronjobs (automations) e fecha com o checklist
  do que so o humano consegue fazer no app. Idempotente: rodar de novo completa
  so o que falta.
  Use sempre que aparecer "/orchestrator-setup", "instalar o orquestrador",
  "configurar do zero", "acabei de clonar", "maquina nova", ou quando o
  /orchestrator-doctor acusar que falta parte da instalacao.
---

# Instalacao

Voce e o instalador. Nao delegue ao humano o que consegue descobrir sozinho, e
nao decida por ele o que muda o comportamento do sistema.

**Idempotente do inicio ao fim.** Nunca presuma instalacao limpa: diagnostique
primeiro, e faca so o que falta. Rodar duas vezes tem que ser seguro.

## Passo 0 — Diagnostico, sempre

```bash
./bin/doctor.sh
```

Ele diz o que ja existe e o que falta. Um `doctor` que sai sem falha significa
que nao ha nada a instalar — diga isso e pare.

## Passo 1 — Pre-requisitos

`orca`, `jq`, `python3` com `pyyaml`, `git`, e `gh` para o worker abrir PR. O
doctor ja confere. Se faltar algum, **entregue o comando de instalacao ao humano
com `!`** em vez de instalar por conta propria — mexer no ambiente da maquina
esta fora do seu escopo.

## Passo 2 — O registry

```bash
[ -f registry.yaml ] || cp registry.example.yaml registry.yaml
```

O template ja vem com uma empresa ficticia (`acme`) e dois repos de exemplo.
**Eles saem no fim**, quando os repos de verdade entrarem — nao antes, para o
arquivo nunca ficar sem exemplo de forma.

Levante com o humano, e so isto:

- quantas empresas, e o nome de cada uma
- quais repositorios, e onde estao no disco
- se o Linear tem um time so ou varios

## Passo 3 — Linear

Chame `/orchestrator-linear`. **Nao reimplemente**: token, estados e etiquetas
tem uma implementacao so, e ela mora la.

Ela cuida do token sem nunca toca-lo, cria os 9 estados com o `type` e a
`position` certos, e cria os grupos `Repo`, `Risk`, `Stack` mais a `Fast Track`
plana.

## Passo 4 — Repos

Para cada repositorio, chame `/orchestrator-repo-add`. Ela registra no Orca,
cria a etiqueta `Repo/` e escreve no registry, nessa ordem.

Descubra o que der para descobrir — base branch, lockfile — e **pergunte a base
sempre que o repo tiver `main` e `develop`**. Errar ali faz todo worker daquele
repo partir de codigo velho, sem nada acusar.

## Passo 5 — Subagentes

```bash
./bin/install-agents.sh
```

Copia `.claude/agents/orch-*.md` para `~/.claude/agents/`. **Nao e opcional.**
Quem chama esses subagentes e o worker, e o worker roda no worktree do cliente,
que nao pode receber arquivo nosso — `~/.claude/agents/` e o unico lugar
alcancavel.

O script recusa instalar arquivo sem `model:`. Sem esse campo o subagente
herdaria modelo e effort de quem o chamou, inclusive o teto rebaixado de um
ticket de risco baixo, e a divisao de papeis viraria decoracao.

## Passo 6 — Teste na mao, antes de qualquer automacao

Nesta ordem, e **so siga se cada uma passar**:

1. `./bin/has-ready.sh <TEAM>` — deve sair 1 com a fila vazia
2. `/reconcile` com tudo limpo — deve dizer "tudo consistente"
3. um ticket real com `/pull-ready <empresa>`, acompanhando na tela

Ligar cron antes de o caminho manual funcionar transforma um bug de configuracao
em um bug intermitente que dispara a cada 2 minutos.

## Passo 7 — Cronjobs

⚠️ **Leia o `--help` antes de agir. Sempre.**

```bash
orca automations create --help
```

Os flags do Orca mudam entre versoes, e ja mudaram duas vezes: `--cron` virou
`--trigger`, `--agent` virou `--provider`, e `--reuse-session` saiu (hoje ha
`--workspace-mode existing|new-per-run`). O `automations/setup-automations.sh`
esta congelado na versao em que foi escrito. **O `--help` manda, nao o script e
nao esta skill.**

Tres automations:

| Nome | Cadencia | Precheck | Prompt |
|---|---|---|---|
| `pull-all` | `*/2 * * * *` | `bin/has-ready.sh <TEAM>` | `/pull-ready` |
| `triage-all` | `1-59/2 * * * *` | `bin/has-triage.sh <TEAM>` | `/triage-tickets` |
| `morning-reset` | `0 8 * * 1-5` | — | `/reconcile` |

🔴 **O escalonamento par/impar nao e estetico.** `*/2` sao os minutos pares e
`1-59/2` os impares. As duas primeiras compartilham a mesma sessao no mesmo
workspace: disparo simultaneo faz as duas competirem por ela. Nao troque por
`*/5` — metade dos multiplos de 5 e par e colidiria.

O precheck e o que impede acordar o modelo a toa: ele sai 0 quando ha trabalho e
diferente de 0 quando nao ha, e so no primeiro caso o agente sobe.

Confira que subiram e que a proxima execucao esta no futuro:

```bash
orca automations list
```

## Passo 8 — O checklist humano

Isto **voce nao consegue fazer**, e sem isto o sistema fica mudo. Entregue como
lista e peca confirmacao item a item:

- [ ] ligar o **auto mode** em `Settings → Agents` (o badge tem que aparecer)
- [ ] deixar o Orca como item de inicializacao
- [ ] impedir a maquina de dormir na janela de trabalho
- [ ] no Linear, desligar *PR aberto → In Progress* e *review → In Review*, que
      brigam com o worker movendo o mesmo ticket. **Manter** *PR merged → Done*
- [ ] reiniciar o Orca, se o token do Linear foi criado depois de ele abrir

O ultimo item pega gente todo dia: o Orca e app de GUI e herda o ambiente do
launchd de quando abriu. Chave criada depois nao chega nele.

## Passo 9 — Feche verificando

```bash
./bin/doctor.sh
```

**Nao declare a instalacao pronta com FALHA aberta.** Se sobrou alguma, diga
qual e o que falta — instalacao "quase pronta" que ninguem terminou e como este
sistema falha em silencio.

## O kill switch

Diga onde fica, porque e a primeira coisa que se procura quando algo dispara
errado:

```bash
touch PAUSE   # na raiz: para tudo, sem desabilitar automation
rm PAUSE      # volta
```
