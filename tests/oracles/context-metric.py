"""Oráculo independiente de tools/context-metric.ps1.

Calcula lo mismo que la métrica por otro camino (Python sobre `git show`, sin compartir código con la
función bajo prueba) y de acá salen los literales congelados de tests/context-metric.tests.ps1.
No corre en la suite: se corre a mano cuando hay que regrabar un literal.

    python tests/oracles/context-metric.py <ref> [personal|southpoint|ai]
"""
import subprocess
import sys

ref = sys.argv[1]
variant = sys.argv[2] if len(sys.argv) > 2 else "personal"
root = f"skills/bootstrap-{variant}-project/assets/scaffold"


def show(path):
    raw = subprocess.check_output(["git", "show", f"{ref}:{path}"]).decode("utf-8")
    return raw.lstrip("﻿").replace("\r\n", "\n").replace("\r", "\n")


def ls(path):
    r = subprocess.run(["git", "ls-tree", "-r", "--name-only", f"{ref}:{path}"],
                       capture_output=True, text=True)
    return r.stdout.split() if r.returncode == 0 else []


def frontmatter(text):
    lines = text.split("\n")
    return lines[1:lines.index("---", 1)]


def description(fm):
    return [l for l in fm if l.startswith("description:")][0][len("description:"):].strip()


claude_md = len(show(f"{root}/CLAUDE.md"))
commands = loaded = flagged = 0
for name in ls(f"{root}/.claude/commands"):
    fm = frontmatter(show(f"{root}/.claude/commands/{name}"))
    if any(l.split(":", 1)[0] == "disable-model-invocation" and l.split(":", 1)[1].strip() == "true"
           for l in fm):
        flagged += 1
        continue
    commands += len(description(fm))
    loaded += 1
agents = n_agents = 0
for name in ls(f"{root}/.claude/agents"):
    agents += len(description(frontmatter(show(f"{root}/.claude/agents/{name}"))))
    n_agents += 1

print(f"{ref} {variant}: CLAUDE.md {claude_md} | comandos {commands} ({loaded} cargan, {flagged} con el flag)"
      f" | agents {agents} ({n_agents}) | total {claude_md + commands + agents}")
