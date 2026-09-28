"""Un `claude` falso para los tests de `correr`: nunca el real, nunca la red.

Lee su guion de `$GUION_FALSO` (un JSON con una lista de pasos, uno por invocación) y lleva la
cuenta en `n.txt` junto al guion. Cada invocación deja en `llamadas.jsonl` (junto al guion) lo que
vio: argv, prompt (stdin), cwd, `CLAUDE_CONFIG_DIR`, qué había en la config, la huella de la
credencial, las variables `CLAUDE*` del entorno y si había `PREGUNTAS.md`.

Un paso: `session_id`, `exit` (default 0), `preguntas` (texto de `PREGUNTAS.md` o null),
`worktree` (nombre de un carril, o una lista: los abre a la vez, les escribe `.scratch/`, espera
`espera` segundos y los borra, como el paso 8 de PARALELISMO.md), `estados` (los textos sucesivos
del issue del carril, con `espera` segundos entre uno y otro; default `["Status: done\n"]`),
`queda` (true: los carriles no se borran al terminar la sesión), `como_el_scaffold` (true:
abre los carriles donde los abre `abrir-carril.ps1`, `<padre>/carriles/<repo>/<nombre>`; si
no, en `.claude/worktrees/<nombre>`).
"""
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

guion_ruta = Path(os.environ["GUION_FALSO"])
pasos = json.loads(guion_ruta.read_text(encoding="utf-8"))
contador = guion_ruta.parent / "n.txt"
n = int(contador.read_text()) if contador.exists() else 0
contador.write_text(str(n + 1))
paso = pasos[min(n, len(pasos) - 1)]

cfg = Path(os.environ["CLAUDE_CONFIG_DIR"])
cwd = Path.cwd()
cred = cfg / ".credentials.json"
llamada = {
    "argv": sys.argv[1:],
    "prompt": sys.stdin.buffer.read().decode("utf-8"),
    "cwd": str(cwd),
    "config_dir": str(cfg),
    "config": sorted(p.relative_to(cfg).as_posix() for p in cfg.rglob("*")),
    "credencial_sha256": hashlib.sha256(cred.read_bytes()).hexdigest() if cred.exists() else None,
    "claude_env": sorted(k for k in os.environ if k.upper().startswith("CLAUDE")),
    "habia_preguntas": (cwd / "PREGUNTAS.md").exists(),
}
with open(guion_ruta.parent / "llamadas.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps(llamada, ensure_ascii=False) + "\n")

sid = paso["session_id"]
proyectos = cfg / "projects" / "C--falso-proyecto"
proyectos.mkdir(parents=True, exist_ok=True)
with open(proyectos / f"{sid}.jsonl", "a", encoding="utf-8") as f:
    f.write(json.dumps({"timestamp": f"2026-09-24T12:00:0{n}Z", "sesion": n + 1}) + "\n")
sub = proyectos / sid / "subagents"
sub.mkdir(parents=True, exist_ok=True)
(sub / f"agent-{n + 1}.jsonl").write_text('{"timestamp": "2026-09-24T12:00:00Z"}\n', encoding="utf-8")

if paso.get("worktree"):
    nombres = paso["worktree"] if isinstance(paso["worktree"], list) else [paso["worktree"]]
    estados = paso.get("estados", ["Status: done\n"])
    espera = paso.get("espera", 1.0)
    raiz = (cwd.parent / "carriles" / cwd.name if paso.get("como_el_scaffold")
            else cwd / ".claude" / "worktrees")
    wts = [raiz / nombre for nombre in nombres]
    for nombre, wt in zip(nombres, wts):
        subprocess.run(["git", "-C", str(cwd), "worktree", "add", "-q", "-b", nombre, str(wt)],
                       check=True, capture_output=True)
        (wt / ".scratch" / "issues").mkdir(parents=True)
        carril = cfg / "projects" / f"C--falso-{nombre}"
        carril.mkdir(parents=True, exist_ok=True)
        (carril / "carril.jsonl").write_text('{"timestamp": "2026-09-24T12:00:05Z"}\n',
                                             encoding="utf-8")
    for i, estado in enumerate(estados):
        if i:
            time.sleep(espera)
        for wt in wts:
            (wt / ".scratch" / "issues" / "01.md").write_text(estado, encoding="utf-8")
    time.sleep(espera)
    for wt in ([] if paso.get("queda") else wts):
        subprocess.run(["git", "-C", str(cwd), "worktree", "remove", "--force", str(wt)],
                       check=True, capture_output=True)

if paso.get("preguntas") is not None:
    (cwd / "PREGUNTAS.md").write_bytes(paso["preguntas"].encode("utf-8"))

print(json.dumps({"type": "result", "session_id": sid}))
sys.exit(paso.get("exit", 0))
