#!/usr/bin/env python3
"""Porta unica de escrita no registry.yaml.

Nenhuma skill edita o registry direto. Todas passam por aqui, e por um motivo
concreto: 33% do arquivo e comentario, e os comentarios sao a auditoria. Sao
eles que dizem por que `implementer_fallback` e o ajuste mais caro, por que
`base` precisa do prefixo `origin/`, por que Fable saiu. Um round-trip por
`yaml.safe_load` + `yaml.dump` apaga os 183 e devolve um arquivo de 343 linhas
que parseia igual e nao ensina mais nada.

Por isso a escrita e TEXTUAL, nunca reserializacao:

    1. le como texto
    2. ancora com match unico exigido      <- ambiguidade e erro, nao palpite
    3. insere ou troca preservando indentacao
    4. valida: yaml.safe_load no resultado
    5. diff semantico: o dict novo difere do velho EXATAMENTE onde se pediu
    6. so entao grava

O passo 5 e o que existe. Sem ele uma ancora errada corrompe o arquivo de um
jeito que continua sendo YAML valido — a falha caracteristica deste projeto,
que nao levanta erro e so aparece semanas depois.

Uso:
    registry-edit.py add-repo    --company acme --name "Acme - API" ...
    registry-edit.py rm-repo     --name "Acme - API"
    registry-edit.py add-company --key acme --linear-team ACME [--wip-max 3]
    registry-edit.py set-model   --role implementer_by_risk.medium --model opus --effort high
    registry-edit.py show        [--json]

Toda operacao aceita --dry-run: imprime o diff e nao grava.
"""

import argparse
import difflib
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.exit("registry-edit: falta pyyaml (python3 -m pip install pyyaml)")


RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REGISTRY = os.path.join(RAIZ, "registry.yaml")
EXEMPLO = os.path.join(RAIZ, "registry.example.yaml")


class Recusa(Exception):
    """Erro que aborta sem gravar. A mensagem vai para o humano."""


# --------------------------------------------------------------------------
# leitura


def ler(caminho=None):
    caminho = caminho or REGISTRY
    if not os.path.exists(caminho):
        raise Recusa(
            f"{os.path.basename(caminho)} nao existe.\n"
            f"Rode /orchestrator-setup, ou copie do template:\n"
            f"    cp {os.path.basename(EXEMPLO)} {os.path.basename(caminho)}"
        )
    with open(caminho, encoding="utf-8") as fh:
        return fh.read()


def carregar(texto):
    try:
        d = yaml.safe_load(texto)
    except yaml.YAMLError as e:
        raise Recusa(f"registry.yaml nao e YAML valido:\n{e}")
    if not isinstance(d, dict):
        raise Recusa("registry.yaml nao contem um mapa no topo")
    return d


# --------------------------------------------------------------------------
# diff semantico: o coracao da seguranca


def achatar(obj, prefixo=""):
    """Reduz o dict a {caminho: valor-folha}, para comparar por chave."""
    saida = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            saida.update(achatar(v, f"{prefixo}.{k}" if prefixo else str(k)))
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            saida.update(achatar(v, f"{prefixo}[{i}]"))
    else:
        saida[prefixo] = obj
    return saida


def mudancas(antes, depois):
    a, b = achatar(antes), achatar(depois)
    return {
        "removidos": sorted(set(a) - set(b)),
        "adicionados": sorted(set(b) - set(a)),
        "alterados": sorted(k for k in set(a) & set(b) if a[k] != b[k]),
    }


def exigir_escopo(antes, depois, prefixos):
    """Aborta se algo mudou FORA dos prefixos pretendidos.

    E aqui que uma ancora errada morre. Sem esta checagem, um regex que casou
    no lugar errado produz um YAML perfeitamente valido e semanticamente
    destruido, e ninguem descobre no mesmo dia.
    """
    m = mudancas(antes, depois)
    fora = [
        k
        for grupo in m.values()
        for k in grupo
        if not any(k == p or k.startswith(p + ".") or k.startswith(p + "[") for p in prefixos)
    ]
    if fora:
        raise Recusa(
            "ABORTADO: a edicao mexeu onde nao devia.\n"
            f"  pretendido: {', '.join(prefixos)}\n"
            "  mexeu tambem em:\n"
            + "\n".join(f"    - {k}" for k in fora[:15])
            + ("\n    ..." if len(fora) > 15 else "")
            + "\n\nNada foi gravado. Isso e bug do registry-edit, nao do seu comando."
        )
    return m


# --------------------------------------------------------------------------
# gravacao


def gravar(texto_antigo, texto_novo, prefixos, dry_run, caminho=None, comentarios_removiveis=0):
    """Grava se, e so se, a edicao ficou dentro do que se pediu.

    `comentarios_removiveis` e a franquia de comentarios que a operacao tem
    direito de apagar — os que moram DENTRO do bloco que ela remove. Uma
    remocao de repo leva junto os comentarios daquele repo, e isso e correto;
    o que o guard existe para impedir e perder comentario de outro lugar.
    """
    caminho = caminho or REGISTRY
    antes = carregar(texto_antigo)
    depois = carregar(texto_novo)          # passo 4: ainda e YAML?
    m = exigir_escopo(antes, depois, prefixos)   # passo 5: so onde eu pedi?

    if not any(m.values()):
        print("nada a fazer: o registry ja esta nesse estado")
        return False

    diff = list(
        difflib.unified_diff(
            texto_antigo.splitlines(keepends=True),
            texto_novo.splitlines(keepends=True),
            fromfile="registry.yaml",
            tofile="registry.yaml (novo)",
            n=2,
        )
    )
    sys.stdout.write("".join(diff))

    perdidos = texto_antigo.count("#") - texto_novo.count("#") - comentarios_removiveis
    if perdidos > 0:
        raise Recusa(
            f"ABORTADO: a edicao apagaria {perdidos} comentario(s) fora do bloco alvo.\n"
            "Os comentarios sao a auditoria deste arquivo. Nada foi gravado."
        )

    if dry_run:
        print("\n--dry-run: nada gravado")
        return False

    tmp = caminho + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(texto_novo)
    os.replace(tmp, caminho)
    print(f"\ngravado em {os.path.basename(caminho)}")
    return True


# --------------------------------------------------------------------------
# ancoragem


def bloco_da_empresa(texto, chave):
    """Devolve (inicio, fim) do corpo de uma empresa dentro de `companies:`."""
    m = list(re.finditer(rf"^  {re.escape(chave)}:[ \t]*$", texto, re.M))
    if not m:
        raise Recusa(f"empresa '{chave}' nao existe no registry")
    if len(m) > 1:
        raise Recusa(f"empresa '{chave}' aparece {len(m)} vezes — arquivo inconsistente")
    ini = m[0].end()
    resto = texto[ini:]
    prox = re.search(r"^  \S", resto, re.M)      # proxima empresa (indent 2)
    return ini, ini + (prox.start() if prox else len(resto))


def indentacao_dos_repos(corpo):
    m = re.search(r"^(\s+)repos:[ \t]*$", corpo, re.M)
    if not m:
        raise Recusa("bloco 'repos:' nao encontrado nesta empresa")
    return m.end(), len(m.group(1))


# --------------------------------------------------------------------------
# operacoes


def op_add_repo(a):
    texto = ler()
    d = carregar(texto)

    for emp, dados in (d.get("companies") or {}).items():
        if a.name in (dados.get("repos") or {}):
            raise Recusa(f"o repo '{a.name}' ja existe na empresa '{emp}'")
    if a.company not in (d.get("companies") or {}):
        raise Recusa(
            f"empresa '{a.company}' nao existe. Crie antes:\n"
            f"    registry-edit.py add-company --key {a.company} --linear-team <TEAM>"
        )
    if not a.base.startswith("origin/"):
        raise Recusa(
            f"base '{a.base}' nao comeca com 'origin/'.\n"
            "Sem o prefixo o Orca usa a ref LOCAL sem tocar na rede, e o worker\n"
            "implementa em cima de codigo velho. O /pull-ready recusa despachar\n"
            "repo assim. Use 'origin/{}'.".format(a.base)
        )

    ini, fim = bloco_da_empresa(texto, a.company)
    fim_repos, ind = indentacao_dos_repos(texto[ini:fim])
    ponto = ini + fim_repos

    p = " " * (ind + 2)
    linhas = [
        "",
        f'{p}"{a.name}":',
        f"{p}  slug: {a.slug}",
        f"{p}  orca_repo_id: {a.orca_repo_id}",
        f"{p}  base: {a.base}",
        f"{p}  setup: {a.setup}",
        f"{p}  gate: []                     # politica: o agente nao executa nada",
        f"{p}  manual:                      # roteiro humano; o agente so transcreve no PR",
    ]
    linhas += [f"{p}    - {c}" for c in (a.manual or ["# preencha o roteiro de verificacao"])]
    linhas.append(f"{p}  ci: {a.ci}")
    if a.pair:
        linhas.append(f'{p}  pair: "{a.pair}"')
    linhas.append(f"{p}  plan_gate: false")
    linhas.append(f"{p}  risk_default: {a.risk_default}")

    novo = texto[:ponto] + "\n".join(linhas) + "\n" + texto[ponto:]
    return gravar(texto, novo, [f"companies.{a.company}.repos.{a.name}"], a.dry_run)


def op_rm_repo(a):
    texto = ler()
    d = carregar(texto)
    dona = next(
        (e for e, v in (d.get("companies") or {}).items() if a.name in (v.get("repos") or {})),
        None,
    )
    if not dona:
        raise Recusa(f"repo '{a.name}' nao existe no registry")

    m = list(re.finditer(rf'^(\s+)"{re.escape(a.name)}":[ \t]*$', texto, re.M))
    if len(m) != 1:
        raise Recusa(f"a chave do repo '{a.name}' casou {len(m)} vezes — nao vou adivinhar")
    ind = len(m[0].group(1))
    ini = m[0].start()
    resto = texto[m[0].end() :]
    prox = re.search(rf"^ {{0,{ind}}}\S", resto, re.M)
    fim = m[0].end() + (prox.start() if prox else len(resto))

    removido = texto[ini:fim]
    novo = texto[:ini] + texto[fim:]
    return gravar(
        texto,
        novo,
        [f"companies.{dona}.repos.{a.name}"],
        a.dry_run,
        comentarios_removiveis=removido.count("#"),
    )


def op_add_company(a):
    texto = ler()
    d = carregar(texto)
    if a.key in (d.get("companies") or {}):
        raise Recusa(f"empresa '{a.key}' ja existe")

    m = re.search(r"^companies:[ \t]*$", texto, re.M)
    if not m:
        raise Recusa("bloco 'companies:' nao encontrado")

    bloco = (
        f"\n  {a.key}:\n"
        f"    linear_team: {a.linear_team}\n"
        f"    wip_max: {a.wip_max}\n"
        f"    repos:\n"
    )
    novo = texto[: m.end()] + "\n" + bloco.rstrip("\n") + "\n" + texto[m.end() :].lstrip("\n")
    return gravar(texto, novo, [f"companies.{a.key}"], a.dry_run)


def op_set_model(a):
    texto = ler()
    partes = a.role.split(".")
    chave = partes[-1]

    if len(partes) == 2 and partes[0] == "implementer_by_risk":
        if chave not in ("high", "medium", "low"):
            raise Recusa("nivel de risco deve ser high, medium ou low")
        alvo = rf"^(\s+){re.escape(chave)}:(\s*)\{{[^}}]*\}}[ \t]*$"
        m = list(re.finditer(alvo, texto, re.M))
        if len(m) != 1:
            raise Recusa(f"'{a.role}' casou {len(m)} vezes — esperava exatamente 1")
        ind, esp = m[0].group(1), m[0].group(2)
        linha = f"{ind}{chave}:{esp}{{ model: {a.model}, effort: {a.effort} }}"
        novo = texto[: m[0].start()] + linha + texto[m[0].end() :]
        prefixo = f"defaults.models.implementer_by_risk.{chave}"
    else:
        if not a.model:
            raise Recusa(f"papel '{a.role}' recebe so --model")
        m = list(re.finditer(rf"^(\s+){re.escape(chave)}:[ \t]+(\S+)[ \t]*$", texto, re.M))
        if len(m) != 1:
            raise Recusa(f"'{chave}' casou {len(m)} vezes — esperava exatamente 1")
        linha = f"{m[0].group(1)}{chave}: {a.model}"
        novo = texto[: m[0].start()] + linha + texto[m[0].end() :]
        prefixo = f"defaults.models.{chave}"

    return gravar(texto, novo, [prefixo], a.dry_run)


def op_show(a):
    d = carregar(ler())
    if a.json:
        import json

        print(json.dumps(d, indent=2, ensure_ascii=False))
        return False

    m = (d.get("defaults") or {}).get("models") or {}
    print("modelos por papel")
    for papel in ("orchestrator", "planner", "reviewer", "gate_runner"):
        if papel in m:
            print(f"  {papel:22s} {m[papel]}  (effort: global)")
    for nivel, v in (m.get("implementer_by_risk") or {}).items():
        v = v if isinstance(v, dict) else {"model": v}
        print(f"  implementar/{nivel:9s} {v.get('model')}/{v.get('effort', 'global')}")
    fb = m.get("implementer_fallback")
    fb = fb if isinstance(fb, dict) else {"model": fb}
    print(f"  {'implementar/fallback':22s} {fb.get('model')}/{fb.get('effort', 'global')}")

    print("\nempresas e repos")
    for emp, v in (d.get("companies") or {}).items():
        repos = v.get("repos") or {}
        print(f"  {emp}  (time {v.get('linear_team')}, wip_max {v.get('wip_max')}, {len(repos)} repos)")
        for nome, r in repos.items():
            aviso = "" if str(r.get("base", "")).startswith("origin/") else "   <- base SEM origin/ !"
            print(f"      {nome:32s} {r.get('base')}{aviso}")
    return False


# --------------------------------------------------------------------------


def main():
    p = argparse.ArgumentParser(prog="registry-edit.py", description=__doc__.split("\n")[0])
    p.add_argument("--dry-run", action="store_true", help="imprime o diff e nao grava")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("add-repo")
    s.add_argument("--company", required=True)
    s.add_argument("--name", required=True, help="identico ao nome da etiqueta Repo/ no Linear")
    s.add_argument("--slug", required=True)
    s.add_argument("--orca-repo-id", dest="orca_repo_id", required=True)
    s.add_argument("--base", required=True, help="com o prefixo origin/")
    s.add_argument("--setup", default="npm ci")
    s.add_argument("--ci", default="github")
    s.add_argument("--pair")
    s.add_argument("--risk-default", dest="risk_default", default="medium",
                   choices=["high", "medium", "low"])
    s.add_argument("--manual", nargs="*")
    s.set_defaults(fn=op_add_repo)

    s = sub.add_parser("rm-repo")
    s.add_argument("--name", required=True)
    s.set_defaults(fn=op_rm_repo)

    s = sub.add_parser("add-company")
    s.add_argument("--key", required=True)
    s.add_argument("--linear-team", dest="linear_team", required=True)
    s.add_argument("--wip-max", dest="wip_max", type=int, default=3)
    s.set_defaults(fn=op_add_company)

    s = sub.add_parser("set-model")
    s.add_argument("--role", required=True,
                   help="orchestrator | planner | reviewer | implementer_by_risk.<nivel>")
    s.add_argument("--model")
    s.add_argument("--effort", choices=["low", "medium", "high", "xhigh", "max"])
    s.set_defaults(fn=op_set_model)

    s = sub.add_parser("show")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=op_show)

    a = p.parse_args()
    try:
        a.fn(a)
    except Recusa as e:
        print(f"\n{e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
