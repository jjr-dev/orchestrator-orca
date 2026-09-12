#!/usr/bin/env python3
"""Backend `orca`: registra o trabalho nas tasks do proprio Orca.

Fala o MESMO vocabulario do `bin/linear.sh` — os mesmos verbos, os mesmos nomes
de estado. Quem traduz e este arquivo, para que as skills nao precisem saber
qual backend esta ligado. Chame pelo `bin/board.sh`, nunca direto.

Tres coisas o Orca nao tem, e como cada uma e resolvida:

  etiquetas   `Repo/`, `Risk/` e `Stack/` viram uma linha de front-matter no
              topo da spec. E um comentario HTML: invisivel no markdown
              renderizado, trivial de parsear, e visivel na interface do Orca.
              Um so lugar, em vez de um indice paralelo para desincronizar.

  9 estados   colapsam em 5. Os estados extras do Linear existem para arrastar
              cartao; sem board eles nao se distinguem por nada que o sistema
              leia.

  comentario  vira uma secao `## Notas` no fim da propria spec, datada. O Orca
              nao tem fio de comentario por task, e inventar um arquivo lateral
              seria mais um lugar para divergir.

`In Progress` e o unico estado que este arquivo NAO grava: o Orca recusa a
transicao sem um Dispatch ativo. Isso e bom — significa que o status nao
consegue mentir sobre haver um worker rodando.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FRONT = re.compile(r"^<!--\s*orch\s+(.*?)\s*-->\s*$", re.M)
CAMPO = re.compile(r'(\w[\w-]*)="([^"]*)"|(\w[\w-]*)=(\S+)')

# nome do Linear -> o que fazer no Orca
ESTADOS = {
    "Draft":           ("status", "pending"),
    "Drafting":        ("status", "pending"),
    "Drafted":         ("gate",   None),        # portao aberto = esperando voce
    "Ready for Agent": ("liberar", "ready"),
    "Scheduled":       ("liberar", "ready"),
    "In Progress":     ("orca",   "dispatched"),
    "In Review":       ("status", "completed"),
    "Manual QA":       ("status", "completed"),
    "Done":            ("status", "completed"),
}


class Falha(Exception):
    pass


def orca(*args, entrada=None):
    p = subprocess.run(["orca", "orchestration", *args, "--json"],
                       capture_output=True, text=True, input=entrada)
    bruto = p.stdout.strip()
    if not bruto:
        raise Falha(f"orca nao respondeu: {p.stderr.strip()[:300]}")
    try:
        d = json.loads(bruto)
    except ValueError:
        raise Falha(f"resposta do orca nao e JSON: {bruto[:300]}")
    if not d.get("ok"):
        e = d.get("error") or {}
        raise Falha(e.get("message") or json.dumps(e)[:300])
    return d.get("result") or {}


def ler_front(spec):
    m = FRONT.search(spec or "")
    if not m:
        return {}
    d = {}
    for a, b, c, e in CAMPO.findall(m.group(1)):
        d[(a or c)] = b if a else e
    return d


def escrever_front(spec, campos):
    partes = " ".join(f'{k}="{v}"' for k, v in sorted(campos.items()) if v not in (None, ""))
    linha = f"<!-- orch {partes} -->" if partes else ""
    spec = spec or ""
    if FRONT.search(spec):
        return FRONT.sub(lambda _: linha, spec, count=1)
    return f"{linha}\n\n{spec}".lstrip() if linha else spec


def tasks():
    return orca("task-list")["tasks"]


def acha(ident):
    """Aceita o id do orca (task_xxx) ou o titulo exato. Nunca adivinha."""
    t = tasks()
    exato = [x for x in t if x["id"] == ident]
    if exato:
        return exato[0]
    por_titulo = [x for x in t if (x.get("task_title") or "") == ident]
    if len(por_titulo) == 1:
        return por_titulo[0]
    if len(por_titulo) > 1:
        raise Falha(f"'{ident}' casa com {len(por_titulo)} tasks — use o id task_xxx")
    raise Falha(f"task '{ident}' nao existe neste run")


def gate_aberto(task_id):
    for g in orca("gate-list")["gates"]:
        if g["task_id"] == task_id and g["status"] == "pending":
            return g
    return None


def cmd_create(a):
    itens = json.load(open(a.batch)) if a.batch else [{
        "title": a.title, "body": a.body, "body_file": a.body_file,
        "labels": a.label, "state": a.state, "parent": a.parent,
    }]
    if not itens:
        raise Falha("nada a criar")

    criadas = []
    for it in itens:
        if not it.get("title"):
            raise Falha("cada item precisa de title")
        corpo = it.get("body") or ""
        if it.get("body_file"):
            corpo = open(it["body_file"]).read()

        # As etiquetas do Linear viram front-matter. `Risk/` e `Repo/` chegam
        # como nome curto, igual ao Linear; o que distingue e a posicao na
        # chamada, nao um prefixo — por isso o risco e reconhecido por valor.
        campos, rotulos = {}, list(it.get("labels") or a.label or [])
        for l in rotulos:
            if l.lower() in ("high", "medium", "low"):
                campos["risk"] = l.lower()
            elif l == "Fast Track":
                campos["fast"] = "1"
            elif l == "Queue Jump":
                campos["queue-jump"] = "1"
            elif "/" in l:
                campos["stack"] = l
            else:
                campos["repo"] = l

        args = ["task-create", "--task-title", it["title"],
                "--display-name", it["title"],
                "--spec", escrever_front(corpo, campos)]
        pai = it.get("parent") or a.parent
        if pai:
            args += ["--parent", acha(pai)["id"]]

        t = orca(*args)["task"]
        estado = it.get("state") or a.state
        if estado:
            aplicar_estado(t["id"], estado)
        criadas.append({"id": t["id"], "identifier": t["id"], "title": it["title"]})
    return {"created": criadas}


def aplicar_estado(task_id, nome):
    if nome not in ESTADOS:
        raise Falha(f"estado '{nome}' nao existe.\n  existem: " + ", ".join(ESTADOS))
    modo, valor = ESTADOS[nome]

    if modo == "orca":
        return f"{nome}: o Orca marca sozinho quando o worker sobe; nao gravei"

    if modo == "gate":
        if gate_aberto(task_id):
            return f"{nome}: ja havia portao aberto"
        orca("gate-create", "--task", task_id,
             "--question", "Aprovar a spec e despachar?",
             "--options", '["aprovar","ajustar"]')
        return f"{nome}: portao aberto, task em blocked e fora da fila ready"

    if modo == "liberar":
        g = gate_aberto(task_id)
        if g:
            orca("gate-resolve", "--id", g["id"], "--resolution", "aprovar")
        orca("task-update", "--id", task_id, "--status", valor)
        return f"{nome}: {'portao resolvido, ' if g else ''}status ready"

    orca("task-update", "--id", task_id, "--status", valor)
    return f"{nome}: status {valor}"


def cmd_move(a):
    notas = [aplicar_estado(acha(i)["id"], a.to) for i in a.idents]
    return {"moved": a.idents, "to": a.to, "notas": notas}


def dir_rascunhos():
    d = os.path.join(RAIZ, "state", "drafts")
    os.makedirs(d, exist_ok=True)
    return d


def cmd_draft(a):
    """Guarda uma spec proposta, esperando aprovacao humana.

    No Orca a spec e IMUTAVEL depois da criacao — `task-update` so aceita
    `--status` e `--result`. Entao o rascunho nao pode nascer como task: ele
    viveria sem poder ser ajustado, e ajuste antes de aprovar e o proposito do
    portao. Fica em arquivo ate ser aprovado, e so ai vira task.
    """
    corpo = open(a.body_file).read() if a.body_file else (a.body or "")
    if not a.title or not corpo:
        raise Falha("informe --title e --body/--body-file")
    campos = {}
    for l in a.label or []:
        if l.lower() in ("high", "medium", "low"):
            campos["risk"] = l.lower()
        elif l == "Fast Track":
            campos["fast"] = "1"
        elif l == "Queue Jump":
            campos["queue-jump"] = "1"
        elif "/" in l:
            campos["stack"] = l
        else:
            campos["repo"] = l
    if a.parent:
        campos["parent"] = a.parent

    slug = a.slug or re.sub(r"[^a-z0-9]+", "-", a.title.lower()).strip("-")[:60]
    caminho = os.path.join(dir_rascunhos(), f"{slug}.md")
    with open(caminho, "w") as f:
        f.write(escrever_front(corpo, campos) + "\n")
    return {"drafted": [{"identifier": slug, "title": a.title, "arquivo": caminho}]}


def cmd_list_drafts(a):
    saida = []
    for nome in sorted(os.listdir(dir_rascunhos())):
        if not nome.endswith(".md"):
            continue
        caminho = os.path.join(dir_rascunhos(), nome)
        f = ler_front(open(caminho).read())
        saida.append({
            "identifier": nome[:-3], "arquivo": caminho,
            "repo": f.get("repo"), "risk": f.get("risk"), "stack": f.get("stack"),
            "parent": f.get("parent"),
            "queue_jump": f.get("queue-jump") == "1", "fast": f.get("fast") == "1",
            "idade_s": int(time.time() - os.path.getmtime(caminho)),
        })
    return {"drafts": saida}


def cmd_promote(a):
    """Aprovado: o rascunho vira task do Orca, ja na fila `ready`."""
    criadas = []
    for slug in a.idents:
        caminho = os.path.join(dir_rascunhos(), f"{slug}.md")
        if not os.path.exists(caminho):
            raise Falha(f"rascunho '{slug}' nao existe em {dir_rascunhos()}")
        spec = open(caminho).read()
        f = ler_front(spec)
        titulo = a.title or next(
            (l.lstrip("# ").strip() for l in spec.split("\n") if l.startswith("#")), slug)

        args = ["task-create", "--task-title", titulo, "--display-name", titulo, "--spec", spec]
        if f.get("parent"):
            args += ["--parent", acha(f["parent"])["id"]]
        t = orca(*args)["task"]
        orca("task-update", "--id", t["id"], "--status", "ready")
        os.replace(caminho, caminho + ".promovido")
        criadas.append({"identifier": t["id"], "title": titulo, "de": slug})
    return {"promoted": criadas}


def cmd_update(a):
    raise Falha(
        "o backend orca nao reescreve a spec de uma task existente: `task-update`\n"
        "  so aceita --status e --result.\n"
        "  ajuste ANTES de aprovar — o rascunho e um arquivo ate o `promote`.\n"
        "  para reescrever um rascunho, chame `draft` de novo com o mesmo --slug."
    )


def cmd_comment(a):
    """No-op honesto: sai 0, mas diz no stderr onde a informacao foi parar.

    Falhar aqui pararia o worker no meio por causa de um comentario, e
    comentario nao e o trabalho. Silenciar tambem nao serve — ninguem saberia
    que o registro mudou de lugar. Entao: nao interrompe, e nao esconde.
    """
    corpo = open(a.body_file).read() if a.body_file else (a.body or "")
    print(
        f"board(orca): comentario NAO gravado em {', '.join(a.idents)} "
        f"({len(corpo)} chars).\n"
        "  o orca nao tem fio de comentario por task. onde a informacao vive:\n"
        "    plano do worker    -> PLAN.md no worktree\n"
        "    veredito do review -> corpo do PR\n"
        "    relatorio final    -> o worker reporta e o orca grava em `result`",
        file=sys.stderr,
    )
    return {"commented": [], "ignorado": a.idents, "motivo": "backend orca nao tem comentario"}


def cmd_label(a):
    """Idem: as etiquetas sao front-matter gravado na criacao, e a spec e
    imutavel. Mexer depois nao existe, mas tambem nao quebra nada."""
    print(
        f"board(orca): etiqueta NAO alterada em {', '.join(a.idents)}"
        f"{' +' + ','.join(a.add) if a.add else ''}"
        f"{' -' + ','.join(a.remove) if a.remove else ''}.\n"
        "  no backend orca elas sao front-matter da spec, gravado na criacao.\n"
        "  para mudar, o caminho e recriar — normalmente nao vale.",
        file=sys.stderr,
    )
    return {"labeled": [], "ignorado": a.idents, "motivo": "front-matter e imutavel"}


def cmd_list(a):
    saida = []
    abertos = {g["task_id"] for g in orca("gate-list")["gates"] if g["status"] == "pending"}
    for t in tasks():
        f = ler_front(t.get("spec"))
        saida.append({
            "identifier": t["id"], "title": t.get("task_title"),
            "status": t["status"], "parent": t.get("parent_id"),
            "esperando_aprovacao": t["id"] in abertos,
            "repo": f.get("repo"), "risk": f.get("risk"), "stack": f.get("stack"),
            "queue_jump": f.get("queue-jump") == "1", "fast": f.get("fast") == "1",
        })
    if a.state:
        alvo = ESTADOS.get(a.state)
        if not alvo:
            raise Falha(f"estado '{a.state}' nao existe")
        if a.state == "Drafted":
            saida = [x for x in saida if x["esperando_aprovacao"]]
        else:
            saida = [x for x in saida if x["status"] == alvo[1] and not x["esperando_aprovacao"]]
    return {"issues": saida}


def main():
    p = argparse.ArgumentParser(prog="orca-board", description="backend orca")
    sub = p.add_subparsers(dest="verbo", required=True)

    c = sub.add_parser("create"); c.add_argument("--team"); c.add_argument("--title")
    c.add_argument("--body"); c.add_argument("--body-file", dest="body_file")
    c.add_argument("--state"); c.add_argument("--label", action="append", default=[])
    c.add_argument("--parent"); c.add_argument("--batch"); c.set_defaults(fn=cmd_create)

    m = sub.add_parser("move"); m.add_argument("--to", required=True)
    m.add_argument("--team"); m.add_argument("idents", nargs="+"); m.set_defaults(fn=cmd_move)

    u = sub.add_parser("update"); u.add_argument("--title"); u.add_argument("--body")
    u.add_argument("--body-file", dest="body_file"); u.add_argument("--state")
    u.add_argument("--parent"); u.add_argument("--team")
    u.add_argument("idents", nargs="+"); u.set_defaults(fn=cmd_update)

    k = sub.add_parser("comment"); k.add_argument("--body")
    k.add_argument("--body-file", dest="body_file")
    k.add_argument("idents", nargs="+"); k.set_defaults(fn=cmd_comment)

    l = sub.add_parser("label"); l.add_argument("--add", action="append", default=[])
    l.add_argument("--remove", action="append", default=[]); l.add_argument("--team")
    l.add_argument("idents", nargs="+"); l.set_defaults(fn=cmd_label)

    d = sub.add_parser("draft"); d.add_argument("--title"); d.add_argument("--body")
    d.add_argument("--body-file", dest="body_file"); d.add_argument("--slug")
    d.add_argument("--label", action="append", default=[]); d.add_argument("--parent")
    d.add_argument("--team"); d.set_defaults(fn=cmd_draft)

    ld = sub.add_parser("list-drafts"); ld.add_argument("--team"); ld.set_defaults(fn=cmd_list_drafts)

    pr = sub.add_parser("promote"); pr.add_argument("--title"); pr.add_argument("--team")
    pr.add_argument("idents", nargs="+"); pr.set_defaults(fn=cmd_promote)

    s = sub.add_parser("list"); s.add_argument("--team"); s.add_argument("--state")
    s.set_defaults(fn=cmd_list)

    a = p.parse_args()
    try:
        print(json.dumps(a.fn(a), indent=2, ensure_ascii=False))
    except Falha as e:
        print(f"board(orca): {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
