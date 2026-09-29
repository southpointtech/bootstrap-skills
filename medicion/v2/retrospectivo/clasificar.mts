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
// El rol va anclado a la frase de identidad: un verbo suelto ("encontrás") o "del review del
// carril" atrapaban reviewers.
const NO_REVIEW = /^\W*Sos el \**(carril|implementador)\b|^\W*(Buscá|Necesito) /i;

for (const conj of ["bs-main", "bs-todos"]) {
  const cuenta: Record<string, number> = {};
  for (const l of fs.readFileSync(path.join(dir, conj, "agents.jsonl"), "utf8").split("\n").filter(Boolean)) {
    const r = JSON.parse(l);
    const c = classifyPrompt(r.prompt ?? "");
    const brazo = Date.parse(r.t0) < BORDE ? "antes" : "desde";
    const k = `${brazo} reviewer=${c.is_reviewer}`;
    cuenta[k] = (cuenta[k] ?? 0) + 1;
    // Cota de los subagentes que NO son review, independiente del clasificador: los que
    // nombran otro rol en el arranque del prompt.
    if (NO_REVIEW.test((r.prompt ?? "").replace(/\s+/g, " ").slice(0, 160))) {
      cuenta[`${brazo} no-review`] = (cuenta[`${brazo} no-review`] ?? 0) + 1;
    }
  }
  console.log(conj, JSON.stringify(cuenta));
}
