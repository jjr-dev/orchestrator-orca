---
name: orc-help
description: |
  Lista todos os comandos do orquestrador com uma linha sobre cada um, as duas
  portas de entrada (pelo Linear e pelo chat), os scripts que voce pode rodar
  direto, e o kill switch. Use quando nao lembrar o nome de um comando ou quiser
  saber o que existe.
  Use sempre que aparecer "/orc-help", "quais comandos existem?", "como uso o
  orquestrador?", "esqueci o nome do comando", ou quando alguem estiver vendo o
  sistema pela primeira vez.
---

# Referencia de comandos

## Ancore-se na raiz antes de qualquer comando

```bash
cd "${ORCH_ROOT:-.}" && [ -f registry.example.yaml ] \
  || echo "nao estou na raiz do orquestrador: defina ORCH_ROOT ou entre nela"
```

## Rode

```bash
./bin/help.sh
```

Imprima a saida **como ela sai**, sem reescrever. Ela ja esta agrupada e
alinhada, e reescrever a mao e como a referencia comeca a divergir do sistema.

## Por que e script e nao texto aqui

A lista sai de `.claude/skills/orc-*/`, lida do disco. Skill nova aparece
sozinha. O que e escrito a mao — o grupo e a frase de uma linha — mora em
`descreve()`, dentro do `bin/help.sh`.

**Quando uma skill nao esta nesse mapa, o script avisa** em vez de omiti-la. Se
voce acabou de criar uma skill e o aviso apareceu, acrescente a linha dela; o
custo de ignorar e uma referencia que mente, e este projeto ja tem historico
disso.

## Depois de imprimir

Se a pessoa perguntou como fazer algo especifico, **responda a pergunta** em vez
de so despejar a lista. A saida do script e o mapa; ela veio atras de um
caminho.

Duas perguntas que aparecem sempre, e a resposta curta de cada uma:

- **"Por onde eu comeco?"** — Se o sistema nunca foi instalado nesta maquina,
  `/orc-setup`. Se ja esta rodando e voce quer trabalho novo, `/orc-task`.
- **"Como sei se esta tudo ligado?"** — `/orc-doctor`. Ele e o unico que
  responde isso com evidencia; o resto voce descobre quando para de funcionar.

## O que voce NAO faz aqui

- **Nao execute nenhum dos comandos listados.** Esta skill descreve; quem
  decide rodar e o humano.
- **Nao invente comando que nao esta na lista.** Se ele nao apareceu, ou nao
  existe, ou nao foi classificado — e nos dois casos a resposta e dizer isso.
