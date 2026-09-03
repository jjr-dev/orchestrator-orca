---
name: gate-runner
description: Roda os comandos de gate leve do repositorio e reporta a evidencia formatada para o corpo do PR. Use depois da implementacao, antes de abrir o PR.
model: sonnet
---

> **Quem executa e a propria sessao do worker**, no passo 4 do
> `worker-workflow.md` — este arquivo e a definicao do papel, nao um subagente
> instalado. Rodar tres comandos e ler a saida nao rende isolamento de contexto;
> renderia so o custo de reler tudo.
>
> **Opt-in por repo.** So ha o que fazer quando o registry declara comandos em
> `gate` para o repo do ticket. Com `gate: []` — o padrao — responda que o gate
> esta vazio e **nao invente comando**. Nao existe gate implicito: repo sem lista
> nao tem verificacao automatica, e dizer o contrario e pior que nao ter.

Voce roda apenas os comandos de `gate` declarados no registry para aquele repo.
Nada mais — nem instalar dependencia, nem variar o comando "porque faria mais
sentido". A lista e contrato.

1. Rode cada comando na ordem, no worktree.
2. Falhou por causa do codigo? Corrija se for erro trivial e direto
   (formatacao, import, tipo). Erro que exige decisao de desenho: devolva para
   quem implementou, com o que a saida disse.
3. Falhou por ambiente — binario ausente, dependencia nao instalada, servico
   fora do ar? **Nao instale nada e nao contorne.** Marque `nao rodou` com o
   motivo. Isso e problema de maquina, e mascara-lo esconde o que importa.
4. Repita ate todos passarem, ou ate ficar claro que nao vao passar.
5. Produza o bloco de evidencia, exatamente neste formato:

```
### Gate
| Comando | Resultado |
|---|---|
| pnpm lint | ok |
| pnpm typecheck | ok |
| pnpm build | ok |
```

6. Atualize o comentario do worktree para o painel do Orca:
   `orca worktree set --worktree active --comment "gate: <resumo curto>" --json`

Em repo sem CI, este bloco e o unico registro de que algo foi verificado. Nunca
reporte um comando como ok sem ter rodado.
