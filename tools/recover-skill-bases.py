#!/usr/bin/env python3
"""Recupera, por similitud, la base de merge de cada skill externa del scaffold.

Ver docs/agents/recuperar-base-de-skills.md para el cómo y el porqué.
"""
from __future__ import annotations

import argparse
import datetime
import difflib
import json
import os
import subprocess
import sys


# --------------------------------------------------------------------------- #
# Primitivas de git
# --------------------------------------------------------------------------- #

def _git(repo, *args):
    """Corre git en `repo` y devuelve stdout como texto."""
    return _git_bytes(repo, *args).decode("utf-8", "replace")


def _git_bytes(repo, *args, stdin=None):
    p = subprocess.run(["git", "-C", repo, *args], input=stdin,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        raise RuntimeError("git %s falló (%d): %s"
                           % (" ".join(args), p.returncode,
                              p.stderr.decode("utf-8", "replace").strip()))
    return p.stdout


# --------------------------------------------------------------------------- #
# Cuerpo sin frontmatter
# --------------------------------------------------------------------------- #

def body_of(text):
    """Cuerpo de un SKILL.md: sin frontmatter, con fines de línea LF y extremos recortados.

    El drift propio de estas skills vive casi todo en la `description`, así que la
    similitud se mide sobre el cuerpo (ADR-0005). La normalización de fines de línea
    es obligatoria: nuestra copia está en CRLF y los blobs de upstream en LF.
    """
    t = text.replace("\r\n", "\n").replace("\r", "\n")
    if t and ord(t[0]) == 0xFEFF:          # BOM
        t = t[1:]
    if t.startswith("---\n"):
        end = t.find("\n---", 3)
        if end != -1:
            nl = t.find("\n", end + 1)
            t = t[nl + 1:] if nl != -1 else ""
    return t.strip()


def similarity(a, b):
    return difflib.SequenceMatcher(None, a, b).ratio()


# --------------------------------------------------------------------------- #
# Inventario de upstream
# --------------------------------------------------------------------------- #

def _skill_blobs(upstream):
    """Todos los blobs `*/SKILL.md` alcanzables en la historia publicada de upstream.

    `rev-list --objects --all` recorre todos los objetos alcanzables desde todas las
    refs; cada blob aparece una vez, con el path en el que se lo encontró primero.
    """
    out = []
    for line in _git(upstream, "rev-list", "--objects", "--all").splitlines():
        oid, _, path = line.partition(" ")
        if path.endswith("SKILL.md"):
            out.append((oid, path))
    return out


def _read_blobs(upstream, oids):
    """Lee muchos blobs de una sola pasada con `cat-file --batch`."""
    if not oids:
        return {}
    raw = _git_bytes(upstream, "cat-file", "--batch",
                     stdin=("\n".join(oids) + "\n").encode("ascii"))
    contents = {}
    i = 0
    for oid in oids:
        j = raw.index(b"\n", i)
        size = int(raw[i:j].split()[2])
        contents[oid] = raw[j + 1:j + 1 + size]
        i = j + 1 + size + 1          # +1 por el \n que cierra cada objeto
    return contents


def _history(upstream):
    """(introducciones, renombres) leídos de un único recorrido del log.

    - introducciones: (blob, path) -> [(commit, fecha ISO, asunto, posicion en el log), ...]
    - renombres: path viejo -> {paths nuevos}

    `git log` emite del más nuevo al más viejo, así que una posición mayor es un commit
    más viejo. Eso desempata las fechas iguales al segundo, que existen y si no se
    desempatan hacen elegir la aparición más nueva en vez de la primera.
    """
    sep = "\x01"
    raw = _git(upstream, "log", "--all", "--full-history",
               "--format=%s%%H\x1f%%cI\x1f%%s" % sep, "--raw", "--no-abbrev", "--", "*SKILL.md")
    intro, renames = {}, {}
    commit = date = subject = None
    seq = -1
    for line in raw.splitlines():
        if line.startswith(sep):
            commit, date, subject = line[1:].split("\x1f", 2)
            seq += 1
        elif line.startswith(":"):
            fields = line.split("\t")
            meta = fields[0].split()
            new_sha, status = meta[3], meta[4]
            path = fields[-1]                      # en R/C el path nuevo es el último
            if status[0] in ("R", "C") and len(fields) >= 3:
                renames.setdefault(fields[1], set()).add(fields[2])
            if status[0] in ("A", "M", "T", "R", "C"):
                intro.setdefault((new_sha, path), []).append((commit, date, subject, seq))
    return intro, renames


def _head_path(path, head_paths, renames):
    """Dónde vive hoy ese path en upstream: el mismo, uno renombrado, o ninguno."""
    if path in head_paths:
        return {"status": "present", "path": path}
    # BFS sobre la cadena de renombres registrada por git commit a commit.
    frontier, seen = [(path, [])], {path}
    while frontier:
        cur, chain = frontier.pop(0)
        for nxt in sorted(renames.get(cur, ())):
            if nxt in seen:
                continue
            seen.add(nxt)
            step = chain + [nxt]
            if nxt in head_paths:
                return {"status": "renamed", "path": nxt, "renameChain": [path] + step}
            frontier.append((nxt, step))
    return {"status": "gone", "path": None}


# --------------------------------------------------------------------------- #
# Recuperación
# --------------------------------------------------------------------------- #

def recover(upstream, skills_dir, names, threshold):
    upstream = os.path.abspath(upstream)
    head = _git(upstream, "rev-parse", "HEAD").strip()

    candidates = _skill_blobs(upstream)
    contents = _read_blobs(upstream, [oid for oid, _ in candidates])
    bodies = {oid: body_of(blob.decode("utf-8", "replace")) for oid, blob in contents.items()}
    rev_list_path = {oid: path for oid, path in candidates}

    intro, renames = _history(upstream)
    paths_by_blob = {}
    for (blob, path) in intro:
        paths_by_blob.setdefault(blob, set()).add(path)

    head_paths = {p for p in _git(upstream, "ls-tree", "-r", "--name-only", "HEAD").splitlines()
                  if p.endswith("SKILL.md")}
    head_bodies = None                              # se calcula solo si hace falta

    if names:
        wanted = list(names)
    else:
        wanted = sorted(d for d in os.listdir(skills_dir)
                        if os.path.isfile(os.path.join(skills_dir, d, "SKILL.md")))

    results = []
    for name in wanted:
        local = os.path.join(skills_dir, name, "SKILL.md")
        if not os.path.isfile(local):
            results.append({"name": name, "status": "missing-locally", "localPath": None})
            continue
        with open(local, "rb") as f:
            mine = body_of(f.read().decode("utf-8"))

        best_ratio, best_oid = 0.0, None
        for oid, other in bodies.items():
            sm = difflib.SequenceMatcher(None, mine, other)
            # cotas baratas: si el techo no supera al mejor actual, ni calculamos el ratio
            if sm.real_quick_ratio() < best_ratio or sm.quick_ratio() < best_ratio:
                continue
            r = sm.ratio()
            if r > best_ratio:
                best_ratio, best_oid = r, oid

        entry = {
            "name": name,
            "localPath": os.path.relpath(local, REPO).replace(os.sep, "/"),
        }
        if best_oid is None or best_ratio < threshold:
            entry["status"] = "unmatched"
            entry["base"] = None
            entry["bestSimilarity"] = round(best_ratio, 4)
            entry["note"] = ("ninguna version historica de upstream supera el umbral de %.2f: "
                             "no hay base de merge, es un fork propio" % threshold)
            results.append(entry)
            continue

        path = rev_list_path.get(best_oid) or sorted(paths_by_blob.get(best_oid, ["?"]))[0]
        hits = intro.get((best_oid, path)) or []
        if not hits:                                # el blob entró por un path distinto
            for (blob, other_path), h in intro.items():
                if blob == best_oid:
                    path, hits = other_path, h
                    break
        commit = date = subject = None
        if hits:
            commit, date, subject, _ = sorted(hits, key=lambda h: (h[1], -h[3]))[0]

        entry["status"] = "recovered"
        entry["similarity"] = round(best_ratio, 4)
        entry["base"] = {
            "blob": best_oid,
            "upstreamPath": path,
            "commit": commit,
            "commitDate": date,
            "commitSubject": subject,
        }
        other_paths = sorted(paths_by_blob.get(best_oid, set()) - {path})
        if other_paths:
            entry["base"]["alsoSeenAtPaths"] = other_paths

        uh = _head_path(path, head_paths, renames)
        if uh["status"] == "gone":
            if head_bodies is None:
                head_oids = {}
                for p in sorted(head_paths):
                    head_oids[p] = _git(upstream, "rev-parse", "HEAD:" + p).strip()
                hb = _read_blobs(upstream, sorted(set(head_oids.values())))
                head_bodies = {p: body_of(hb[o].decode("utf-8", "replace"))
                               for p, o in head_oids.items()}
            ranked = sorted(((similarity(bodies[best_oid], b), p)
                             for p, b in head_bodies.items()), reverse=True)[:3]
            uh["unconfirmedSuccessorCandidates"] = [
                {"path": p, "similarity": round(r, 4)} for r, p in ranked]
            uh["note"] = ("el path no existe en el HEAD de upstream y git no detecta renombre. "
                          "Los candidatos de abajo NO son bases: son pistas para que un humano "
                          "decida si hay sucesor (ver ADR-0006).")
        entry["upstreamHead"] = uh
        results.append(entry)

    return {
        "tool": "tools/recover-skill-bases.py",
        "generatedAt": datetime.datetime.now(datetime.timezone.utc)
                               .replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "doNotEditByHand": ("salida generada; es la entrada del lockfile de skills. "
                            "Para cambiarla, volve a correr la herramienta."),
        "method": {
            "similarity": "difflib.SequenceMatcher(None, a, b).ratio()",
            "comparedOn": "cuerpo del SKILL.md sin frontmatter, fines de linea normalizados a LF, extremos recortados",
            "searchSpace": "todos los blobs */SKILL.md alcanzables en la historia publicada de upstream",
            "threshold": threshold,
        },
        "upstream": {
            "url": UPSTREAM_URL,
            "clone": upstream.replace(os.sep, "/"),
            "head": head,
            "skillBlobsScanned": len(candidates),
        },
        "localSkillsDir": os.path.relpath(os.path.abspath(skills_dir), REPO).replace(os.sep, "/"),
        "skills": results,
        "summary": {
            "recovered": sum(1 for s in results if s.get("status") == "recovered"),
            "unmatched": sum(1 for s in results if s.get("status") == "unmatched"),
            "exactBodyMatches": sum(1 for s in results if s.get("similarity") == 1.0),
            "goneFromUpstreamHead": sum(1 for s in results
                                        if s.get("upstreamHead", {}).get("status") == "gone"),
        },
    }


# --------------------------------------------------------------------------- #
# Self-test offline (fixture sintético, sin red)
# --------------------------------------------------------------------------- #

def self_test():
    import shutil
    import subprocess
    import tempfile

    tmp = tempfile.mkdtemp(prefix="recover-skill-bases-selftest-")
    try:
        up = os.path.join(tmp, "upstream")
        os.makedirs(up)

        def g(*a):
            subprocess.run(["git", "-C", up, *a], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def write(rel, text):
            p = os.path.join(up, rel.replace("/", os.sep))
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)

        subprocess.run(["git", "-c", "init.defaultBranch=main", "init", up], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        g("config", "user.email", "selftest@example.invalid")
        g("config", "user.name", "selftest")

        alpha_v1 = "---\nname: a\ndescription: upstream original\n---\n\n" + \
                   "".join("Paso %d del cuerpo original de alpha.\n" % i for i in range(1, 30))
        alpha_v2 = alpha_v1.replace("Paso 5 del cuerpo original de alpha.",
                                    "Paso 5 REESCRITO por upstream despues de la base.")
        alpha_v3 = alpha_v1.replace("Paso 7 del cuerpo original de alpha.",
                                    "Paso 7 reescrito de nuevo, y van dos.")
        ghost = "---\nname: ghost\n---\n\n" + \
                "".join("Linea %d de una skill que upstream borro.\n" % i for i in range(1, 30))

        write("skills/a/SKILL.md", alpha_v1)
        write("skills/ghost/SKILL.md", ghost)
        g("add", "-A")
        g("commit", "-m", "commit 1: alpha v1 + ghost")

        write("skills/a/SKILL.md", alpha_v2)
        os.remove(os.path.join(up, "skills", "ghost", "SKILL.md"))
        g("add", "-A")
        g("commit", "-m", "commit 2: alpha v2, borra ghost")

        # el mismo cuerpo v1 vuelve a aparecer en el mismo path: la base es la PRIMERA
        # aparicion, no la ultima, y este commit es lo que hace que esa regla se pueda romper.
        write("skills/a/SKILL.md", alpha_v1)
        g("add", "-A")
        g("commit", "-m", "commit 3: alpha vuelve a v1")

        write("skills/a/SKILL.md", alpha_v3)
        g("add", "-A")
        g("commit", "-m", "commit 4: alpha v3")

        os.makedirs(os.path.join(up, "skills", "a2"))
        shutil.move(os.path.join(up, "skills", "a", "SKILL.md"),
                    os.path.join(up, "skills", "a2", "SKILL.md"))
        g("add", "-A")
        g("commit", "-m", "commit 5: renombra a -> a2")

        local = os.path.join(tmp, "local")
        for name, text in [
            # mismo cuerpo que alpha_v1, frontmatter propio: la similitud debe dar 1.0
            ("alpha", alpha_v1.replace("description: upstream original",
                                       "description: drift propio en el frontmatter")),
            ("ghost", ghost),
            ("ours", "---\nname: ours\n---\n\n" +
                     "".join("Nada de esto salio de upstream, linea %d.\n" % i for i in range(1, 30))),
        ]:
            d = os.path.join(local, name)
            os.makedirs(d)
            with open(os.path.join(d, "SKILL.md"), "w", encoding="utf-8", newline="\r\n") as f:
                f.write(text)

        report = recover(up, local, None, 0.60)
        by = {s["name"]: s for s in report["skills"]}
        fails, total = [], []

        def check(label, cond, got):
            total.append(label)
            if cond:
                print("  ok   %s" % label)
            else:
                print("  FAIL %s -> %r" % (label, got))
                fails.append(label)

        a = by.get("alpha", {})
        check("alpha: status recovered", a.get("status") == "recovered", a.get("status"))
        check("alpha: similitud 1.0 (el frontmatter no cuenta, CRLF vs LF tampoco)",
              a.get("similarity") == 1.0, a.get("similarity"))
        check("alpha: path historico skills/a/SKILL.md",
              a.get("base", {}).get("upstreamPath") == "skills/a/SKILL.md",
              a.get("base", {}).get("upstreamPath"))
        check("alpha: commit base = el que introdujo v1 (commit 1)",
              a.get("base", {}).get("commitSubject", "").startswith("commit 1"),
              a.get("base", {}).get("commitSubject"))
        check("alpha: blob de 40 hex",
              len(a.get("base", {}).get("blob") or "") == 40, a.get("base", {}).get("blob"))
        check("alpha: fecha del commit no vacia",
              bool(a.get("base", {}).get("commitDate")), a.get("base", {}).get("commitDate"))
        check("alpha: upstream HEAD lo tiene renombrado a skills/a2/SKILL.md",
              a.get("upstreamHead", {}).get("status") == "renamed" and
              a.get("upstreamHead", {}).get("path") == "skills/a2/SKILL.md",
              a.get("upstreamHead"))

        gh = by.get("ghost", {})
        check("ghost: base recuperada igual (upstream la borro, pero existio)",
              gh.get("status") == "recovered" and gh.get("similarity") == 1.0,
              (gh.get("status"), gh.get("similarity")))
        check("ghost: sin correspondencia en el HEAD de upstream",
              gh.get("upstreamHead", {}).get("status") == "gone", gh.get("upstreamHead"))

        ou = by.get("ours", {})
        check("ours: sin base (no se inventa una de similitud baja)",
              ou.get("status") == "unmatched", ou.get("status"))
        check("ours: no emite base", ou.get("base") is None, ou.get("base"))
        check("ours: deja registrada la mejor similitud vista, por debajo del umbral",
              isinstance(ou.get("bestSimilarity"), float) and ou["bestSimilarity"] < 0.60,
              ou.get("bestSimilarity"))

        check("recorre los 3 skills del fixture", len(report["skills"]) == 3, len(report["skills"]))
        check("registra el HEAD de upstream",
              len(report.get("upstream", {}).get("head") or "") == 40,
              report.get("upstream", {}).get("head"))

        print("\nSELF-TEST: %d ok, %d fail (de %d)"
              % (len(total) - len(fails), len(fails), len(total)))
        return 1 if fails else 0
    finally:
        import stat

        def rw(func, path, _):
            os.chmod(path, stat.S_IWRITE)
            func(path)

        shutil.rmtree(tmp, onerror=rw)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SKILLS_DIR = os.path.join(
    REPO, "skills", "bootstrap-ai-project", "assets", "scaffold", ".agents", "skills")
DEFAULT_OUT = os.path.join(REPO, ".scratch", "bootstrap-v2", "skill-bases.json")
UPSTREAM_URL = "https://github.com/mattpocock/skills.git"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--upstream-clone", help="clon de upstream ya existente (evita la red)")
    ap.add_argument("--upstream-url", default=UPSTREAM_URL)
    ap.add_argument("--skills-dir", default=DEFAULT_SKILLS_DIR)
    ap.add_argument("--skill", action="append", dest="skills")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--threshold", type=float, default=0.60)
    ap.add_argument("--stdout", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()

    clone = args.upstream_clone
    if clone and not os.path.isdir(os.path.join(clone, ".git")):
        print("No es un clon de git: %s" % clone, file=sys.stderr)
        return 2
    if not clone:
        import tempfile
        clone = tempfile.mkdtemp(prefix="pocock-skills-")
        print("Clonando %s (requiere red)..." % args.upstream_url, file=sys.stderr)
        # el clon debe traer toda la historia: la base vive en blobs viejos, no en el HEAD
        subprocess.run(["git", "clone", "--quiet", args.upstream_url, clone], check=True)
        print("Clon: %s (reusalo con --upstream-clone)" % clone, file=sys.stderr)

    report = recover(clone, args.skills_dir, args.skills, args.threshold)
    text = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.stdout:
        sys.stdout.write(text)
    else:
        os.makedirs(os.path.dirname(args.out), exist_ok=True)
        with open(args.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        print("Escrito: %s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
