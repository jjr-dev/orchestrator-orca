#!/usr/bin/env python3
"""Porta de escrita no Linear. Chame pelo `bin/linear.sh`, que resolve a chave.

Por que existe: o `orca linear` resolve nome -> UUID a cada escrita, e cada
chamada e um processo novo, entao nada se aproveita entre elas. Medido em
11/09: mover dois tickets custa 4199 ms por ali e 401 ms aqui; criar um ticket
com estado e tres etiquetas custa 5630 ms por ali e 387 ms aqui.

Duas coisas compram essa diferenca:

  1. cache de UUID em state/linear-cache.json — estados e etiquetas de um time
     mudam raramente, e uma consulta de 306 ms traz todos;
  2. aliases de GraphQL — N tickets cabem numa requisicao so.

O que NAO muda: leitura continua sendo `orca linear issue` e `list-issues`.
Elas ja custam ~410 ms, perto do piso de rede, e as skills esperam o formato
de saida delas.

O cache que erra se conserta sozinho: nome que nao casa dispara uma rebusca e
tenta de novo. So o miss paga, e o miss e raro.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(RAIZ, "state", "linear-cache.json")
API = "https://api.linear.app/graphql"

# UUID de ticket e imutavel, entao essa metade do cache nunca vence. Cresce,
# porem. No limite jogamos fora inteiro em vez de expirar entrada por entrada:
# reconstruir custa uma consulta, e nao vale carregar politica de expiracao.
TETO_ISSUES = 5000


class Falha(Exception):
    pass


def gql(query, tentativas=3):
    chave = os.environ.get("LINEAR_API_KEY")
    if not chave:
        raise Falha("LINEAR_API_KEY ausente: rode por bin/linear.sh")

    corpo = json.dumps({"query": query}).encode()
    req = urllib.request.Request(
        API, data=corpo,
        headers={"Authorization": chave, "Content-Type": "application/json"},
    )

    for n in range(tentativas):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                d = json.loads(r.read())
            break
        except urllib.error.HTTPError as e:
            # 4xx e erro nosso e nao melhora repetindo. 5xx e da Linear.
            if e.code < 500 or n == tentativas - 1:
                raise Falha(f"HTTP {e.code} da Linear: {e.read()[:300].decode(errors='replace')}")
            time.sleep(0.4 * (n + 1))
        except (urllib.error.URLError, TimeoutError) as e:
            if n == tentativas - 1:
                raise Falha(f"rede indisponivel: {e}")
            time.sleep(0.4 * (n + 1))

    if d.get("errors"):
        msgs = [
            e.get("extensions", {}).get("userPresentableMessage") or e.get("message", "?")
            for e in d["errors"]
        ]
        raise Falha("Linear recusou: " + "; ".join(msgs))
    return d.get("data") or {}


def ler_cache():
    try:
        with open(CACHE) as f:
            c = json.load(f)
        if c.get("version") == 1:
            c.setdefault("teams", {})
            c.setdefault("issues", {})
            return c
    except (OSError, ValueError):
        pass
    return {"version": 1, "teams": {}, "issues": {}}


def gravar_cache(c):
    if len(c.get("issues", {})) > TETO_ISSUES:
        c["issues"] = {}
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    # Troca atomica: o cron e uma sessao de chat escrevem aqui ao mesmo tempo,
    # e um arquivo meio gravado seria lido como cache vazio para sempre.
    tmp = f"{CACHE}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(c, f, indent=2, sort_keys=True)
    os.replace(tmp, CACHE)


def buscar_meta(team):
    d = gql(
        '{ team(id:%s){ id key '
        "states(first:100){ nodes{ id name } } "
        "labels(first:250){ nodes{ id name parent{ name } } } } }" % json.dumps(team)
    )
    t = d.get("team")
    if not t:
        raise Falha(f"time '{team}' nao existe no Linear")

    estados = {n["name"]: n["id"] for n in t["states"]["nodes"]}

    # A API devolve o nome da etiqueta SEM o grupo: 'high', nao 'Risk/high'.
    # Indexamos as duas formas. Quando o nome curto aparece em mais de um grupo
    # ele sai do indice curto de proposito — resolver no escuro criaria ticket
    # com a etiqueta do grupo errado, e isso so apareceria no board.
    curtas, longas, repetidas = {}, {}, set()
    for n in t["labels"]["nodes"]:
        g = (n.get("parent") or {}).get("name")
        if g:
            longas[f"{g}/{n['name']}"] = n["id"]
        if n["name"] in curtas:
            repetidas.add(n["name"])
        curtas[n["name"]] = n["id"]
    for r in repetidas:
        curtas.pop(r, None)

    return {
        "id": t["id"],
        "estados": estados,
        "etiquetas": curtas,
        "qualificadas": longas,
        "ambiguas": sorted(repetidas),
        "buscado_em": int(time.time()),
    }


def meta(team, cache, forcar=False):
    if forcar or team not in cache["teams"]:
        cache["teams"][team] = buscar_meta(team)
        gravar_cache(cache)
    return cache["teams"][team]


def resolver(team, cache, tipo, nome):
    """tipo e 'estado' ou 'etiqueta'. Rebusca uma vez antes de desistir."""
    for forcar in (False, True):
        m = meta(team, cache, forcar=forcar)
        achou = (
            m["estados"].get(nome)
            if tipo == "estado"
            else m["qualificadas"].get(nome) or m["etiquetas"].get(nome)
        )
        if achou:
            return achou

    if tipo == "estado":
        existem = sorted(m["estados"])
        dica = ""
    else:
        existem = sorted(set(m["etiquetas"]) | set(m["qualificadas"]))
        dica = (
            f"\n  '{nome}' existe em mais de um grupo — use 'Grupo/{nome}'"
            if nome in m["ambiguas"] else ""
        )
    raise Falha(
        f"{tipo} '{nome}' nao existe no time {team}.{dica}\n  existem: " + ", ".join(existem)
    )


def time_do(ident):
    """JJR-217 -> JJR. Evita pedir --team em toda operacao sobre ticket."""
    if "-" not in ident:
        raise Falha(f"'{ident}' nao parece um identificador de ticket (esperado algo como JJR-217)")
    return ident.rsplit("-", 1)[0]


def resolver_idents(idents, cache):
    falta = sorted({i for i in idents if i not in cache["issues"]})
    if falta:
        partes = " ".join(
            f"i{n}: issue(id:{json.dumps(i)}){{ id identifier }}" for n, i in enumerate(falta)
        )
        try:
            d = gql("{ %s }" % partes)
        except Falha as e:
            raise Falha(f"{e}\n  resolvendo: {', '.join(falta)}")
        for n, i in enumerate(falta):
            no = d.get(f"i{n}")
            if not no:
                raise Falha(f"ticket '{i}' nao existe")
            cache["issues"][no["identifier"]] = no["id"]
        gravar_cache(cache)
    return {i: cache["issues"][i] for i in idents}


def texto_do(item, campo_texto="body", campo_arquivo="body_file"):
    if item.get(campo_arquivo):
        with open(item[campo_arquivo]) as f:
            return f.read()
    return item.get(campo_texto)


def confere(d, rotulo):
    """Uma mutation pode voltar 200 com success:false. Silenciar isso seria
    exatamente a falha que este projeto mais sofre: parece ligado e nao esta."""
    ruins = [k for k, v in d.items() if isinstance(v, dict) and v.get("success") is False]
    if ruins:
        raise Falha(f"{rotulo}: a Linear respondeu success:false em {len(ruins)} operacao(oes)")


def cmd_create(args, cache):
    if args.batch:
        with open(args.batch) as f:
            itens = json.load(f)
        if not isinstance(itens, list) or not itens:
            raise Falha("o --batch deve ser uma lista JSON nao vazia")
    else:
        if not args.title:
            raise Falha("informe --title ou --batch")
        itens = [{
            "title": args.title,
            "body": args.body,
            "body_file": args.body_file,
            "state": args.state,
            "labels": args.label,
            "parent": args.parent,
        }]

    inputs = []
    for it in itens:
        team = args.team or (time_do(it["parent"]) if it.get("parent") else None)
        if not team:
            raise Falha("informe --team (ou um parent, de onde o time e deduzido)")
        m = meta(team, cache)

        campos = [f'teamId:"{m["id"]}"', f"title:{json.dumps(it['title'])}"]

        corpo = texto_do(it)
        if corpo is not None:
            campos.append(f"description:{json.dumps(corpo)}")

        estado = it.get("state") or args.state
        if estado:
            campos.append(f'stateId:"{resolver(team, cache, "estado", estado)}"')

        pai = it.get("parent") or args.parent
        if pai:
            campos.append(f'parentId:"{resolver_idents([pai], cache)[pai]}"')

        etiquetas = it.get("labels") if it.get("labels") is not None else args.label
        ids = [resolver(team, cache, "etiqueta", l) for l in (etiquetas or [])]
        if ids:
            campos.append("labelIds:" + json.dumps(ids))

        inputs.append("{" + ", ".join(campos) + "}")

    partes = " ".join(
        f"c{n}: issueCreate(input:{i}){{ success issue{{ id identifier url title }} }}"
        for n, i in enumerate(inputs)
    )
    d = gql("mutation{ %s }" % partes)
    confere(d, "create")

    criados = []
    for n in range(len(inputs)):
        q = d[f"c{n}"]["issue"]
        cache["issues"][q["identifier"]] = q["id"]
        criados.append(q)
    gravar_cache(cache)
    return {"created": criados}


def cmd_update(args, cache):
    """Reescreve titulo, corpo, estado ou pai de tickets que ja existem.
    A triagem vive disso: o ticket nasce com o pedido cru e sai com a spec."""
    campos = []
    if args.title:
        campos.append(f"title:{json.dumps(args.title)}")
    corpo = texto_do({"body": args.body, "body_file": args.body_file})
    if corpo is not None:
        campos.append(f"description:{json.dumps(corpo)}")
    if args.state:
        campos.append(f'stateId:"{resolver(args.team or time_do(args.idents[0]), cache, "estado", args.state)}"')
    if args.parent is not None:
        # `--parent ""` desliga o vinculo. E o que a triagem faz quando promove
        # um ticket a pai e precisa que ele deixe de ser filho de outro.
        if args.parent == "":
            campos.append("parentId:null")
        else:
            campos.append(f'parentId:"{resolver_idents([args.parent], cache)[args.parent]}"')
    if not campos:
        raise Falha("informe ao menos um de --title, --body/--body-file, --state, --parent")

    uu = resolver_idents(args.idents, cache)
    entrada = "{" + ", ".join(campos) + "}"
    partes = " ".join(
        f'u{n}: issueUpdate(id:"{u}", input:{entrada}){{ success }}'
        for n, u in enumerate(uu.values())
    )
    d = gql("mutation{ %s }" % partes)
    confere(d, "update")
    return {"updated": args.idents}


def cmd_move(args, cache):
    uu = resolver_idents(args.idents, cache)
    team = args.team or time_do(args.idents[0])
    sid = resolver(team, cache, "estado", args.to)
    d = gql(
        "mutation{ issueBatchUpdate(ids:%s, input:{stateId:\"%s\"}){ success } }"
        % (json.dumps(list(uu.values())), sid)
    )
    confere(d, "move")
    return {"moved": args.idents, "to": args.to}


def cmd_comment(args, cache):
    corpo = texto_do({"body": args.body, "body_file": args.body_file})
    if not corpo:
        raise Falha("informe --body ou --body-file")
    uu = resolver_idents(args.idents, cache)
    partes = " ".join(
        f"k{n}: commentCreate(input:{{issueId:\"{u}\", body:{json.dumps(corpo)}}}){{ success }}"
        for n, u in enumerate(uu.values())
    )
    d = gql("mutation{ %s }" % partes)
    confere(d, "comment")
    return {"commented": args.idents}


def cmd_label(args, cache):
    if not args.add and not args.remove:
        raise Falha("informe --add e/ou --remove")
    uu = resolver_idents(args.idents, cache)
    partes = []
    for n, (ident, u) in enumerate(uu.items()):
        team = args.team or time_do(ident)
        for m_, l in enumerate(args.add):
            lid = resolver(team, cache, "etiqueta", l)
            partes.append(f'a{n}_{m_}: issueAddLabel(id:"{u}", labelId:"{lid}"){{ success }}')
        for m_, l in enumerate(args.remove):
            lid = resolver(team, cache, "etiqueta", l)
            partes.append(f'r{n}_{m_}: issueRemoveLabel(id:"{u}", labelId:"{lid}"){{ success }}')
    d = gql("mutation{ %s }" % " ".join(partes))
    confere(d, "label")
    return {"labeled": args.idents, "added": args.add, "removed": args.remove}


def cmd_cache(args, cache):
    if args.forget:
        cache = {"version": 1, "teams": {}, "issues": {}}
        gravar_cache(cache)
        return {"cache": "esquecido"}
    if args.refresh:
        if not args.team:
            raise Falha("informe --team para o --refresh")
        meta(args.team, cache, forcar=True)
    resumo = {
        t: {
            "estados": len(m["estados"]),
            "etiquetas": len(m["etiquetas"]) + len(m["qualificadas"]),
            "ambiguas": m["ambiguas"],
            "idade_s": int(time.time()) - m["buscado_em"],
        }
        for t, m in cache["teams"].items()
    }
    return {"arquivo": CACHE, "teams": resumo, "issues_em_cache": len(cache["issues"])}


def main():
    p = argparse.ArgumentParser(prog="linear.sh", description="escrita rapida no Linear")
    sub = p.add_subparsers(dest="verbo", required=True)

    c = sub.add_parser("create", help="cria um ticket, ou varios de uma vez")
    c.add_argument("--team")
    c.add_argument("--title")
    c.add_argument("--body")
    c.add_argument("--body-file", dest="body_file")
    c.add_argument("--state")
    c.add_argument("--label", action="append", default=[])
    c.add_argument("--parent")
    c.add_argument("--batch", help="arquivo JSON: lista de {title, body_file, state, labels, parent}")
    c.set_defaults(fn=cmd_create)

    m = sub.add_parser("move", help="move um ou varios tickets de estado")
    m.add_argument("--to", required=True)
    m.add_argument("--team")
    m.add_argument("idents", nargs="+")
    m.set_defaults(fn=cmd_move)

    u = sub.add_parser("update", help="reescreve titulo, corpo, estado ou pai")
    u.add_argument("--title")
    u.add_argument("--body")
    u.add_argument("--body-file", dest="body_file")
    u.add_argument("--state")
    u.add_argument("--parent", help='IDENT do pai, ou "" para desligar')
    u.add_argument("--team")
    u.add_argument("idents", nargs="+")
    u.set_defaults(fn=cmd_update)

    k = sub.add_parser("comment", help="comenta em um ou varios tickets")
    k.add_argument("--body")
    k.add_argument("--body-file", dest="body_file")
    k.add_argument("idents", nargs="+")
    k.set_defaults(fn=cmd_comment)

    l = sub.add_parser("label", help="acrescenta e remove etiquetas")
    l.add_argument("--add", action="append", default=[])
    l.add_argument("--remove", action="append", default=[])
    l.add_argument("--team")
    l.add_argument("idents", nargs="+")
    l.set_defaults(fn=cmd_label)

    ca = sub.add_parser("cache", help="inspeciona, atualiza ou esquece o cache")
    ca.add_argument("--refresh", action="store_true")
    ca.add_argument("--forget", action="store_true")
    ca.add_argument("--team")
    ca.set_defaults(fn=cmd_cache)

    args = p.parse_args()
    try:
        saida = args.fn(args, ler_cache())
    except Falha as e:
        print(f"linear: {e}", file=sys.stderr)
        return 1
    print(json.dumps(saida, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
