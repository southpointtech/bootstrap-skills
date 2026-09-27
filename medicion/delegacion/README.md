# Experimento: delegar la implementación a subagentes

Compromiso previo, congelado **antes** de correr el primer slice tratado (2026-09-27). Si hay que
cambiar algo de lo que sigue, se cambia en un commit propio y antes de mirar un resultado.

## La pregunta

¿Hacer que la sesión principal orqueste y un subagente implemente cada tarea
(`superpowers:subagent-driven-development`) estira cuánto trabajo entra en una sesión antes del
handoff, sin empeorar lo que el review-loop encuentra?

## Por qué esto y no "delegar todo"

`python medicion/delegacion/contexto.py fuentes` sobre las 296 sesiones principales desde el
2026-08-01 que pasaron los 120k de contexto (corrida del 2026-09-27). Crecimiento del contexto de la
principal, por fuente:

| Fuente | Parte |
|---|---|
| Lo que escribe la propia principal (thinking, comandos, Edit/Write, texto, pedidos a subagentes) | ~46 % |
| Prompts del usuario, skills y hooks cargados, adjuntos del harness | ~25 % |
| Salida de Bash y PowerShell | 19,2 % |
| Salida de Read | 4,7 % |
| Lo que devuelven los subagentes (`tool:Agent`) | 1,8 % |

Delegar solo lo ruidoso (lecturas amplias, búsquedas, suites) ataca una fracción chica, porque
muchas lecturas preceden a una edición y no se pueden delegar. Lo grande es lo que la principal
escribe, y eso solo sale de su contexto si sale la implementación. Delegar tiene un peaje por
tarea: en las sesiones principales desde el 2026-08-01, los 3.324 pedidos a subagentes suman 2,5
veces los caracteres de lo que esos subagentes devolvieron (9,0 M contra 3,6 M).

## Métrica

`python medicion/delegacion/contexto.py slices`: por sesión, crecimiento del contexto de la
principal desde su primera llamada hasta el primer commit con `Slice-Close:`, dividido por las
líneas (adiciones + borrados) de ese commit. El método completo está en el docstring del script.

**Línea base** (corrida del 2026-09-27, proyecto `Bootstrap-Skills`, primer slice de cada sesión):
n = 31 con líneas, de 32. Tokens por línea: **p25 287, mediana 482, p75 1.342**; crecimiento
absoluto mediano 110.411 tokens.

## Protocolo

1. **Tratamiento**: los **3 próximos slices** de este repo que cierren con `Slice-Close:`, sin
   elegirlos. Cada uno arranca en una sesión nueva y se implementa con
   `superpowers:subagent-driven-development`: la principal planifica, despacha y verifica; no edita
   archivos de producción ni de test ella misma.
2. **Éxito**: la mediana de tokens por línea de los 3 tratados es **≤ 371** (la mediana de la línea
   base, 482, dividida por 1,3).
3. **Freno de calidad**: si en un slice tratado el review-loop encuentra algo que el subagente
   declaró hecho y no estaba hecho, se anota; con 2 de 3 slices así el experimento se da por
   fallido aunque cumpla el número.
4. **Qué no concluye**: 3 slices contra una base tan dispersa (p25–p75 de 287 a 1.342) sirven para
   descartar o para seguir midiendo, no para adoptar la regla en el scaffold. Adoptarla es otra
   decisión, con más slices.

## Límites conocidos del método

- Los commits hechos con `git commit -F archivo` no se detectan (el `Slice-Close:` no está en el
  comando). Para los slices tratados, commitear con `-m`.
- El reparto del output entre thinking, texto y tool_use no sirve: el transcript graba los bloques
  de thinking vacíos (28 de 30 en una sesión revisada el 2026-09-27), así que el thinking queda
  repartido entre los otros bloques del mismo mensaje. El total del output (~46 %) sí sale del
  `usage` y es exacto.
- Tokens por línea castiga los slices chicos: un slice de 17 líneas que igual lee mucho da 1.342.
