---
name: orc-backend
description: |
  Mostra e troca onde o orquestrador registra o trabalho: `linear` (ticket,
  board, cronjobs) ou `orca` (task do proprio Orca, tudo pelo chat, sem token
  nem servico externo). Explica o que muda, o que nao migra, e o que fazer
  depois da troca.
  Use sempre que aparecer "/orc-backend", "trocar para o orca", "desativar o
  linear", "voltar para o linear", "quero usar sem linear", "qual backend esta
  ativo".
---

# Backend: onde o trabalho e registrado

## Ancore-se na raiz antes de qualquer comando

```bash
cd "${ORCH_ROOT:-.}" && [ -f registry.example.yaml ] \
  || echo "nao estou na raiz do orquestrador: defina ORCH_ROOT ou entre nela"
```

## Sempre comece mostrando onde esta

```bash
./bin/backend.sh --explica
```

Se a pessoa so perguntou qual esta ativo, responda e **pare**. Trocar backend
sem pedido explicito e mudar o comportamento do sistema inteiro pelas costas.

## As duas opcoes

| | `linear` | `orca` |
|---|---|---|
| onde mora a spec | ticket do Linear | task do Orca |
| etiquetas `Repo/` `Risk/` | etiquetas de verdade | front-matter no topo da spec |
| estados | os 9 do workflow | 5 (`pending` `ready` `blocked` `dispatched` `completed`) |
| aprovacao no chat | ticket parado em `Drafted` | rascunho em `state/drafts/` |
| fila de triagem a cada 2 min | sim | **nao** — nao ha coluna para largar pedido |
| fila de execucao a cada 2 min | sim | sim, via `task-list --ready` |
| board visual | sim | `orca orchestration task-list` |
| imagem no ticket | baixa do Linear | caminho local passado no chat |
| comentario por ticket | sim | nao — plano fica no `PLAN.md`, veredito no PR |
| token / servico externo | exige | **nao exige** |
| historico | servidor | local, nesta maquina |

## Trocar

```bash
./bin/registry-edit.py set-backend orca     # ou linear
```

Essa e a **unica** forma. Ela passa pela porta de escrita do registry, que
prova que so `defaults.backend` mudou e recusa se a edicao vazar para outra
chave. Nao edite o YAML a mao aqui: o valor e lido por scripts que rodam sem
sessao nenhuma aberta, e um erro de digitacao para a fila em silencio.

Confirme que pegou, nos dois lugares que leem:

```bash
./bin/backend.sh
./bin/board.sh backend
```

Se divergirem, alguem esta lendo outro registry — pare e investigue antes de
seguir.

## 🔴 A troca nao migra nada

O que ja existe fica onde nasceu. Ticket no Linear continua no Linear; task no
Orca continua no Orca. Nao existe importacao, e **nao invente uma**: copiar
ticket para task duplicaria o registro de execucao sem nenhuma forma de saber
qual dos dois e verdade.

Antes de trocar, diga quanto trabalho esta no ar e pergunte, com a sua
recomendacao (regra 34):

```bash
./bin/board.sh list --team <TEAM> --state "In Progress"
./bin/board.sh list-drafts --team <TEAM>
```

**Recomendo: termine o que esta em `In Progress` antes de trocar.** Worker no ar
reporta para o backend em que nasceu, e depois da troca ninguem olha mais para
la. O trabalho nao se perde, mas some da sua vista.

## Depois de trocar

**Para `orca`:**

1. `./bin/doctor.sh` — ele pula as checagens do Linear sozinho e passa a
   verificar o Orca.
2. Desabilite a automation de triagem: sem board nao ha fila para ela vigiar.
   O precheck ja sai 1, entao ela nunca acorda, mas deixa-la habilitada e
   configuracao que mente.
   ```bash
   orca automations list
   ```
3. O token do Linear **pode ficar onde esta**. Nada mais o le, e apagar e um
   passo irreversivel por nenhum ganho. Se quiser mesmo remover, e no
   `~/.zshenv`, e a decisao e sua.

**Para `linear`:**

1. `/orc-linear` se o token nunca foi configurado nesta maquina.
2. `/orc-sync` para criar os estados e as etiquetas que faltarem.
3. `./bin/doctor.sh` — em modo linear ele checa os 9 estados e todo `Repo/`.
4. Reabilite a automation de triagem, se voce a desligou.

## O que voce NAO faz aqui

- **Nao troca sem pedido explicito.**
- **Nao migra dados entre backends.** Nao existe caminho seguro.
- **Nao apaga o token do Linear** ao sair dele.
- **Nao mexe em automation sem avisar qual e por que.**
