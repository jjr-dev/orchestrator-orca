---
name: orchestrator-sync
description: |
  Reconcilia as tres pontas da configuracao — registry.yaml, Linear e Orca —
  e mostra onde elas discordam: repo sem etiqueta, etiqueta orfa, repo id que
  nao existe mais, estado renomeado, stack apontando para repo removido.
  Propoe o conserto de cada divergencia e so aplica com o seu ok.
  Use sempre que aparecer "/orchestrator-sync", "sincroniza o linear",
  "as etiquetas estao certas?", depois de mexer no Linear pela interface, ou
  quando um ticket nao for roteado e voce nao souber por que.
---

# Sincronizar registry ↔ Linear ↔ Orca

Nao confunda com `/reconcile`. Aquele cuida de **trabalho** travado (ticket
orfao, worker morto). Este cuida de **configuracao** divergente.

A divergencia tipica nasce de uma edicao pela interface do Linear: alguem
renomeia uma etiqueta, e o registry continua com o nome velho. Nada quebra,
nenhum erro aparece, e os tickets daquele repo simplesmente param de ser
roteados.

## 1. Colete as tres pontas

```bash
# registry
./bin/registry-edit.py show --json > /tmp/orch-registry.json

# linear: estados e etiquetas do time
./bin/linear-query.sh '{ teams(filter:{key:{eq:"<TEAM>"}}, first:1){ nodes{
  id key
  states{ nodes{ name type } }
  labels{ nodes{ id name parent{ name } } }
} } }' > /tmp/orch-linear.json

# orca
orca repo list --json > /tmp/orch-orca.json
```

⚠️ O nome da etiqueta vem **sem** o prefixo do grupo. Filtre por `parent.name`,
nunca por `startswith("Repo/")`.

## 2. Compare

Seis divergencias, e cada uma tem um sintoma diferente:

| Divergencia | Sintoma no dia a dia | Conserto |
|---|---|---|
| repo no registry, sem etiqueta `Repo/` | ticket daquele repo nunca e despachado | criar a etiqueta |
| etiqueta `Repo/` sem repo no registry | ticket etiquetado da erro na resolucao | criar o repo, ou apagar a etiqueta |
| `orca_repo_id` que nao existe mais no Orca | despacho falha com `selector_not_found` | reregistrar e atualizar o id |
| estado do workflow renomeado | o precheck do cron para de disparar, mudo | recriar o estado com o nome exato |
| `Risk/<nivel>` faltando | tickets daquele nivel caem no fallback (o mais caro) | criar a etiqueta |
| `stacks:` citando repo que nao esta em `repos:` | ticket de stack quebra no meio | corrigir o registry |

Compare **nomes exatos**, sem normalizar caixa nem espaco. `Acme - API` e
`Acme  - API` sao repos diferentes para a resolucao, e e justamente esse tipo de
diferenca que voce esta procurando.

## 3. Relate antes de consertar

```
registry ↔ Linear ↔ Orca

  ✓ 18 repos alinhados nas tres pontas
  ✗ "Beta - Forms" no registry, sem etiqueta Repo/ no Linear
      → nenhum ticket desse repo foi roteado desde que ele entrou
  ✗ etiqueta "Gama - Legacy" sem entrada no registry
      → 3 tickets abertos com ela vao dar erro de resolucao
  ⚠ estado "Manual QA" nao existe; ha um "QA Manual"
      → renomeado pela interface. O precheck casa por nome exato e esta mudo.

Conserto proposto:
  criar etiqueta Repo/Beta - Forms
  criar estado "Manual QA" (o "QA Manual" fica, para voce mover os tickets)
Pendente de decisao sua:
  "Gama - Legacy" — apagar a etiqueta ou acrescentar o repo?

Confirma o conserto?
```

Uma confirmacao para o lote inteiro. O que exigir julgamento fica separado,
como pendencia, e nao entra no lote.

## 4. Conserte

Etiqueta e estado: as mutations estao em `/orchestrator-linear`.
Registry: **sempre** por `./bin/registry-edit.py`, nunca editando o arquivo.

```bash
./bin/registry-edit.py add-repo --company <emp> --name "<nome>" ...
./bin/registry-edit.py rm-repo --name "<nome>"
```

## 5. O que NUNCA fazer aqui

- **Nao apague etiqueta que tem ticket usando.** Consulte antes:
  `{ issues(filter:{labels:{name:{eq:"<nome>"}}}, first:1){ nodes{ id } } }`.
  Etiqueta apagada leva o vinculo junto e nao volta.
- **Nao renomeie estado para "alinhar".** Renomear muda o estado dos tickets que
  estao nele. Crie o certo e deixe a migracao com o humano.
- **Nao remova repo do registry so porque a etiqueta sumiu.** A etiqueta pode
  ter sido apagada por engano; o registry costuma ser a ponta certa.
- **Nao decida sozinho o lado da verdade** quando os dois lados fazem sentido.
  Pergunte.

## 6. Verifique

```bash
./bin/doctor.sh
```

A secao `linear` tem que sair sem FALHA.
