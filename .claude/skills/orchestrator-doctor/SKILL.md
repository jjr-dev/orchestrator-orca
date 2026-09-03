---
name: orchestrator-doctor
description: |
  Verifica se a instalacao do orquestrador esta realmente ligada: binarios,
  registry, estados e etiquetas no Linear, subagentes instalados, resolver de
  modelo, hook de comandos e as automations. Somente leitura; propoe os
  consertos mas so aplica com o seu ok.
  Use sempre que aparecer "/orchestrator-doctor", "esta tudo ligado?", "o
  orquestrador esta funcionando?", depois de mexer em configuracao, depois de
  atualizar o Orca, ou quando algo parou de disparar sem erro aparente.
---

# Diagnostico da instalacao

## Por que esta skill existe

A falha caracteristica deste sistema **nao levanta erro**. Duas reais, ambas
descobertas por acaso, semanas depois:

- o `guard-commands.sh` estava registrado num `settings.json` que o worker nunca
  leu. 258 comandos de projeto passaram sem barreira, sem um unico aviso.
- o bloco `models` do registry era decoracao: nada lia aqueles valores. Sonnet
  era 0,07% dos tokens de saida.

Nos dois casos o sistema continuou entregando PRs. Por isso o diagnostico e
comando proprio, e nao um passo do setup: a pergunta "isto ainda esta ligado?"
se faz o tempo todo, nao uma vez.

## Rode

```bash
./bin/doctor.sh
```

Saida: `0` tudo ok, `1` ha falha, `2` so avisos.

**As checagens moram no script, nao aqui.** Se voce achar que falta uma,
acrescente la — regra que depende de o agente da vez lembrar de aplicar e regra
que um dia nao e aplicada.

## Como ler o resultado

`FALHA` e coisa quebrada agora. `aviso` e coisa que provavelmente esta certa mas
merece o seu olho.

Um aviso e **permanente e correto**: *"o hook NAO alcanca o worker"*. Nao tente
consertar. O `guard-commands.sh` roda pelo `settings.json` deste diretorio, e o
worker roda no worktree do cliente, onde esse arquivo nao existe. Para o worker
a politica de execucao zero e regra de prompt, e depende de ele cumprir. O
aviso existe para que ninguem volte a acreditar que ha barreira ali.

## Consertos que voce pode oferecer

Antes de aplicar qualquer um, diga o que vai fazer e espere o ok.

| Falha | Conserto |
|---|---|
| subagente nao instalado, ou difere da fonte | `./bin/install-agents.sh` |
| `registry.yaml` nao existe | `cp registry.example.yaml registry.yaml`, depois `/orchestrator-setup` |
| `registry.yaml` nao esta no `.gitignore` | acrescente a linha — publicar o repo publicaria a config |
| estado faltando no Linear | `/orchestrator-linear` |
| repo sem etiqueta `Repo/` | `/orchestrator-sync` |
| automation ausente ou desabilitada | `/orchestrator-setup` (secao de cronjobs) |
| `base` sem `origin/` | edite o `registry.yaml`; o `/pull-ready` ja recusa despachar assim |
| precheck sem permissao de execucao | `chmod +x bin/has-*.sh` |

**Nao conserte `base` sem perguntar qual e a branch certa.** Trocar
`development` por `origin/development` e obvio; escolher entre `main` e
`develop` num repo que tem as duas nao e, e errar faz o worker partir de codigo
velho sem nada acusar.
