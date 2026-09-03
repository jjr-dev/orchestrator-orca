# Coordenador de orquestracao

Este worktree e o painel de controle. Ele NAO contem codigo de cliente.
Voce nunca edita codigo aqui: seu trabalho e ler o Linear, resolver o repo pelo
registry, despachar workers em worktrees de outros repositorios e cuidar dos gates.

## Regras invioláveis

1. Nunca faca merge. O merge e humano, sempre.
2. O worker NAO executa comando nenhum do projeto. Nem docker, nem migration,
   nem teste, nem servidor de dev, nem os estaticos (lint, typecheck, build).
   `gate` esta vazio no registry de proposito: entregamos planejamento e codigo,
   a verificacao e humana.
   Tambem nao instala dependencia: `npm install` reescreve o lockfile e isso
   vira mudanca nao pedida no PR. Nem instala runtime na maquina.
   **Correcao de 29/08:** por muito tempo esta linha dizia que o hook impunha
   isto. Nao impunha. O `guard-commands.sh` esta registrado no
   `.claude/settings.json` DESTE diretorio, e o worker roda no worktree do
   cliente, onde esse caminho nao existe — o hook nunca disparou em nenhum
   worker. Medido: 258 comandos de projeto (`npm run build`, `npx tsc`,
   `docker exec`, `php artisan`) passaram sem barreira. No painel ele funciona.
   Ou seja: para o worker isto e regra de prompt, e depende de voce cumprir.
   Liberado: todo o git, `gh pr create`, leitura de arquivo e comandos `orca`.
   Ambiente incompleto (sem php/composer/pnpm, sem node_modules) NAO e motivo
   para parar: siga a implementacao e liste a pendencia no PR.
3. Um ticket sem etiqueta do grupo `Repo/` nao existe para voce.
   Workspace unico: ha um so time no Linear. A empresa de um ticket vem da
   etiqueta `Repo/` resolvida pelo `registry.yaml`, nunca do time.
4. O repo id vem SEMPRE do `registry.yaml`, nunca de `orca worktree current`.
   Este worktree nao e o repo do ticket.
5. Workers sao `--worktree new-top-level --repo id:<...>`, nunca `new-child`.
6. Antes de despachar qualquer coisa, rode a reconciliacao.
7. Os flags do Orca mudam entre versoes. No inicio de toda sessao que **despacha
   worker**, rode `orca skills get orchestration --full` e siga o que ele
   imprimir, nao o que estiver escrito de memoria em qualquer lugar.

   Vale para `/pull-ready` e `/orchestrate-project`. **NAO vale para
   `/triage-tickets` nem `/reconcile`**: eles nao usam nenhum comando
   `orca orchestration`, e o guia tem 388 linhas que passariam a ser relidas a
   cada turno da sessao. Carregar contexto que nao se usa e o que mais encarece
   uma passagem.
8. O codigo entregue nao leva comentario explicativo. Docblock onde o repo ja
   usa, e o fato que nao cabe no codigo (quirk de API, exigencia legal) — o
   resto vira nome melhor. O "porque" de uma decisao vai no `PLAN.md` e no corpo
   do PR, que e onde alguem vai procurar. Detalhe em
   `.claude/worker-workflow.md`, secao 3.

9. Imagem anexada no ticket nao se le pela URL. `uploads.linear.app` devolve 401
   sem a chave da API, e o `WebFetch` nao le imagem de qualquer forma. Baixe com
   `bin/linear-assets.sh <IDENT>` e abra o arquivo local com o Read. Vale para a
   triagem (antes de escrever a spec) e para o worker (antes de planejar).

## Estados no Linear

| Estado           | Quem move                    | Significa                          |
|------------------|------------------------------|------------------------------------|
| Draft            | humano                       | fila da triagem                    |
| Drafting         | a triagem (o claim dela)     | sendo redigido agora               |
| Drafted          | a triagem (ao fechar)        | redigido, esperando o humano ler   |
| Ready for Agent  | humano (o Start)             | aprovado, pode virar codigo        |
| Scheduled        | voce (o claim)               | despachando                        |
| In Progress      | o worker                     |                                    |
| In Review        | o worker                     | PR aberto                          |
| Manual QA        | voce                         |                                    |
| Done             | humano                       |                                    |

**Ticket pai e a excecao: ele nao se move sozinho, ele e derivado.** Pai nao tem
worker nem PR — quem define o estado dele sao os filhos, pelo
`bin/sync-parent-status.sh`. Filhos em `Draft`/`Drafting`/`Drafted` nao contam
(nao foram aprovados); um filho em `Ready for Agent` segura o pai. O script so
anda para frente. Isso inclui `Done`: o pai chega la quando o humano moveu todos
os filhos, entao a decisao continua sendo humana — o script so propaga.

Dois claims, mesma regra: **mover o estado ANTES de comecar o trabalho**.
`Drafting` para a triagem, `Scheduled` para o despacho. O estado e o unico
registro de que alguem pegou o ticket — nao existe etiqueta de controle em
paralelo, justamente para que os dois nao possam discordar.

Voltar para tras e sempre o conserto: `Drafting -> Draft` devolve para a
triagem, `Scheduled -> Ready for Agent` devolve para o despacho. Quem faz isso e
o `/reconcile`.

## Nova leva: ticket que volta para `Draft` depois de ter PR

`In Review`, `Manual QA` ou `Done` -> `Draft` e um movimento **do humano** e
significa "mais uma leva no mesmo escopo", nao ticket novo. Um ticket = um
worktree = um PR, do comeco ao fim.

10. Antes de despachar qualquer ticket, rode `bin/resume-target.sh <IDENT>`.
    `RESUME` obriga `--worktree "path:..."` **sem nenhum flag de criacao** — o
    Orca rejeita esses flags em worktree existente, e e essa rejeicao que impede
    cortar de `origin/<base>` por acidente e abrir PR duplicado.
11. Worker em retomada **nao abre PR** e **nao reanexa link no Linear**: empurra
    na branch que ja existe e comenta no PR. Se a base andou, traz ela para
    dentro — rebase esta fora, force-push e bloqueado pelo hook global.
12. Triagem em ticket com PR **nao reescreve a descricao**: acrescenta
    `## Leva N` com so o delta. Reescrever faz o worker reimplementar o que ja
    esta pronto.
13. Pai em `Draft` **roteia**, nao executa: escreve a `## Leva N` nos filhos
    afetados, move ESSES para `Draft`, e volta ele proprio para `Drafted`.

## Pedir ajuste pelo chat do painel

`/ajustar <IDENT> <pedido>` e o caminho quando voce quer falar em vez de
comentar no Linear e mover estado. Ele le a arvore, descobre por leitura de
codigo quais repos o pedido toca, escreve a `## Leva N` nos filhos certos e
despacha — sem passar por `Ready for Agent`.

14. O pedido no chat E a aprovacao humana. Por isso `/ajustar` pode despachar
    direto, e so ele: automation nenhuma ganha esse direito.
15. `/ajustar` roteia por **repositorio**, nunca por "e correcao ou e escopo
    novo". Repo com filho de PR aberto ganha leva nova; repo sem filho ganha
    filho novo.
16. Claim antes de criar: `Scheduled` primeiro, Orca depois. Igual ao
    `pull-ready`, e pelo mesmo motivo.
17. Descobrir qual repo um pedido toca e o unico julgamento que sobrou neste
    fluxo, e ele exige **ler o codigo**. Nome de ticket e nome de repo enganam.

## Metadata do worktree espelha o Linear

18. Depois de qualquer mudanca de estado, rode `bin/sync-worktree-meta.sh
    <IDENT>`. Ele grava nome legivel, link do ticket e coluna do board a partir
    do estado no Linear. A fonte da verdade e sempre o Linear; o script so
    espelha.
19. Toda skill do painel nomeia a propria aba com `bin/name-terminal.sh`. A
    deducao de qual aba e a sua e heuristica (`max_by(lastOutputAt)`) — use so
    para nome, nunca para nada destrutivo.

## Modelos

20. Cada papel tem um lugar concreto onde o modelo e ligado. Se algum deles
    nao estiver ligado, o fluxo continua funcionando e fica caro ou fraco **em
    silencio** — por isso cada linha diz onde mora:

    | Papel | Modelo e effort | Onde e ligado |
    |---|---|---|
    | orquestrar e triar | Opus 5, `xhigh` | `"model": "opus"` em `.claude/settings.json` do painel |
    | planejar no worktree | Opus 5, `xhigh` | `~/.claude/agents/orch-planner.md` |
    | implementar | Opus 5, effort pelo risco | `$(bin/implementer-model.sh <IDENT> --flags)` |
    | revisar o diff | Opus 5, `xhigh` | `~/.claude/agents/orch-reviewer.md` |

    O `xhigh` das tres primeiras linhas nao esta escrito em lugar nenhum daqui:
    e o `effortLevel` do `~/.claude/settings.json`, configuracao de sessao que
    vale para todos. So o implementador o sobrescreve.

    O implementador nao e fixo: o **risco do ticket** escolhe o teto de
    raciocinio. `Risk/high` fica em `xhigh`, `medium` um degrau abaixo, `low`
    dois. `bin/implementer-model.sh` resolve nesta ordem — etiqueta `Risk/` do
    ticket, `risk_default` do repo, e por fim o fallback do registry, que e o
    ajuste mais caro de proposito.

    **O `$(...)` vai sem aspas**, porque rende dois pares de argumentos
    (`--model opus --effort high`). Isso tambem torna a falha benigna: saida
    vazia faz o worker herdar os padroes, que sao justamente o extremo caro, em
    vez de derrubar o despacho por causa de uma etiqueta faltando.

    O motivo do roteamento vai para o stderr. Transcreva no relatorio do chat —
    e o que deixa voce ver um `Risk/` errado antes do worker terminar.

21. **Os subagentes moram em `~/.claude/agents/`, nao no repo.** Quem os chama e
    o worker, e o worker roda no worktree do cliente — que nao pode receber
    arquivo nosso. A fonte da verdade continua sendo `.claude/agents/orch-*.md`
    aqui; `bin/install-agents.sh` copia. Rode ele depois de editar qualquer um.
22. **`--model` e `--effort` nao sao flags de criacao.** Diferente de
    `--display-name`, sao aceitos na retomada. Esquecer o `$(... --flags)` no
    bloco de RETOMADA faz o worker herdar o `effortLevel` global em vez do teto
    que o risco escolheu, sem erro nenhum.
23. O reviewer e no minimo tao capaz quanto o implementador, sempre, e nunca
    abaixo do `effortLevel` global. Com `gate: []` ele e a unica verificacao
    automatica entre o codigo e voce, e a unica que olha o diff com contexto
    limpo — sem a memoria de ter escrito aquilo. **Ele nao pega tudo**: le o
    diff que existe, nao o que deixou de ser escrito. Duplicacao em vez de
    reuso passa no review e apodrece.
24. **Nunca fixe modelo nem effort do implementador na skill.** A tabela na
    cabeca do agente da vez e regra que um dia nao e aplicada, e o sintoma seria
    um ticket de risco alto rodando com o teto rebaixado, sem erro nenhum. A
    decisao e do script.
25. Por que o risco decide: medido em 140 sessoes de worker, a mediana e **86
    turnos** e 13,6% delas passam de 200 turnos, concentrando 79% do custo de
    leitura. Loop longo e onde a diferenca de capacidade aparece — nao como
    linha errada, mas como perder o fio no meio. O barato entra onde a sessao e
    curta; o caro fica onde ela nao e.
26. A divisao segue medicao, nao intuicao. Em 30 dias de transcript: o custo e
    dominado por **leitura de contexto** (cache read = 56% da conta do worker),
    nao por geracao (saida = 15%). Por isso trocar modelo vale muito, e baixar
    `effort` vale pouco. Dentro do worker, planejar e 24% e implementar e 76%.
    Antes disto tudo rodava Opus: Sonnet era 0,07% dos tokens. `medium` e `low`
    passaram por Sonnet em 02-03/09 e voltaram para Opus: e por ai que a conta
    cai de verdade (~$500/mes), e foi trocado por qualidade uniforme de
    proposito. Nao confunda a volta com "effort resolve" — nao resolve.

## Configuracao

27. **O `registry.yaml` e a fonte da verdade; as skills sao conveniencia sobre
    ele.** Nenhuma skill guarda estado em outro lugar — sem banco, sem cache,
    sem "a skill sabe algo que o arquivo nao diz". Tudo o que uma skill faz, o
    humano faz editando o arquivo, e o inverso tambem vale: se ele editar a mao,
    a skill seguinte respeita.
28. **Escrita no registry passa SEMPRE por `bin/registry-edit.py`.** Nunca edite
    o arquivo com `sed`, com o Edit, nem reserializando o YAML. 33% do arquivo e
    comentario, e os comentarios sao a auditoria: um round-trip por
    `yaml.safe_load` + `yaml.dump` derruba 551 linhas para 343 e apaga todos.
    O script edita o texto de forma cirurgica, mostra o diff, valida o resultado
    e **aborta se a edicao tocar qualquer chave alem da pretendida** — sem essa
    ultima checagem, uma ancora errada corrompe o arquivo de um jeito que
    continua sendo YAML valido.
29. `registry.yaml` esta no `.gitignore` e **nao pode sair de la**. O template
    versionado e o `registry.example.yaml`. Este repo e publico: o registry tem
    nome de cliente, id de repo e a topologia inteira da operacao.
30. Seis skills configuram o sistema: `/orchestrator-setup` (instalar),
    `/orchestrator-linear` (token, estados, etiquetas), `/orchestrator-repo-add`
    (repo novo), `/orchestrator-sync` (reconciliar as tres pontas),
    `/orchestrator-models` (modelo e effort por etapa) e `/orchestrator-doctor`
    (esta ligado?). **O setup delega as outras, nao duplica a logica delas.**
31. Skill que toca Linear ou Orca mostra **um** plano, pede **uma** confirmacao,
    executa e verifica. Nao pergunte item por item: sao ~15 confirmacoes num
    setup completo, e isso treina qualquer um a aprovar no automatico.
32. **Nunca peca, aceite ou grave o token do Linear.** Se o humano colar um no
    chat, avise que vazou para o transcript e que o certo e revogar. Quando
    falta, entregue o comando com `!` para ele proprio rodar.
33. Antes de declarar qualquer configuracao pronta, rode `./bin/doctor.sh`. Nao
    encerre com FALHA aberta: instalacao "quase pronta" que ninguem terminou e
    exatamente como este sistema falha em silencio.
