// ¿El parser de hallazgos de claude-analytics (finding-rules) ve los reportes de los dos brazos?
// Cuenta, por brazo, los reportes con 0 hallazgos parseados que igual nombran una severidad.
//
//   cd <checkout de claude-analytics en master>
//   node --import tsx <este archivo, .mts por el top-level await> <dir-de-salida-de-filtrar> <borde ISO>
//
// Es una cota gruesa, no un conteo de hallazgos perdidos: un reporte que dice "no High
// findings" nombra una severidad sin tener un hallazgo.
import * as fs from "node:fs";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const [dir, bordeIso] = process.argv.slice(2);
if (!dir || !bordeIso) throw new Error("uso: auditar.ts <dir> <borde ISO>");
const BORDE = Date.parse(bordeIso);
if (!Number.isFinite(BORDE)) throw new Error(`borde inválido: ${bordeIso}`);
const { classifyReport } = await import(pathToFileURL(path.resolve("src/lib/finding-rules.ts")).href);

const SEV = /\b(high|medium|alta|media|critical|blocking)\b/i;
for (const conj of ["bs-main", "bs-todos"]) {
  const cuenta: Record<string, number> = {};
  for (const l of fs.readFileSync(path.join(dir, conj, "agents.jsonl"), "utf8").split("\n").filter(Boolean)) {
    const r = JSON.parse(l);
    const rep: string = r.report ?? "";
    const k = [
      Date.parse(r.t0) < BORDE ? "antes" : "desde",
      classifyReport(rep).findings.length > 0 ? "con-parseados" : "sin-parseados",
      SEV.test(rep) ? "nombra-severidad" : "no-nombra",
    ].join(" ");
    cuenta[k] = (cuenta[k] ?? 0) + 1;
  }
  console.log(conj, JSON.stringify(cuenta, Object.keys(cuenta).sort()));
}
