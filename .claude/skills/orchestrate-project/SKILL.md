---
name: orchestrate-project
description: |
  Modo manual e de planejamento: recebe uma etiqueta Repo/ ou um projeto do Linear,
  monta o grafo de dependencias e imprime a tabela de ondas — quem entra agora, quem
  espera qual merge, e qual e o caminho mais longo do grafo. Com --run, despacha a
  primeira onda; sem, so mostra.
  Use sempre que aparecer "/orchestrate-project", "monta as ondas", "como fica o
  grafo desse projeto", "o que da pra rodar em paralelo", "planeja esse projeto",
  ou quando o usuario colar um link de projeto do Linear querendo ver o plano.
---

# Planejar um projeto em ondas

Argumentos: `<etiqueta Repo/ | url de projeto do Linear> [--run]`

O fluxo do dia a dia e a `/pull-ready`, que nao tem barreira de onda: cada ticket
entra assim que os proprios blockers fecham. Esta skill existe para **enxergar** o
projeto inteiro antes de comecar.

## Passo 1 - Ler

Leia o projeto e TODAS as issues, com `includeRelations` para pegar
`blocks` / `blockedBy`. Nao infira dependencia por titulo. Blocker fora do projeto
conta: leia o estado dele tambem, mas nao o despache.

Tickets em multiplos repos sao normais — o grafo atravessa etiquetas.

## Passo 2 - Calcular

- Nos = issues. Arestas = `blockedBy`.
- Onda de um ticket = `max(onda dos blockers) + 1`. Sem blocker aberto = onda 1.
- Ticket `Done` conta como blocker satisfeito (onda 0).
- Blocker externo ainda aberto: o dependente nao tem onda. Marque
  `bloqueado externamente por <ID>`.

## Passo 3 - Imprimir

```
| Onda | Ticket | Repo | Desbloqueia | Pontos |
```

Depois, tres linhas de leitura que sao o ponto da skill:

1. **Profundidade do grafo**: o caminho mais longo. Esse numero e quantas vezes o
   humano vai ter que revisar e mergear em sequencia. E a unica metrica de tempo
   que importa — largura e barata, profundidade custa um review.
2. **Fan-in**: tickets com 2+ blockers, que so comecam quando todos fecharem.
3. **Onde encurtar**: aponte pares FE/BE que estao em serie com `blockedBy` e que
   poderiam ir em paralelo se o contrato subisse para o pai. Essa e a otimizacao de
   maior retorno.

Aponte tambem os tickets que introduzem flag OFF por padrao. Nunca ligue a flag.

## Passo 4 - Alertas

- Ticket acima de 5 pontos: sugira quebrar.
- Ticket separado so de testes: sugira fundir no ticket que ele testa.
- Ticket de "foundation" com funcoes para uso futuro: sugira eliminar.
- Ticket sem etiqueta `Repo/` que nao e issue pai: sinalize, nao sera despachado.

## Passo 5 - Despachar (so com --run)

Sem `--run`, pare no relatorio. Com `--run`, delegue para a `/pull-ready` da
empresa correspondente — nao duplique aqui a logica de claim e dispatch.
