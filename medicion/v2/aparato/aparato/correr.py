"""Lanzar al agente sobre una corrida ya materializada, según `medicion/v2/CORRIDA.md`.

`claude -p` con cwd en `proyecto/` y `CLAUDE_CONFIG_DIR=<corrida>/config` (vacío salvo una copia de
la credencial, que se borra siempre al terminar). Si una sesión termina dejando `PREGUNTAS.md`, se
copia a `preguntas/ronda-NN.md`, se arma la respuesta del cliente con `ruteo`, se borra y se
relanza continuando la sesión. Mientras corre, un hilo sondea los worktrees de carril y guarda la
última copia vista de su `.scratch/`; al final se copian crudos todos los JSONL de
`config/projects/`.
"""
import json
import re
import shutil
import subprocess
import threading
from pathlib import Path

from . import brazos
from . import materializar as mat

MODELO = "claude-opus-5-5"
CREDENCIAL = Path.home() / ".claude" / ".credentials.json"
TOPE_RONDAS = 5
SONDEO = 2.0  # segundos entre dos miradas a los worktrees de carril


class SesionFallida(RuntimeError):
    def __init__(self, sesion, exit_code, stderr):
        cola = stderr.decode("utf-8", errors="replace").strip()[-500:]
        super().__init__(f"la sesión {sesion} de claude salió con {exit_code}: {cola}")


def _evals(juguete):
    return json.loads((Path(juguete) / "evals" / "evals.json").read_text(encoding="utf-8"))


def prompt_inicial(brazo, juguete=mat.JUGUETE):
    return _evals(juguete)["evals"][0]["prompt"] + "\n\n" + brazos.FRASE_MODO[brazo.modo]


def respuesta_del_cliente(preguntas, juguete=mat.JUGUETE):
    """(secciones, texto): A y C si su `ruteo` coincide con `preguntas`, B siempre; orden A, C, B."""
    ruteo = _evals(juguete)["ruteo"]
    secciones = [s for s in ("A", "C") if re.search(ruteo[s], preguntas, re.IGNORECASE)] + ["B"]
    texto = (Path(juguete) / "cliente" / "respuestas.md").read_text(encoding="utf-8")
    partes = re.split(r"^## (\S+)[ \t]*$", texto, flags=re.MULTILINE)
    cuerpos = {partes[i]: partes[i + 1].strip() for i in range(1, len(partes), 2)}
    return secciones, "\n\n".join(cuerpos[s] for s in secciones)


def _entorno_del_agente(config):
    # Nada `CLAUDE*` de la sesión que lanza (esfuerzo, id de sesión, sockets) le llega al agente:
    # los tres brazos arrancan con el mismo entorno, salvo la config de su corrida.
    env = {k: v for k, v in mat.entorno_sin_git_heredado().items()
           if not k.upper().startswith("CLAUDE")}
    env["CLAUDE_CONFIG_DIR"] = str(config)
    return env


def _session_id(stdout):
    texto = stdout.decode("utf-8", errors="replace").strip()
    for candidato in (texto, texto.splitlines()[-1] if texto else ""):
        try:
            sid = json.loads(candidato).get("session_id")
            return sid or None
        except (ValueError, AttributeError):
            continue
    return None


def _sesion(claude, proyecto, config, prompt, session_id, continuar):
    args = [*claude, "-p", "--output-format", "json", "--model", MODELO,
            "--dangerously-skip-permissions"]
    if session_id:
        args += ["--resume", session_id]
    elif continuar:
        args.append("--continue")
    # El prompt va por stdin: por argv, un `claude.cmd` de Windows cortaría los saltos de línea.
    r = subprocess.run(args, cwd=proyecto, env=_entorno_del_agente(config),
                       input=prompt.encode("utf-8"), capture_output=True)
    return r.returncode, _session_id(r.stdout), r.stderr


class Sondeo:
    """Hilo que mira los worktrees de `proyecto` y guarda la última copia vista de su `.scratch/`
    en `<destino>/<nombre de la carpeta del worktree>/.scratch/`. Al salir del `with` mira una
    vez más."""

    def __init__(self, proyecto, destino, intervalo):
        self.proyecto, self.destino, self.intervalo = Path(proyecto), Path(destino), intervalo
        self._parar = threading.Event()
        self._hilo = threading.Thread(target=self._bucle, daemon=True)

    def __enter__(self):
        self._hilo.start()
        return self

    def __exit__(self, *exc):
        self._parar.set()
        self._hilo.join()
        self.sondear()

    def _bucle(self):
        while not self._parar.wait(self.intervalo):
            self.sondear()

    def sondear(self):
        try:
            salida = mat._correr([mat.GIT, "-C", str(self.proyecto), "worktree", "list",
                                  "--porcelain"]).decode("utf-8", errors="replace")
        except Exception:
            return  # git ocupado o el agente a mitad de un `worktree add`: se mira en el próximo
        rutas = [Path(l[len("worktree "):]) for l in salida.splitlines()
                 if l.startswith("worktree ")]
        for wt in rutas[1:]:  # el primero es el principal: `proyecto/`
            if (wt / ".scratch").is_dir():
                self._copiar(wt.name, wt / ".scratch")

    def _copiar(self, nombre, scratch):
        carpeta = self.destino / nombre
        nueva, vigente = carpeta / ".scratch.nueva", carpeta / ".scratch"
        shutil.rmtree(nueva, ignore_errors=True)
        try:
            shutil.copytree(scratch, nueva)
        except (OSError, shutil.Error):
            # El agente la borró a mitad de la copia: queda la anterior, que es la última entera.
            shutil.rmtree(nueva, ignore_errors=True)
            return
        shutil.rmtree(vigente, ignore_errors=True)
        nueva.rename(vigente)


def _copiar_transcripts(config, destino):
    projects = Path(config) / "projects"
    if not projects.is_dir():
        return
    for p in projects.rglob("*.jsonl"):
        d = Path(destino) / p.relative_to(projects)
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(p, d)


def _rondas(corrida, brazo, bitacora, claude, tope_rondas, juguete):
    proyecto, config = corrida / "proyecto", corrida / "config"
    prompt, session_id, ronda, sesion = prompt_inicial(brazo, juguete), None, 0, 0
    while True:
        sesion += 1
        bitacora.registrar("sesion_lanzada", sesion=sesion, session_id=session_id)
        code, nuevo, stderr = _sesion(claude, proyecto, config, prompt, session_id,
                                      continuar=sesion > 1)
        session_id = nuevo or session_id
        bitacora.registrar("sesion_terminada", sesion=sesion, session_id=session_id,
                           exit_code=code)
        if code != 0:
            raise SesionFallida(sesion, code, stderr)
        preguntas = proyecto / "PREGUNTAS.md"
        if not preguntas.exists():
            return "completa"
        if ronda >= tope_rondas:
            return "tope_rondas"  # la última `PREGUNTAS.md` queda en `proyecto/`, sin responder
        ronda += 1
        copia = corrida / "preguntas" / f"ronda-{ronda:02d}.md"
        copia.parent.mkdir(exist_ok=True)
        shutil.copyfile(preguntas, copia)
        secciones, prompt = respuesta_del_cliente(
            copia.read_bytes().decode("utf-8", errors="replace"), juguete)
        bitacora.registrar("ronda_preguntas", ronda=ronda,
                           copia=copia.relative_to(corrida).as_posix(), secciones=secciones)
        preguntas.unlink()


def lanzar(corrida, brazo, *, claude, tope_rondas=TOPE_RONDAS, sondeo=SONDEO,
           credencial=CREDENCIAL, juguete=mat.JUGUETE, ahora=mat._ahora_utc):
    """Corre el agente sobre `corrida` hasta que cierra; devuelve el `motivo` de `corrida_cerrada`.

    `claude` es el comando como lista (`[ruta del exe]`). Si algo falla, registra
    `corrida_cerrada` con `motivo: error` y propaga la excepción.
    """
    corrida = Path(corrida)
    config = corrida / "config"
    bitacora = mat.Bitacora(corrida / "bitacora.jsonl", ahora)
    copia_credencial = config / ".credentials.json"
    try:
        try:
            config.mkdir(exist_ok=True)
            shutil.copyfile(credencial, copia_credencial)
            with Sondeo(corrida / "proyecto", corrida / "carriles", sondeo):
                motivo = _rondas(corrida, brazo, bitacora, claude, tope_rondas, juguete)
            _copiar_transcripts(config, corrida / "transcripts")
        except BaseException as e:
            try:
                _copiar_transcripts(config, corrida / "transcripts")
            except Exception as e2:
                e.add_note(f"además falló copiar los transcripts: {type(e2).__name__}: {e2}")
            mat.registrar_sin_tapar(bitacora, e, "corrida_cerrada", motivo="error",
                                    error=f"{type(e).__name__}: {e}")
            raise
    finally:
        copia_credencial.unlink(missing_ok=True)
    bitacora.registrar("corrida_cerrada", motivo=motivo)
    return motivo
