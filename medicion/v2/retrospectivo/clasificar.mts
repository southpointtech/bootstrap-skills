// Aplica el clasificador de reviewers de claude-analytics (focus-rules) a las copias
// filtradas y cuenta, por brazo, cuántos subagentes reconoce como reviewer.
//
//   cd <checkout de claude-analytics en master>
//   node --import tsx <este archivo, .mts por el top-level await> <dir-de-salida-de-filtrar> <borde ISO>
//
// Se usa para decidir el denominador: el clasificador es del 2026-09-04 y no reconoce los
// prompts de /slice-review de ninguno de los dos brazos (ver REPORTE.md).
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const [dir, bordeIso] = process.argv.slice(2);
if (!dir || !bordeIso) throw new Error("uso: clasificar.ts <dir> <borde ISO>");
const BORDE = Date.parse(bordeIso);
if (!Number.isFinite(BORDE)) throw new Error(`borde inválido: ${bordeIso}`);
const { classifyPrompt } = await import(pathToFileURL(path.resolve("src/lib/focus-rules.ts")).href);

for (const conj of ["bs-main", "bs-todos"]) {
  const cuenta: Record<string, number> = {};
  for (const l of fs.readFileSync(path.join(dir, conj, "agents.jsonl"), "utf8").split("\n").filter(Boolean)) {
    const r = JSON.parse(l);
    const c = classifyPrompt(r.prompt ?? "");
    const k = `${Date.parse(r.t0) < BORDE ? "antes" : "desde"} reviewer=${c.is_reviewer}`;
    cuenta[k] = (cuenta[k] ?? 0) + 1;
  }
  console.log(conj, JSON.stringify(cuenta));
}
