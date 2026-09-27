"""Cuanto crece el contexto de la sesion PRINCIPAL de Claude Code, y por que.

Lee los transcripts .jsonl crudos (no la base de claude-analytics: esa guarda tokens por evento pero
no el tamano de lo que devuelve cada herramienta). Solo lectura: no escribe nada fuera de stdout.

    python medicion/delegacion/contexto.py fuentes [--desde 2026-08-01] [--pico 120000]
    python medicion/delegacion/contexto.py slices  [--desde 2026-08-01] [--proyecto Bootstrap-Skills]

Metodo (comun a los dos):
  - Contexto de una llamada a la API = input + cache_read + cache_creation de su `usage`, contando
    una vez cada message.id (un mensaje del asistente se graba en varias lineas con el mismo usage).
  - Solo la sesion principal: los .jsonl directamente bajo <raiz>/projects/<proyecto>/ y sin
    `isSidechain`. Los de subagentes viven en subcarpetas y no se leen.
  - Una caida del contexto a menos del 60 % de la llamada anterior es una compaction: corta el tramo.

`fuentes`: entre dos llamadas, delta = ctx(n) - ctx(n-1) - output(n-1) son los tokens que entraron
en el medio; se reparten entre los bloques que entraron (tool_result por herramienta, texto del
usuario, adjuntos del harness) en proporcion a sus caracteres. El output(n-1) se reparte entre sus
bloques (thinking, texto, tool_use) tambien por caracteres: ese reparto interno no sirve, porque
el transcript graba el thinking vacio y su peso cae en los otros bloques del mensaje; el total del
output si es exacto. Los adjuntos `prompt_snapshot` no cuentan:
son una copia del system prompt, no contexto nuevo.

`slices`: por sesion, crecimiento desde su primera llamada hasta el primer commit con `Slice-Close:`
en el comando (`git commit -m ...`; los commits con `-F archivo` no se ven). Se toma solo el primer
slice de cada sesion porque el review-loop de un slice corre DESPUES de su commit y engordaria al
siguiente. Lineas = adiciones + borrados de `git show --numstat` en el `cwd` de la sesion; los
merges y los commits que ya no existen quedan sin lineas y fuera de la tabla normalizada.
"""
import argparse, collections, datetime, glob, json, os, re, statistics, subprocess, sys

RAICES = [os.path.expanduser('~/.claude/projects'), os.path.expanduser('~/.claude-southpoint/projects')]


def transcripts(desde):
    t0 = datetime.datetime.fromisoformat(desde).timestamp()
    for raiz in RAICES:
        for f in glob.glob(os.path.join(raiz, '*', '*.jsonl')):
            if os.path.getmtime(f) >= t0:
                yield f


def eventos(f):
    with open(f, encoding='utf8', errors='replace') as fh:
        for linea in fh:
            try:
                e = json.loads(linea)
            except ValueError:
                continue
            if not e.get('isSidechain'):
                yield e


def contexto(u):
    return u.get('input_tokens', 0) + u.get('cache_read_input_tokens', 0) + u.get('cache_creation_input_tokens', 0)


def largo(c):
    if isinstance(c, str):
        return len(c)
    if isinstance(c, list):
        return sum(len(x.get('text', '')) if x.get('type') == 'text' else len(json.dumps(x))
                   for x in c if isinstance(x, dict))
    return len(json.dumps(c)) if c else 0


def texto_resultado(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return '\n'.join(x.get('text', '') for x in c if isinstance(x, dict))
    return ''


def cmd_fuentes(a):
    total = collections.Counter(); arranques = []; picos = []; ruido = []
    RUIDO = {'tool:Read', 'tool:Grep', 'tool:Glob', 'tool:Bash', 'tool:PowerShell', 'tool:WebFetch', 'tool:WebSearch'}
    for f in transcripts(a.desde):
        nombres = {}; mezcla = collections.defaultdict(collections.Counter); pendiente = []
        visto = set(); ant = None; ant_out = 0; ant_id = None; primero = None; pico = 0
        acc = collections.Counter()
        for e in eventos(f):
            t = e.get('type'); m = e.get('message') or {}
            if t == 'assistant':
                mid = m.get('id')
                for b in m.get('content') or []:
                    if not isinstance(b, dict):
                        continue
                    if b.get('type') == 'tool_use':
                        nombres[b['id']] = b.get('name', '?')
                        n = b.get('name', '?')
                        k = ('out:escribe (Edit/Write)' if n in ('Edit', 'Write', 'NotebookEdit')
                             else 'out:pedido a subagente' if n in ('Agent', 'Task', 'Workflow')
                             else 'out:otros tool_use')
                        mezcla[mid][k] += len(json.dumps(b.get('input')))
                    elif b.get('type') == 'thinking':
                        mezcla[mid]['out:thinking'] += len(b.get('thinking', ''))
                    elif b.get('type') == 'text':
                        mezcla[mid]['out:texto'] += len(b.get('text', ''))
                u = m.get('usage')
                if not mid or not u or mid in visto:
                    continue
                visto.add(mid)
                ctx = contexto(u)
                if ctx < 1000:
                    continue
                if ant is None:
                    primero = ctx
                elif ctx < ant * 0.6:
                    pendiente = []
                else:
                    mz = mezcla.get(ant_id) or {}
                    tm = sum(mz.values())
                    for k, v in (mz.items() if tm else [('out:sin bloques', 1)]):
                        acc[k] += ant_out * v / (tm or 1)
                    d = ctx - ant - ant_out
                    tc = sum(c for _, c in pendiente)
                    if d > 0:
                        for k, c in (pendiente if tc else [('sin atribuir', 1)]):
                            acc[k] += d * c / (tc or 1)
                pendiente = []; ant = ctx; ant_out = u.get('output_tokens', 0); ant_id = mid
                pico = max(pico, ctx)
            elif t == 'user':
                c = m.get('content')
                meta = 'usuario:meta (skill/hook)' if e.get('isMeta') else 'usuario:prompt'
                for b in (c if isinstance(c, list) else [{'type': 'text', 'text': c or ''}]):
                    if not isinstance(b, dict):
                        continue
                    if b.get('type') == 'tool_result':
                        n = nombres.get(b.get('tool_use_id'), '?')
                        n = 'mcp:' + n.split('__')[1] if n.startswith('mcp__') else n
                        pendiente.append(('tool:' + n, largo(b.get('content'))))
                    elif b.get('type') == 'text':
                        pendiente.append((meta, len(b.get('text', ''))))
            elif t in ('attachment', 'system'):
                adj = e.get('attachment') or {}
                if adj.get('type') == 'prompt_snapshot':
                    continue
                pendiente.append(('harness:' + str(adj.get('type') or e.get('subtype')),
                                  len(json.dumps(adj or e.get('content') or ''))))
        if primero and pico >= a.pico:
            total.update(acc); arranques.append(primero); picos.append(pico)
            s = sum(acc.values())
            ruido.append(sum(v for k, v in acc.items() if k in RUIDO) / s if s else 0)
    if not picos:
        sys.exit(f'ninguna sesion principal desde {a.desde} con pico >= {a.pico:,}')
    g = sum(total.values())
    print(f'sesiones principales desde {a.desde} con pico >= {a.pico:,}: {len(picos)}')
    print(f'contexto al arrancar: mediana {statistics.median(arranques):,.0f}  min {min(arranques):,}  max {max(arranques):,}')
    print(f'pico: mediana {statistics.median(picos):,.0f}')
    print(f'crecimiento atribuido: {g:,.0f} tokens')
    for k, v in total.most_common(a.top):
        print(f'  {k:40s} {v:14,.0f}  {100 * v / g:5.1f}%')
    q = statistics.quantiles(ruido, n=4)
    print(f'parte Read+Grep+Glob+Bash+PowerShell+Web por sesion: p25 {q[0]:.0%}  mediana {q[1]:.0%}  p75 {q[2]:.0%}')


HASH = re.compile(r'\[[^\]\s]+(?: \(root-commit\))? ([0-9a-f]{7,40})\]|^([0-9a-f]{7,40})\b', re.M)


def git(cwd, *args):
    r = subprocess.run(['git', '-C', cwd, *args], capture_output=True, text=True, encoding='utf8', errors='replace')
    return r.stdout if r.returncode == 0 else None


def hash_del_cierre(cwd, salida):
    """El hash del commit de cierre: el primero de la salida cuyo mensaje trae `Slice-Close:`.

    La salida puede ser la de `git commit` ([rama hash]) o la de un `git log --oneline` encadenado,
    y un hash suelto al inicio de linea puede ser de otro comando: por eso se confirma contra git.
    """
    if not cwd or not os.path.isdir(cwd):
        return None
    for m in HASH.finditer(salida):
        h = m.group(1) or m.group(2)
        if 'Slice-Close:' in (git(cwd, 'show', '--no-patch', '--format=%B', h) or ''):
            return h
    return None


def lineas(cwd, h):
    padres = git(cwd, 'show', '--no-patch', '--format=%P', h)
    if padres is None or len(padres.split()) != 1:
        return None
    stat = git(cwd, 'show', '--numstat', '--format=', h)
    if stat is None:
        return None
    return sum(int(c[0]) + int(c[1]) for c in (l.split('\t') for l in stat.splitlines())
               if len(c) >= 2 and c[0].isdigit() and c[1].isdigit())


def cmd_slices(a):
    filas = []
    for f in transcripts(a.desde):
        proyecto = os.path.basename(os.path.dirname(f))
        if a.proyecto and a.proyecto not in proyecto:
            continue
        visto = set(); ctx = None; inicio = None; agentes = 0; commits = {}; cwd = None
        for e in eventos(f):
            cwd = e.get('cwd') or cwd
            m = e.get('message') or {}
            if e.get('type') == 'assistant':
                u = m.get('usage'); mid = m.get('id')
                if u and mid and mid not in visto:
                    visto.add(mid)
                    c = contexto(u)
                    if c > 1000:
                        if ctx and c < ctx * 0.6:
                            break  # compaction antes del primer cierre: la sesion no sirve
                        ctx = c
                        inicio = inicio or c
                for b in m.get('content') or []:
                    if isinstance(b, dict) and b.get('type') == 'tool_use':
                        if b.get('name') in ('Agent', 'Task'):
                            agentes += 1
                        cmd = (b.get('input') or {}).get('command', '')
                        if b.get('name') in ('Bash', 'PowerShell') and 'git commit' in cmd and 'Slice-Close:' in cmd:
                            commits[b['id']] = re.search(r'Slice-Close:\s*([^\n"]{0,60})', cmd).group(1)
            elif e.get('type') == 'user' and commits and isinstance(m.get('content'), list):
                hecho = None
                for b in m['content']:
                    if isinstance(b, dict) and b.get('type') == 'tool_result' and b.get('tool_use_id') in commits:
                        h = hash_del_cierre(cwd, texto_resultado(b.get('content')))
                        if h:
                            hecho = (commits[b['tool_use_id']], h)
                if hecho:
                    filas.append(dict(fecha=e.get('timestamp', '')[:10], proyecto=proyecto, inicio=inicio,
                                      crece=ctx - inicio, agentes=agentes, slice=hecho[0], hash=hecho[1],
                                      lineas=lineas(cwd, hecho[1])))
                    break
    filas.sort(key=lambda r: r['fecha'])
    for r in filas:
        tl = f"{r['crece'] / r['lineas']:6.0f}" if r['lineas'] else '     -'
        print(f"{r['fecha']} {r['hash'][:7]} crece {r['crece']:>8,} lineas {r['lineas'] or '-':>5} tok/linea {tl}"
              f"  agentes {r['agentes']:2d}  {r['slice'][:48]}")
    v = [r['crece'] / r['lineas'] for r in filas if r['lineas']]
    if len(v) >= 4:
        q = statistics.quantiles(v, n=4)
        print(f"n {len(v)} (de {len(filas)})  tok/linea: p25 {q[0]:.0f}  mediana {q[1]:.0f}  p75 {q[2]:.0f}"
              f"  |  crecimiento mediana {statistics.median(r['crece'] for r in filas):,.0f}")


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    s = p.add_subparsers(dest='cmd', required=True)
    f = s.add_parser('fuentes'); f.add_argument('--desde', default='2026-08-01')
    f.add_argument('--pico', type=int, default=120_000); f.add_argument('--top', type=int, default=25)
    g = s.add_parser('slices'); g.add_argument('--desde', default='2026-08-01')
    g.add_argument('--proyecto', default='Bootstrap-Skills')
    a = p.parse_args()
    sys.stdout.reconfigure(encoding='utf-8')
    (cmd_fuentes if a.cmd == 'fuentes' else cmd_slices)(a)


if __name__ == '__main__':
    main()
