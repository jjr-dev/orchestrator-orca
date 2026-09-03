---
name: orchestrator-repo-add
description: |
  Acrescenta um repositorio ao orquestrador de ponta a ponta: registra no Orca,
  cria a etiqueta Repo/ no Linear e escreve a entrada no registry.yaml com os
  invariantes ja corretos. Tambem cria a empresa, quando ela ainda nao existe.
  Use sempre que aparecer "/orchestrator-repo-add", "adiciona esse repo",
  "novo projeto no orquestrador", "adicionar item no registry", ou quando um
  ticket apontar para um repo que o registry ainda nao conhece.
---

# Acrescentar um repositorio

Tres sistemas precisam concordar: o **Orca** (que sabe clonar), o **Linear** (que
tem a etiqueta) e o **registry** (que liga os dois). Se um ficar de fora, o
ticket some sem erro nenhum. Por isso e uma skill, e nao tres comandos.

## 1. O que voce precisa saber

Pergunte o que faltar, mas **descubra sozinho o que der para descobrir**:

| Dado | Como obter |
|---|---|
| caminho local do repo | perguntar |
| empresa | perguntar, ou deduzir se so existe uma |
| nome da etiqueta | propor a partir do nome do repo, e confirmar |
| base branch | `git -C <caminho> symbolic-ref refs/remotes/origin/HEAD` |
| gerenciador de pacote | ver o lockfile |
| risco padrao | propor pelo que o repo e, e confirmar |

```bash
git -C <caminho> symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's#.*/origin/#origin/#'
git -C <caminho> branch -r | grep -E 'origin/(main|master|develop|development|sandbox)$'
ls <caminho> | grep -E 'package-lock.json|yarn.lock|pnpm-lock.yaml|composer.lock'
```

⚠️ **Repo com `main` e `develop` nao se resolve por heuristica.** Pergunte de
qual branch saem as features. Escolher errado faz todo worker daquele repo
partir de codigo velho, e nada acusa — o PR abre, passa no review e so aparece
como conflito no merge.

O campo `setup` e **documentacao para o humano**. O agente nunca o executa;
`gate` fica `[]`. Preencha com o comando correto mesmo assim: quem le o PR usa.

## 2. O plano — mostre e confirme uma vez

```
Vou acrescentar "Acme - API" na empresa acme:

  Orca      orca repo add --path /caminho/acme-api
  Linear    etiqueta Repo/Acme - API  (grupo Repo, ja existe)
  registry  base origin/development · setup npm ci · gate [] · risk_default high

Confirma?
```

## 3. Execute, nesta ordem

A ordem importa: o registry e o ultimo porque precisa do id que o Orca devolve.

```bash
# a) Orca — devolve o id que vai para o registry
orca repo add --path /caminho/absoluto --json
```

Se o repo ja estiver registrado, o Orca diz. Reaproveite o id, nao crie outro.

```bash
# b) Linear — a etiqueta, dentro do grupo Repo
TEAM_ID=$(./bin/linear-query.sh '{ teams(filter:{key:{eq:"<TEAM>"}}, first:1){ nodes{ id } } }' | jq -r '.data.teams.nodes[0].id')
REPO_GRUPO=$(./bin/linear-query.sh "{ teams(filter:{key:{eq:\"<TEAM>\"}}, first:1){ nodes{ labels{ nodes{ id name parent{ name } } } } } }" \
  | jq -r '.data.teams.nodes[0].labels.nodes[] | select(.name=="Repo" ) | .id')

./bin/linear-query.sh "mutation {
  issueLabelCreate(input: {
    teamId: \"$TEAM_ID\", parentId: \"$REPO_GRUPO\", name: \"Acme - API\"
  }) { success issueLabel { id name } }
}"
```

🔴 **O nome da etiqueta e a chave do registry tem que ser identicos**, byte a
byte. E a chave da resolucao inteira. Divergir num espaco ou num hifen deixa
todo ticket daquele repo invisivel para o coordenador, sem erro.

```bash
# c) registry — pela porta unica de escrita, nunca editando o arquivo direto
./bin/registry-edit.py add-repo \
  --company acme \
  --name "Acme - API" \
  --slug api-acme \
  --orca-repo-id <id-que-o-orca-devolveu> \
  --base origin/development \
  --setup "npm ci" \
  --risk-default high \
  --pair "Acme - Web" \
  --manual "npm run lint" "npm run typecheck" "npm run build"
```

O `registry-edit.py` recusa `base` sem `origin/`, recusa nome duplicado, forca
`gate: []`, mostra o diff antes de gravar e aborta se a edicao tocar em qualquer
chave alem da pretendida. Use `--dry-run` se quiser ver antes.

**Empresa que ainda nao existe** vem primeiro:

```bash
./bin/registry-edit.py add-company --key acme --linear-team ACME --wip-max 3
```

`wip_max` e por empresa e protege a maquina: cada worker e uma sessao completa
do Claude Code. Dimensione pela RAM, nao pelo numero de repos.

## 4. Verifique

```bash
./bin/registry-edit.py show
./bin/doctor.sh
```

O doctor cruza registry × Linear: se a etiqueta e a chave divergirem, ele acusa
em *"repo sem etiqueta Repo/ correspondente"*. Nao encerre com essa falha aberta
— e exatamente o estado em que tudo parece pronto e nenhum ticket anda.

## O que voce NAO faz aqui

- **Nao clone nem toque no repo do cliente.** `orca repo add` so registra um
  caminho que ja existe.
- **Nao rode nada do projeto** — nem `npm install` para "descobrir o setup".
  Leia o lockfile.
- **Nao crie a Stack** por conta propria. Stack e para combinacao que se repete;
  proponha quando houver `pair`, e deixe o humano decidir.
