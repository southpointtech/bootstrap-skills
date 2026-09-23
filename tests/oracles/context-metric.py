"""Oráculo independiente de tools/context-metric.ps1.

Calcula lo mismo que la métrica por otro camino (Python sobre `git show`, sin compartir código con la
función bajo prueba) y de acá salen los literales congelados de tests/context-metric.tests.ps1.
Rechaza las formas de frontmatter que rechazan los fixtures `Tira` de la suite (comillas, bloque,
vacía, comentario, continuación, repetida, sin apertura o sin cierre); más allá de eso no se probó.
No corre en la suite: se corre a mano cuando hay que regrabar un literal.

    python tests/oracles/context-metric.py <ref> [personal|southpoint|ai]
"""
import re
import subprocess
import sys


class Rechazo(Exception):
    """Una forma que la métrica no mide. No es `assert`: `python -O` borra los asserts."""


def need(cond, msg):
    if not cond:
        raise Rechazo(msg)


def normalize(raw):
    return raw.lstrip("﻿").replace("\r\n", "\n").replace("\r", "\n")


def frontmatter(text):
    lines = text.split("\n")
    need(lines[0] == "---", "no arranca con frontmatter")
    need("---" in lines[1:], "el frontmatter no cierra")
    return lines[1:lines.index("---", 1)]


def field(fm, key):
    """Valor plano de una línea de `key`, o None si no está."""
    hits = [i for i, l in enumerate(fm) if l.startswith(key + ":")]
    if not hits:
        return None
    need(len(hits) == 1, f"{key} repetida")
    value = fm[hits[0]][len(key) + 1:].strip()
    need(value and value[0] not in "\"'>|", f"{key} no plana")
    need(not re.search(r"(^|\s)#", value), f"{key} con comentario")
    following = [l for l in fm[hits[0] + 1:] if l.strip()]
    need(not (following and re.match(r"\s+#", following[0])), f"{key} con comentario en la línea siguiente")
    need(not (following and following[0][:1].isspace()), f"{key} que sigue en otra línea")
    return value


def description(fm):
    value = field(fm, "description")
    need(value is not None, "sin description")
    return value


def command(text):
    """Description de un comando que carga, o None si lleva el flag."""
    fm = frontmatter(normalize(text))
    flag = field(fm, "disable-model-invocation")
    if flag is not None and flag.lower() == "true":
        return None
    return description(fm)


def agent(text):
    return description(frontmatter(normalize(text)))


def check_no_skills(names):
    need(not names, ".claude/skills no se mide")


def main(ref, variant):
    root = f"skills/bootstrap-{variant}-project/assets/scaffold"

    def show(path):
        return subprocess.check_output(["git", "show", f"{ref}:{path}"]).decode("utf-8")

    def ls_all(path):
        r = subprocess.run(["git", "ls-tree", "-r", "-z", "--name-only", f"{ref}:{path}"], capture_output=True)
        return [n.decode("utf-8") for n in r.stdout.split(b"\0") if n] if r.returncode == 0 else []

    def ls(path):
        return [n for n in ls_all(path) if n.lower().endswith(".md")]

    # Cualquier archivo, no solo .md: la métrica tira ante todo lo que haya bajo .claude/skills/.
    check_no_skills(ls_all(f"{root}/.claude/skills"))
    claude_md = len(normalize(show(f"{root}/CLAUDE.md")))
    commands = loaded = flagged = 0
    for name in ls(f"{root}/.claude/commands"):
        d = command(show(f"{root}/.claude/commands/{name}"))
        if d is None:
            flagged += 1
            continue
        commands += len(d)
        loaded += 1
    agents = n_agents = 0
    for name in ls(f"{root}/.claude/agents"):
        agents += len(agent(show(f"{root}/.claude/agents/{name}")))
        n_agents += 1

    print(f"{ref} {variant}: CLAUDE.md {claude_md} | comandos {commands} ({loaded} cargan, {flagged} con el flag)"
          f" | agents {agents} ({n_agents}) | total {claude_md + commands + agents}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "personal")
