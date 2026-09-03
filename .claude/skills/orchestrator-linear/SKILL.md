---
name: orchestrator-linear
description: |
  Configura o lado Linear do orquestrador: valida o token da API, descobre os
  times, e cria os 9 estados do workflow e os grupos de etiqueta (Repo, Risk,
  Stack, Fast Track) que o roteamento inteiro depende. Idempotente: rodar de
  novo so cria o que falta.
  Use sempre que aparecer "/orchestrator-linear", "configurar o linear",
  "definir o token do linear", "criar os estados", "faltam as etiquetas", ou
  quando o /orchestrator-doctor acusar estado ou grupo faltando.
---

# Linear: token, estados e etiquetas

## Ancore-se na raiz antes de qualquer comando

As chamadas abaixo sao relativas, e o diretorio de trabalho persiste entre elas.
Rode isto primeiro — uma vez, e vale para a skill inteira:

```bash
cd "${ORCH_ROOT:-.}" && [ -f registry.example.yaml ] \
  || echo "nao estou na raiz do orquestrador: defina ORCH_ROOT ou entre nela"
```

Se reclamar, **pare e resolva**. Sessao aberta fora da raiz carrega estas skills
mas nao acha o `bin/` — e a falha aparece no meio do trabalho, nao no comeco.


## 1. O token — voce nunca o digita para mim

**Nao peca o token, nao aceite se for colado, e nao escreva em arquivo nenhum.**
Se o usuario colar um token no chat, avise que ele acabou de vazar para o
transcript e que o certo e revoga-lo e gerar outro.

Primeiro veja se ja existe:

```bash
./bin/linear-query.sh '{ viewer { id name } }' 2>&1 | head -5
```

Se responder com um nome, o token existe e funciona — pule para a etapa 2.

Se falhar, entregue **este comando para o humano rodar**, explicando que o `!`
no inicio da linha executa na sessao dele:

```
! umask 077 && printf 'export LINEAR_API_KEY="COLE_AQUI"\n' >> ~/.zshenv && chmod 600 ~/.zshenv
```

O token sai de *Linear → Settings → Security & access → Personal API keys*.

Tres coisas para dizer junto, porque cada uma ja custou tempo:

- **`~/.zshenv`, nao `.zshrc`.** O `.zshrc` so e lido por shell interativo, e os
  prechecks do cron rodam em shell nao interativo.
- **O Orca nao vai enxergar a chave ate ser reiniciado.** Ele e app de GUI e
  herda o ambiente do launchd de quando abriu. O `bin/linear-key.sh` contorna
  lendo o arquivo direto, mas so scripts nossos passam por ele.
- Depois que o humano rodar, valide de novo antes de seguir.

## 2. Descobrir o time

```bash
./bin/linear-query.sh '{ teams(first:20){ nodes{ id key name } } }'
```

Se houver mais de um, pergunte qual. **Estados e etiquetas sao por time** — com
mais de um time, tudo abaixo se repete para cada.

## 3. Diagnostico antes do plano

Uma consulta so, e dela sai tudo:

```bash
./bin/linear-query.sh '{ teams(filter:{key:{eq:"<TEAM>"}}, first:1){ nodes{
  id key
  states{ nodes{ id name type position } }
  labels{ nodes{ id name parent{ name } } }
} } }'
```

⚠️ **A API devolve o nome da etiqueta SEM o prefixo do grupo.** `Repo/Acme - API`
e so como a interface exibe; via GraphQL vem `name: "Acme - API"` com
`parent: { name: "Repo" }`. Filtre por `parent.name`. Um filtro
`startswith("Repo/")` nunca casaria — e o sistema ficaria mudo, sem erro nenhum.

## 4. O plano — mostre e confirme UMA vez

Liste o que falta e o que ja existe, e peca um ok so:

```
Vou criar no time ACME:
  estados   Drafting, Drafted, Scheduled, Manual QA        (4 de 9 faltam)
  grupos    Risk/{high,medium,low}
  etiqueta  Fast Track
Ja existem: Draft, Ready for Agent, In Progress, In Review, Done, grupo Repo/

Confirma?
```

Nao pergunte item por item. Sao ~15 confirmacoes num setup completo, e isso
treina qualquer um a aprovar no automatico.

## 5. Os estados

Nove, nesta ordem:

```
Draft -> Drafting -> Drafted -> Ready for Agent -> Scheduled
  -> In Progress -> In Review -> Manual QA -> Done
```

| Estado | `type` | `position` | Quem move |
|---|---|---|---|
| `Draft` | backlog | 0.3 | humano (escreve a ideia) |
| `Drafting` | backlog | 0.5 | a triagem — **e o claim dela** |
| `Drafted` | backlog | 0.7 | a triagem, ao terminar |
| `Ready for Agent` | unstarted | 1.5 | **humano — e o Start** |
| `Scheduled` | started | 1.9 | o coordenador — **e o lock** |
| `In Progress` | started | 2 | o worker |
| `In Review` | started | 3 | o worker |
| `Manual QA` | started | 4 | o coordenador |
| `Done` | completed | 5 | humano (o merge dispara) |

⚠️ **`position` ordena DENTRO do grupo de `type`, nao globalmente.** Por isso os
tres da triagem sao todos `backlog`, mesmo `Drafting` sendo "trabalho
acontecendo": marca-lo como `started` o jogaria para o grupo do `Scheduled` e
ele apareceria no board depois de `Drafted`, com a ordem invertida.

```bash
TEAM_ID=$(./bin/linear-query.sh '{ teams(filter:{key:{eq:"<TEAM>"}}, first:1){ nodes{ id } } }' \
  | jq -r '.data.teams.nodes[0].id')

./bin/linear-query.sh "mutation {
  workflowStateCreate(input: {
    teamId: \"$TEAM_ID\", name: \"Drafting\", type: \"backlog\",
    position: 0.5, color: \"#bec2c8\"
  }) { success workflowState { id name } }
}"
```

`Backlog`, `Todo`, `Canceled` e `Duplicate` ja vem do Linear e podem continuar.

**Nunca renomeie um estado existente para encaixar.** Os prechecks casam por
nome exato; renomear mata o disparo do cron em silencio. Crie o que falta.

## 6. As etiquetas

| Grupo | Filhos | `isGroup` |
|---|---|---|
| `Repo` | um por repositorio do registry | **sim** |
| `Risk` | `high` · `medium` · `low` | sim |
| `Stack` | uma por combinacao de repos que se repete | sim |
| (sem grupo) | `Fast Track` | — |

⚠️ **`status` e nome reservado no Linear.** Criar um grupo chamado `Status` e
recusado com *«The label name "status" is reserved»*. Por isso `Fast Track` e
plana.

```bash
./bin/linear-query.sh "mutation {
  issueLabelCreate(input: { teamId: \"$TEAM_ID\", name: \"Risk\", isGroup: true })
  { success issueLabel { id name } }
}"
# e depois cada filho, com parentId = o id devolvido acima
```

As etiquetas `Repo/` **nao se criam aqui**: cada uma nasce junto com o repo, em
`/orchestrator-repo-add`, porque o nome precisa ser identico a chave do registry
e criar nos dois lugares separadamente e como divergem.

## 7. Verifique

Repita a consulta do passo 3 e confira que nada falta. Depois:

```bash
./bin/doctor.sh
```

A secao `linear` tem que sair sem FALHA.

## Automations nativas do Linear

Diga ao humano, porque so ele consegue e o efeito e confuso quando escapa:
desligue *PR aberto → In Progress* e *review → In Review*, que brigam com o
worker movendo o mesmo ticket. **Mantenha** *PR merged → Done*.
