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
        # Por carril, el error (`"<Tipo>: <mensaje>"`) de su último intento de copia si falló; un
        # carril con un intento exitoso más reciente no aparece acá. Solo lo toca `sondear` (el
        # hilo y, tras el `join`, el `__exit__`), nunca a la vez: no hace falta lock.
        self._fallas = {}
        # Carriles que tuvieron al menos un intento de copia exitoso alguna vez. Nunca se saca un
        # nombre de acá: una vez que hubo una copia buena, un intento fallido posterior no la
        # destruye (el swap con renames de `_copiar`), así que sigue habiendo una copia anterior.
        self._con_copia_previa = set()

    def __enter__(self):
        self._hilo.start()
        return self

    def __exit__(self, *exc):
        self._parar.set()
        self._hilo.join()
        self.sondear()

    def carriles_sin_copia(self):
        """Los carriles cuyo último intento de copia falló, en orden de nombre de carril:
        `(carril, error, copia_anterior)`. `copia_anterior` es si el carril tuvo, en algún
        sondeo anterior de esta misma instancia, un intento de copia que no falló."""
        return [
            (carril, error, carril in self._con_copia_previa)
            for carril, error in sorted(self._fallas.items())
        ]

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
                try:
                    self._copiar(wt.name, wt / ".scratch")
                except OSError as e:
                    # `_copiar` no deja ventana de pérdida (swap con renames y rollback): si
                    # falla, la copia anterior sobrevive intacta y se reintenta en el próximo
                    # sondeo. El fallo queda en memoria por carril (`_fallas`) para que `lanzar`
                    # lo reporte como `carril_sin_copia`; una falla del sondeo nunca cambia el
                    # `motivo` de la corrida. Una excepción que no es `OSError` no se traga acá.
                    self._fallas[wt.name] = f"{type(e).__name__}: {e}"
                    continue
                self._fallas.pop(wt.name, None)  # el último intento sobre este carril salió bien
                self._con_copia_previa.add(wt.name)

    def _copiar(self, nombre, scratch):
        carpeta = self.destino / nombre
        nueva, vigente = carpeta / ".scratch.nueva", carpeta / ".scratch"
        vieja = carpeta / ".scratch.vieja"
        shutil.rmtree(nueva, ignore_errors=True)
        try:
            shutil.copytree(scratch, nueva)
        except (OSError, shutil.Error):
            # Cualquier falla acá (el origen desapareció a mitad de copia, un archivo tomado,
            # etc.) se propaga: para `sondear` es un intento fallido, no un éxito silencioso.
            # Se borra lo parcial para no dejar un `.scratch.nueva` a medio copiar tirado; la
            # copia vigente (si había una) no se toca.
            shutil.rmtree(nueva, ignore_errors=True)
            raise
        # Swap con renames: nunca hay un instante sin `vigente` (ni una destrucción irreversible
        # si un rename falla a mitad de camino, p. ej. por un archivo tomado en Windows).
        shutil.rmtree(vieja, ignore_errors=True)  # sobrante de un intento anterior interrumpido
        movida = False
        if vigente.exists():
            try:
                vigente.rename(vieja)
            except OSError:
                shutil.rmtree(nueva, ignore_errors=True)
                raise
            movida = True
        try:
            nueva.rename(vigente)
        except OSError:
            if movida:
                vieja.rename(vigente)  # rollback: `vigente` queda como estaba
            raise
        shutil.rmtree(vieja, ignore_errors=True)


def _registrar_carriles_sin_copia(bitacora, sondeo, original=None):
    """Un evento `carril_sin_copia` por carril cuyo último intento de copia falló, en orden de
    nombre. Escribir el evento nunca cambia el `motivo`: en el camino de error, la falla de la
    bitácora queda como nota en `original` (`mat.registrar_sin_tapar`, igual que el resto de las
    fallas de bitácora de esta corrida); en el exitoso (`original=None`), se descarta.
    """
    for carril, error, copia_anterior in sondeo.carriles_sin_copia():
        campos = dict(carril=carril, error=error, copia_anterior=copia_anterior)
        if original is not None:
            mat.registrar_sin_tapar(bitacora, original, "carril_sin_copia", **campos)
        else:
            try:
                bitacora.registrar("carril_sin_copia", **campos)
            except Exception:
                # Se acepta perder el evento: si la bitácora está rota, el `corrida_cerrada`
                # que sigue va a fallar exactamente igual, y ahí queda el rastro.
                pass


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
    sondeo_obj = None
    try:
        try:
            config.mkdir(exist_ok=True)
            shutil.copyfile(credencial, copia_credencial)
            sondeo_obj = Sondeo(corrida / "proyecto", corrida / "carriles", sondeo)
            with sondeo_obj:
                motivo = _rondas(corrida, brazo, bitacora, claude, tope_rondas, juguete)
            _registrar_carriles_sin_copia(bitacora, sondeo_obj)
            sondeo_obj = None  # ya registrados: si algo de acá para abajo falla, no repetirlos
            _copiar_transcripts(config, corrida / "transcripts")
        except BaseException as e:
            try:
                _copiar_transcripts(config, corrida / "transcripts")
            except Exception as e2:
                e.add_note(f"además falló copiar los transcripts: {type(e2).__name__}: {e2}")
            if sondeo_obj is not None:
                _registrar_carriles_sin_copia(bitacora, sondeo_obj, original=e)
            mat.registrar_sin_tapar(bitacora, e, "corrida_cerrada", motivo="error",
                                    error=f"{type(e).__name__}: {e}")
            raise
    finally:
        copia_credencial.unlink(missing_ok=True)
    bitacora.registrar("corrida_cerrada", motivo=motivo)
    return motivo
