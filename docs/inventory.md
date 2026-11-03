# Inventario de las copias existentes (2026-11-02)

Base de la Fase 1. Compara, paso por paso, las tres copias de los comandos de PR que había antes de este repo y
decide qué versión de cada paso pasa al core. Ninguna copia se modificó; reemplazarlas es la Fase 3.

## Las tres copias

| Id | Dónde | Qué contiene |
|---|---|---|
| **G** (global Claude) | `~/.claude/commands/pr-{review,ready,review-all,ready-all}.md` | Las 4. Ya son agnósticas al repo: detectan repo, usuario y convenciones al ejecutarse. Las `-all` usan `Workflow` con un agente por PR, en serie. |
| **R** (repo de trabajo) | `<repo>/.claude/commands/pr-{review,ready}.md` y `<repo>/.claude/backup-pr-commands/pr-*-all.md` | Versión anterior de G con datos del proyecto escritos a mano: logins del equipo, rutas de apps, tracker, manifiestos de despliegue, convención de títulos de issues y el repo fijo en las `-all`. |
| **C** (port a Codex, 2026-09-22) | `~/.codex/prompts/pr-*.md` y `~/.codex/skills/pr-*/{SKILL.md,references/*.md,agents/openai.yaml}` | G más las mejoras de `codex /review`. Las `-all` prohíben subagentes y recorren las PRs en un solo contexto. |

Duplicación dentro de C: solo hay **4 textos distintos**. `prompts/pr-X.md`, `skills/pr-X/references/workflow.md` y
`skills/pr-X-all/references/item-workflow.md` son idénticos byte a byte; `prompts/pr-X-all.md` es idéntico a
`skills/pr-X-all/references/bulk-workflow.md`. Cada `SKILL.md` es un envoltorio de ~15 líneas que dice "lee
`references/…` y síguelo", traduce `$ARGUMENTS` a "el texto después de `$pr-X`" y repite dos reglas duras (no
aprobar, confirmar antes de escribir en GitHub). `agents/openai.yaml` solo tiene `interface` (`display_name`,
`short_description`, `default_prompt`).

**R no aporta nada que se conserve.** Todo lo que tiene, G lo tiene generalizado (detección en vez de datos
fijos). Sus datos propios no entran en este repo bajo ninguna forma. En las tablas, la columna R solo marca
dónde difería.

Leyenda de "Se queda": **G**, **C**, **G+C** (fusión), **nuevo** (lo decide este inventario), **fuera**.

## pr-review

| # | Paso | G | R | C | Se queda | Por qué |
|---|---|---|---|---|---|---|
| 0 | Argumentos | número, `owner/repo#N`, URL, vacío; `--auto`, `--lang` | sin `owner/repo#N` ni `--lang` | G + `--focus="<criterio>"` | C, más `--dry-run` (nuevo) | `--focus` acota sin apagar la revisión general. `--dry-run` lo pide el plan para los smokes. |
| 0 | Resolver contexto | `git rev-parse`, `gh repo view`, `gh api user`; para si alguno falla; draft → preguntar; autor = yo → `COMMENT` | autor fijo por login | igual que G | G | Agnóstico. Draft "preguntar" pasa por la capacidad *ask* del adapter; en modo lote (sin humano) se salta con `ERROR`/omitido. |
| 0 | Idioma | `--lang`, si no el de los comentarios humanos, si no el del archivo de contexto raíz | siempre español | igual que G | G | — |
| 0 | Focus | — | — | texto literal, se aplica después de las 6 categorías, nunca suprime un bloqueante | C | — |
| 1 | Recolectar | `gh pr view/diff/checks`, commits, GraphQL de hilos | sin `--repo` | G + `baseSha`/`headSha` | C | Los SHA hacen falta para el paso 1a. |
| 1 | Bots vs humanos | por datos (`[bot]`, `Copilot`, `coderabbitai`…) | roster fijo de logins | igual que G | G | — |
| 1a | Alcance | (implícito: el diff de la PR) | — | merge-base→head SHA; no cambiar de rama ni tocar el árbol; refrescar si cambia el head; solo lo que la PR introduce o empeora | C | Es la mejora principal del port: evita reportar deuda vieja y reseñas sobre un head obsoleto. Se quita la mención a "`codex /review`" del título. |
| 1b | Convenciones | `CLAUDE.md`, `AGENTS.md`, `.claude/pr-conventions.md`, `CONTRIBUTING.md`, `.github/copilot-instructions.md`; contexto anidado por archivo cambiado con `git ls-files`/`Glob`; stack; tracker si hay herramienta | archivos de contexto fijos | G, con `AGENTS.md` antes que `CLAUDE.md` en el anidado y `rg --files` | G+C, ampliado | Agregar `GEMINI.md` y `.cursor/rules/` a la lista (ver la matriz). Buscar con "la herramienta de búsqueda de archivos del harness, o `git ls-files`". El archivo de convenciones de review se queda en `.claude/pr-conventions.md` y se acepta también `.agents/pr-conventions.md` (nuevo). |
| 2 | Leer el código | archivo completo + colaboradores; callers; helper duplicado; test vecino | ejemplos propios del proyecto | igual que G | G | — |
| 3 | Prioridad de categorías | correctness → data → security → contracts → conventions → reuse | ejemplos propios | igual que G | G | — |
| 4 | Verificar | argumentar en contra, ruta de fallo concreta | — | G + quality gate P0–P3, "introducido aquí", accionable, evidencia, alta confianza o `[DECISION]`, ancla mínima 1–5 líneas, sin ruido de linter | C | Baja falsos positivos. Se conserva el mapeo P0/P1 → bloqueante, P2 según riesgo, P3 → sugerencia. |
| 5 | Dedupe con bots y tags | tags del archivo de convenciones o por idioma | solo Copilot, tags en español | igual que G | G | — |
| 6 | Redactar | sin firma ni mención a herramientas; bloque `suggestion`; plantillas | — | igual (sin backticks anidados en el bloque `suggestion`) | C | La redacción de C evita romper el fence del markdown. |
| 7 | Preview y confirmar | tabla `# \| Tag \| file:line \| Finding`; evento; cuerpo | — | tabla con columna Prioridad, ordenada P0→P3 | C | En `--dry-run` el preview es la salida final y no se pregunta nada. |
| 8 | Publicar | un solo review; payload con "the Write tool" al scratchpad | — | archivo temporal único con `mktemp`/PowerShell, nunca JSON inline | **nuevo** | Neutral: "escribe el payload a un archivo temporal único y pásalo con `--input`". Sin nombrar herramientas ni el SO. Reglas de anclaje de línea y 422 iguales en G y C. |
| 9 | Reportar | URL, conteos, evento, fallos, CI; ofrecer mover tarea | ofrece mover la tarea del tracker propio | G + "sin hallazgos → dilo y da el riesgo residual; no inventes una sugerencia" | C + contrato | Además escribe el reporte en `runs/<fecha>/pr-<n>.md` y termina con la línea JSON del contrato (ADR-0001). |
| — | Convenciones de issues/PRs | las que encuentre en 1b; si no, imitar issues recientes | convención de títulos propia del equipo | igual que G | G | — |

## pr-ready

| # | Paso | G | R | C | Se queda | Por qué |
|---|---|---|---|---|---|---|
| 0 | Argumentos | número, `owner/repo#N`, URL, vacío; `--auto`, `--lang` | sin `owner/repo#N` ni `--lang` | G + `--focus` (solo para el barrido de gaps) | C, más `--dry-run` | — |
| 0 | Contexto | igual que pr-review | login fijo | igual | G | — |
| 1 | Estado del review | GraphQL con reviews, hilos, `mergeable`, rollup de checks; commits con fecha | sin `--repo` | G + `baseRefOid`/`headRefOid` | C | — |
| 1 | Commits de fix | commits posteriores a cada `submittedAt`; `git diff` local, o `gh` + `contents` si la PR es de otro repo | sin el caso de otro repo | igual que G | G | — |
| 1a | Alcance | — | — | review fresca merge-base→head: diff completo **y** delta de fixes; fijar el head; solo lo que introduce la PR | C | El delta encuentra regresiones; el diff completo, interacciones y gaps originales. |
| 1b | Convenciones | lista de G | fija | G con `AGENTS.md` primero y `rg --files` | G+C, ampliado | Igual que en pr-review. |
| 2 | Auditar hilos sobre el código | 6 estados (`ATENDIDO`, `PARCIAL`, `NO ATENDIDO`, `DESCARTADO OK`, `DESCARTADO SIN BASE`, `SIN RESPONDER`), traducir etiquetas | sin la nota de traducción | igual que G | G | — |
| 3 | Barrido de gaps | regresiones, rama paralela, tests, contratos, migraciones según cómo las aplique el repo, convenciones documentadas, tracker, CI | reglas del proyecto escritas a mano | G + quality gate P0–P3 (P3 nunca bloquea salvo regla del repo) | C | — |
| 4 | Tabla de auditoría | hilos + gaps + CI | — | gaps con columna Prioridad | C | — |
| 5 | Veredicto | LISTA si 0 pendientes, 0 bloqueantes nuevos, CI verde | — | igual | G | — |
| 5a | Si LISTA | **nunca aprueba**; entrega el comentario de aprobación para pegar | en español fijo | igual que G | G | Regla dura del proyecto. |
| 5b | Si NO LISTA | preview, un review, responder en el hilo existente, payload con "Write tool" | — | payload con archivo temporal | **nuevo** (igual que pr-review paso 8) | — |
| 6 | Reportar | veredicto, conteos, URL, CI; recordar que la aprobación la pega el usuario | tracker propio | G + "sin pendientes → dilo con riesgo residual" | C + contrato | — |

## pr-review-all y pr-ready-all

G y C son casi idénticas entre `review-all` y `ready-all` (cambian el comando base, el esquema y el reporte). Se
reconcilian juntas.

| # | Paso | G | R | C | Se queda | Por qué |
|---|---|---|---|---|---|---|
| 0 | Argumentos | lista `401,405`, `--repo owner/repo` | sin `--repo` | G + reenvía `--lang` y `--focus` a cada PR | C, más `--parallel N`, `--model M`, `--dry-run` | El plan pide paralelismo y modelo configurables. |
| 0 | Repo | detectado o `--repo`; para si no hay remoto | fijo | igual | G | — |
| 0 | Ubicar la skill de una PR | primera que exista de `<root>/.claude/commands/` y `~/.claude/commands/`, ruta absoluta | ruta relativa fija | 5 rutas entre `.codex/prompts` y `.claude/commands` | **nuevo** | Con fuente única, la `-all` referencia la skill hermana instalada (`../pr-review/SKILL.md`, resuelta a absoluta por el adapter). Se acaba la búsqueda en rutas de comandos viejos. |
| 1 | Listar PRs | un agente corre `gh pr list` | igual | `gh pr list --limit 100`, paginar si llega a 100, excluir drafts; validar y deduplicar números explícitos conservando el orden | C | Sin paginar se pierden PRs en silencio. La lista la hace el orquestador directo, sin gastar un agente. |
| 1 | Anunciar | repo, conteo, ruta del comando base | conteo | + orden de PRs | C | — |
| 2 | Ejecución | `Workflow`, `for…of` con `await`: **un agente por PR, en serie** | igual | **prohíbe subagentes**: un solo contexto, en serie | G, con `--parallel N` (nuevo, por defecto bajo) | El aislamiento por PR es el objetivo del proyecto; lo de C se descarta. La serie estricta de G era por rate limit de GitHub y salida entrelazada: el contrato JSON resuelve la salida y un tope bajo de concurrencia resuelve el rate limit. |
| 2 | Antes de cada PR | — | — | re-chequear que siga abierta y no draft | C | Evita revisar una PR mergeada a mitad del lote. |
| 2 | Prompt al agente | "lee `<base-cmd>` y síguelo con `--auto`; `--repo` explícito en cada `gh`; prompt autocontenido; nunca aprobar" | — | mismas reglas en texto; `--auto` no relaja verificación ni anclaje | G+C | Se conservan las aclaraciones de C sobre qué **no** relaja `--auto`. |
| 2 | Resultado por PR | esquema propio por comando (`event`/`blockers`… vs `verdict`/`pendientes`…), claves en español | — | campos en texto libre + prioridad máxima | **nuevo**: contrato único | JSON de una línea común a las 4 skills (ADR-0001). |
| 2 | Fallo de una PR | `ERROR` + motivo, sigue | igual | igual | G | — |
| 3 | Reporte | tabla; errores aparte; reintentar con números o `resumeFromRunId` | — | tabla con Prioridad máxima; bloque de aprobación por PR LISTA en ready-all | C | El bloque de aprobación sale del reporte por PR, no del contexto del orquestador. `resumeFromRunId` queda solo en el adapter de Claude Code. |

## Qué se descarta

- La prohibición de subagentes y el bucle en un solo contexto de las `-all` de C.
- Cualquier dato del proyecto de R (logins, rutas, tracker, despliegue, títulos).
- Nombres de herramientas propias de un harness dentro del core (`Workflow`, `Write tool`, `Glob`, `Grep`,
  `rg --files` como único camino, `$pr-X` vs `/pr-X`). Pasan a los adapters o se describen por capacidad.
- Las rutas `.claude/commands` y `.codex/prompts` como lugar de la skill base. Los prompts de Codex están
  deprecados (ver la matriz).

## Pendiente para la Sesión 2

- Traducir al inglés los títulos de los pasos del core; las plantillas de comentario siguen en el idioma de la PR
  (español e inglés de ejemplo).
- Decidir el valor por defecto de `--parallel` (propuesta: 3) y documentar que se puede bajar a 1.
