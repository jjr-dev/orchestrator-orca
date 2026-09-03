---
name: orchestrator-models
description: |
  Mostra e ajusta qual modelo e qual effort cada etapa do orquestrador usa —
  painel, planejamento, implementacao por nivel de risco, e review. Resolve o
  mapa de verdade rodando o resolver, em vez de so ler o YAML, e explica a
  consequencia de custo antes de mudar.
  Use sempre que aparecer "/orchestrator-models", "que modelo esta rodando?",
  "trocar o modelo", "ajustar o effort", "esta caro demais", ou quando alguem
  quiser saber onde o custo esta indo.
---

# Modelos e effort por etapa

## Mostre o estado real, nao o arquivo

Ler o YAML nao prova nada: por semanas este bloco foi decoracao — os valores
estavam la e nada os lia. Resolva de verdade:

```bash
./bin/registry-edit.py show                  # o que o registry diz
./bin/implementer-model.sh <TEAM>-1 --flags  # o que o despacho realmente usa
grep '"model"' .claude/settings.json         # o painel
grep '^model:' ~/.claude/agents/orch-*.md    # os subagentes instalados
python3 -c "import json;print(json.load(open('$HOME/.claude/settings.json')).get('effortLevel'))"
```

| Papel | Onde e ligado |
|---|---|
| orquestrar, triar, rotear | `"model"` em `.claude/settings.json` do painel |
| planejar no worktree | `~/.claude/agents/orch-planner.md` |
| implementar | `$(bin/implementer-model.sh <IDENT> --flags)` no `worker-start` |
| revisar o diff | `~/.claude/agents/orch-reviewer.md` |

**O effort do painel, do planner e do reviewer nao esta escrito no repo.** E o
`effortLevel` do `~/.claude/settings.json`, configuracao de sessao que vale para
todos. So o implementador o sobrescreve, porque so ele tem um eixo — o risco do
ticket — para variar.

## Antes de mudar, diga a consequencia

Duas medicoes que contradizem a intuicao, e as duas mudam a decisao:

**O custo e leitura, nao escrita.** Na conta do worker: cache read 56%, cache
write 28%, saida 15%. Trocar o **modelo** muda o preco do token de entrada, que
e o que domina. Mexer em **effort** alcanca so a saida.

Consequencia pratica, e ela desaponta: **`effort` nao e alavanca de custo.**
Baixar o teto de um nivel de risco e escolha de qualidade proporcional ao risco,
nao economia. Quem economiza e trocar o modelo daquele nivel.

**Planejar e barato.** Dentro do worker, ler-e-planejar e 24% do custo e
implementar e 76%. Por isso o modelo caro no planejamento sai barato, e uma
troca na implementacao rende muito.

Diga isso **antes** de aplicar, com numero quando tiver. Alguem pedindo "baixa o
effort para gastar menos" esta prestes a nao economizar nada.

## Aplique

```bash
# modelo e effort de um nivel de risco
./bin/registry-edit.py set-model --role implementer_by_risk.medium --model sonnet --effort high

# papel simples (o effort vem do global)
./bin/registry-edit.py set-model --role planner --model opus
```

`--dry-run` mostra o diff sem gravar. O comando aborta se a edicao tocar em
qualquer chave alem da pretendida.

**Painel e subagentes nao passam pelo registry** — o registry documenta, os
arquivos e que ligam:

```bash
# painel: edite "model" em .claude/settings.json
# subagentes: edite .claude/agents/orch-*.md e DEPOIS
./bin/install-agents.sh
```

Esquecer o `install-agents.sh` deixa o repo dizendo uma coisa e o subagente
rodando outra. O `./bin/doctor.sh` acusa essa divergencia.

## Invariantes

- **O reviewer nunca fica abaixo do implementador.** Com `gate: []` ele e a
  unica verificacao automatica entre o codigo e o humano; rebaixa-lo esvazia o
  unico ponto de controle que existe.
- **O fallback e o ajuste mais caro, de proposito.** Ele so entra quando falta
  dado. A falha silenciosa aceitavel e gastar demais, nunca entregar de menos.
- **Nunca fixe modelo na skill de despacho.** A decisao e do
  `implementer-model.sh`, que le o registry a cada chamada. Tabela na cabeca do
  agente da vez e regra que um dia nao e aplicada.
- **Alias, nao id fixo.** `opus`/`sonnet` seguem o modelo mais novo da familia,
  entao lancamento novo nao exige editar nada.

## Verifique

```bash
./bin/implementer-model.sh <IDENT-de-risco-alto> --flags
./bin/implementer-model.sh <IDENT-de-risco-baixo> --flags
./bin/doctor.sh
```

Dois tickets de niveis diferentes provam que o roteamento responde. Ler o YAML
de novo nao prova.
