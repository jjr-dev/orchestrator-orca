#!/usr/bin/env python3
"""Gera o prompt do orch-planner / orch-reviewer. Chame pelo subagent-prompt.sh."""

import json
import os
import subprocess
import sys

RAIZ = os.environ["ORCH_SUBAGENT_RAIZ"]
WT = os.environ["ORCH_SUBAGENT_WT"]
PAPEL = os.environ["ORCH_SUBAGENT_PAPEL"]
IDENT = os.environ["ORCH_SUBAGENT_IDENT"]
REPO = os.environ.get("ORCH_SUBAGENT_REPO") or ""


def sh(*args, entrada=None):
    p = subprocess.run(args, capture_output=True, text=True, input=entrada, cwd=RAIZ)
    return p.stdout.strip(), p.returncode


def registry():
    import yaml
    with open(os.path.join(RAIZ, "registry.yaml")) as f:
        return yaml.safe_load(f) or {}


def backend():
    out, rc = sh(os.path.join(RAIZ, "bin/backend.sh"))
    return out if rc == 0 else "linear"


def ticket():
    """(titulo, spec, {repo, risk}) pelo `board.sh show`, que normaliza os dois
    backends. Assim este arquivo nao precisa saber qual esta ligado."""
    out, rc = sh(os.path.join(RAIZ, "bin/board.sh"), "show", IDENT)
    if rc != 0 or not out:
        return IDENT, "", {}
    i = (json.loads(out).get("issue")) or {}
    rot = {}
    if i.get("repo"):
        rot["repo"] = i["repo"]
    if i.get("risk"):
        rot["risk"] = i["risk"]

    # No linear as etiquetas voltam como lista PLANA, sem o grupo — o `parent`
    # so aparece na consulta GraphQL crua. O grupo e deduzido: risco pelo
    # conjunto fechado de niveis, repo por casamento com as chaves do registry,
    # que ja e a fonte da verdade desses nomes.
    if i.get("labels"):
        d_reg = registry()
        repos = {n for e in (d_reg.get("companies") or {}).values()
                 for n in (e.get("repos") or {})}
        for nome in i["labels"]:
            if nome in ("high", "medium", "low"):
                rot.setdefault("risk", nome)
            elif nome in repos:
                rot.setdefault("repo", nome)
    return i.get("title") or IDENT, i.get("spec") or "", rot


def stack_do_repo():
    """Uma linha sobre a stack, detectada do disco. Barato e deterministico —
    o registry nao guarda isso, e sem ela o planner gasta um turno descobrindo."""
    def tem(x):
        return os.path.exists(os.path.join(WT, x))
    if tem("composer.json"):
        return "PHP / Laravel"
    if tem("package.json"):
        try:
            with open(os.path.join(WT, "package.json")) as f:
                d = json.load(f)
            dep = {**(d.get("dependencies") or {}), **(d.get("devDependencies") or {})}
            for chave, nome in (("expo", "Expo / React Native"), ("next", "Next.js"),
                                ("react-native", "React Native"), ("react", "React"),
                                ("vue", "Vue")):
                if chave in dep:
                    return nome
        except Exception:
            pass
        return "Node / JavaScript"
    if tem("pubspec.yaml"):
        return "Flutter"
    if tem("go.mod"):
        return "Go"
    return "stack nao detectada"


def conf_do_repo(nome):
    d = registry()
    for e in (d.get("companies") or {}).values():
        r = (e.get("repos") or {}).get(nome)
        if r:
            return r
    return {}


def tem_imagem(spec):
    """Imagem no Linear e link markdown para uploads.linear.app dentro da
    descricao. Olhar o texto que ja temos evita uma chamada de rede."""
    return "uploads.linear.app" in (spec or "")


titulo, spec, rot = ticket()
repo = REPO or rot.get("repo") or ""
risco = rot.get("risk") or (conf_do_repo(repo).get("risk_default") if repo else "") or "nao declarado"
c = conf_do_repo(repo)
gate = c.get("gate") or []
manual = c.get("manual") or []
imgs = tem_imagem(spec)

cab = [
    f"IDENT: {IDENT}",
    f"Worktree (raiz absoluta, trabalhe SO aqui): {WT}",
    f"Repo: {repo or '(nao resolvido)'} ({stack_do_repo()})",
    f"Base branch: {c.get('base', '(nao declarada)')}",
    f"Risco: {risco}",
    "Anexos de imagem: " + ("SIM — rode "
        f"{os.path.join(RAIZ, 'bin/linear-assets.sh')} {IDENT} e abra cada arquivo "
        "com o Read antes de decidir qualquer coisa" if imgs else "nenhum"),
]

regras = [
    "- NAO execute comando nenhum do projeto (lint, build, teste, instalar",
    "  dependencia, servidor de dev, migration). Leia codigo, nao rode.",
]
if gate:
    regras.append(f"- O `gate` deste repo roda depois: {', '.join('`%s`' % g for g in gate)}.")
else:
    regras.append("- O `gate` deste repo esta VAZIO: nao existe verificacao automatica.")
    regras.append("  A verificacao e humana, pelo roteiro do PR.")
if manual:
    regras.append(f"- Roteiro humano declarado no registry: {', '.join('`%s`' % m for m in manual)}.")

if PAPEL == "planner":
    regras.append(f"- Nao edite nenhum arquivo de codigo. Seu unico output em disco e {WT}/PLAN.md")
    abertura = "Escreva o PLAN.md para o ticket abaixo."
else:
    regras.append("- Nao edite nada. Voce so le o diff e devolve o veredito.")
    regras.append("- Nao rode o gate: quem roda e o worker, no passo dele.")
    abertura = (
        "Revise, com contexto limpo, o diff ja aplicado neste worktree contra o\n"
        "ticket abaixo. Devolva o veredito: aprovado, aprovado com ressalvas, ou\n"
        "reprovado com os bloqueantes, um por linha."
    )

print(abertura)
print()
print("\n".join(cab))
print()
print("Regras de ambiente que valem para voce tambem:")
print("\n".join(regras))
print()
print("=== ESPECIFICACAO COMPLETA DO TICKET ===")
print()
print(f"Ticket: {IDENT} — {titulo}")
print()
print(spec.strip() or "(sem descricao no ticket)")
