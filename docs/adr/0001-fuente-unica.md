# ADR-0001: Fuente única en formato Agent Skills, adapters por harness y contrato de resultado por PR

- **Estado:** aceptada. Enmienda de la Sesión 2: el reporte se llama `<skill>-<n>.md` (con `pr-<n>.md`,
  `pr-review` y `pr-ready` sobre la misma PR en el mismo minuto se pisaban; pasó en el smoke), y se agrega
  `--run-dir=<ruta>` para que un lote fije el directorio. Enmienda de la Sesión 5: contrato por tarea para
  `orchestrate` y `bin/agent-batch` (§4 bis). Enmienda del 2026-11-03: tier por tamaño, modo ligero y escalado
  en `pr-review-all` (§4 ter). Enmienda del 2026-11-06: `pr-fix` y `pr-fix-all`, la primera skill que escribe
  código y hace push (§4 quater).
- **Fecha:** 2026-11-02
- **Contexto previo:** [matriz de harnesses](../harness-matrix.md)

## Contexto

Las skills de PR existían en tres copias que ya divergieron. La copia de Claude Code solo
funciona en Claude Code; el port a Codex prohíbe subagentes en las versiones por lote, así que diez PRs comparten
un contexto. Queremos que las mismas skills corran en Claude Code, Codex, Copilot (CLI y VS Code), Gemini CLI y
Cursor, y que cada PR de un lote corra aislada.

La matriz muestra que:

- Los seis aceptan una carpeta con `SKILL.md` y frontmatter `name`/`description`; cinco leen `~/.agents/skills`, y
  Claude Code lee `~/.claude/skills`.
- Solo Claude Code documenta cómo llegan los argumentos (`$ARGUMENTS`).
- Cinco tienen subagentes con contexto propio, pero se lanzan con herramientas distintas, y en dos (Gemini, VS
  Code) el paralelismo no está documentado.
- Los cinco CLIs tienen modo headless, cada uno con su forma de sacar el mensaje final y de pre-aprobar `gh`/`git`.

## Decisión

### 1. Una sola fuente en formato Agent Skills

- `skills/<nombre>/SKILL.md` con frontmatter `name` (igual a la carpeta) y `description`, y nada más que sea propio
  de un harness. Instrucciones largas en `skills/<nombre>/references/*.md`, cargadas bajo demanda.
- El cuerpo nombra **capacidades**, no herramientas: "pregunta al usuario y espera", "lanza un agente nuevo con
  este prompt", "busca archivos por nombre", "escribe un archivo temporal". Ni `Workflow`, ni `Agent`, ni
  `Write tool`, ni `$pr-x` vs `/pr-x`.
- **Argumentos:** "el texto que sigue al nombre de la skill en el mensaje que la invocó". El cuerpo incluye
  `$ARGUMENTS` una vez, para que Claude Code lo sustituya; en los demás harnesses queda como un literal que la
  misma frase explica.
- Las `-all` no duplican la lógica de una PR: le dicen a cada agente que lea la `SKILL.md` hermana por ruta
  absoluta (resuelta en tiempo de ejecución desde la ubicación de la propia skill).
- Metadatos propios de un harness (p. ej. `agents/openai.yaml` de Codex) se generan en la instalación desde el
  adapter; no se versionan (Sesión 4: `install.sh` los escribe en `skills/<n>/agents/`, ignorado por git, para
  que siga habiendo un solo symlink por skill).

### 2. Un adapter por harness

`adapters/<harness>.md` documenta y, donde haga falta, `install.sh` materializa:

| Qué resuelve | Ejemplo |
|---|---|
| Destino de instalación | `~/.claude/skills` (Claude Code), `~/.agents/skills` (los otros cinco) |
| Cómo se cumple cada capacidad | "lanza un agente" = `Workflow`/`Agent` en Claude Code, subagente en Codex/Copilot/Cursor, `bin/pr-batch` si no hay |
| Envoltorios de invocación | comando TOML con `{{args}}` en Gemini, que no tiene `/x` para skills |
| Headless y permisos | flags de `bin/pr-batch` para ese harness |

Las `-all` tienen **un solo cuerpo** con una sección corta "cómo lanzar un agente por PR" que remite al adapter
del harness en curso. Si el harness no tiene subagentes con contexto propio, o no se pueden lanzar desde una
skill, la sección dice que se use `bin/pr-batch`.

### 3. `bin/pr-batch` como respaldo universal

`bin/pr-batch --harness <h> [--repo owner/repo] [--parallel N] [--model M] [--dry-run] [--lang L] [--focus F] <prs|all>`

- Lanza **una sesión headless por PR** (`claude -p`, `codex exec`, `copilot -p`, `gemini -p`,
  `cursor-agent -p`) con el prompt "corre `pr-review <owner/repo#n> --auto …`", pre-aprobando solo `gh` y `git`
  con el mecanismo de cada harness (ver la matriz).
- Toma el contrato (abajo) de la última línea de cada sesión, escribe `summary.json` y una tabla del lote.
- Reintentos: `pr-batch … --retry-failed <run-dir>` vuelve a correr solo las PRs con `ERROR`.
- Sirve desde cron o CI, y es la ruta por defecto en Gemini y VS Code hasta que la Sesión 6 confirme que sus
  subagentes aíslan y corren en paralelo.

### 4. Contrato de resultado por PR

Lo cumplen las **cuatro** skills, también las de una PR, para que el lote nunca tenga que interpretar texto
libre.

- **Reporte completo** en `<runs>/<timestamp>/<skill>-<n>.md`, donde `<runs>` es `$AGENT_SKILLS_RUNS` o, si no
  existe, `~/.agent-skills/runs`. Nunca dentro del repo revisado. `<timestamp>` es `YYYY-MM-DDTHH-MM` de inicio
  del lote (o de la skill si corre sola). El reporte tiene la tabla de hallazgos, el cuerpo del review publicado
  (o el que se habría publicado con `--dry-run`) y, en `pr-ready` LISTA, el comentario de aprobación.
- **Última línea del mensaje final**: un JSON de una línea, sin nada después.

```json
{"skill":"pr-review","repo":"owner/repo","pr":401,"head":"abc1234","verdict":"REQUEST_CHANGES","max_priority":"P1","findings":{"blocking":2,"suggestion":3,"decision":0},"pending":null,"posted":true,"review_url":"https://github.com/owner/repo/pull/401#pullrequestreview-1","report":"/home/u/.agent-skills/runs/2026-11-02T10-00/pr-review-401.md","summary":"≤ 60 palabras","error":null}
```

| Campo | Valores |
|---|---|
| `skill` | `pr-review` o `pr-ready` (las `-all` no emiten líneas propias por PR; reenvían las de sus agentes) |
| `head` | SHA corto revisado |
| `verdict` | `pr-review`: `REQUEST_CHANGES`, `COMMENT`. `pr-ready`: `READY`, `NOT_READY`. Ambas: `ERROR`, `SKIPPED` (draft, cerrada o mergeada) |
| `max_priority` | `P0`–`P3` o `null` si no hay hallazgos |
| `findings` | conteos tras verificar y deduplicar; en `pr-ready` son los gaps nuevos |
| `pending` | solo `pr-ready`: hilos no `ATENDIDO`/`DESCARTADO OK`; `null` en `pr-review` |
| `posted` | `true` si se escribió en GitHub; siempre `false` con `--dry-run` y en `pr-ready` `READY` |
| `summary` | ≤ 60 palabras, en el idioma de la PR |
| `error` | motivo si `verdict` es `ERROR` o `SKIPPED`; si no, `null` |

Los valores de `verdict` van en inglés aunque la PR sea en español: son para máquinas. Lo que lee una persona
(reporte, comentarios, `summary`) va en el idioma de la PR.

### 4 bis. Contrato por tarea (`orchestrate`, Sesión 5)

`orchestrate` no trabaja sobre PRs sino sobre un grafo de tareas, pero sigue el mismo patrón: el orquestador solo
ve una línea de JSON por tarea, y un runner headless (`bin/agent-batch`) produce lo mismo que los subagentes
nativos. El detalle está en `skills/orchestrate/references/contract.md`.

- **Prompt fijo por tarea**: el de la tarea más unas reglas de ejecución (solo lectura o fence de escritura,
  criterio de "hecho", conclusiones y artefactos de sus dependencias, dónde escribir lo largo, la línea final).
  La skill, el script de `Workflow` del adapter y `bin/agent-batch` arman el mismo texto.
- **Línea final**:
  `{"skill":"orchestrate","task":"t1","kind":"read","status":"ok","summary":"≤ 60 palabras","files_changed":[],"artifacts":[],"follow_ups":[],"error":null}`.
  `status` del agente: `ok` o `failed`; el orquestador sintetiza `blocked` (dependencia que no terminó `ok`, o
  ciclo) y `skipped` (nunca lanzada). Con `--commit` agrega `commit` (`committed`, `sha`, `error`).
- **Run dir**: `<runs>/<timestamp>-orchestrate` (o `--run-dir`) con `graph.json`, los `orchestrate-<id>.md` que
  escriban las tareas, `summary.json` (`{"tasks":[…],"verify":…}`) y `summary.md`.
- **Línea del run**: `skill`, `run_dir`, `graph`, `total`, `counts` (`ok`/`failed`/`blocked`/`skipped`),
  `failed` (ids a re-lanzar con `--only`), `dry_run`, `commits`, `verify`, `summary_json`, `summary_md`.
- **Tiers en vez de modelos**: `small|default|large` + `effort`; cada adapter dice qué significan.
- `bin/agent-batch` comparte con `bin/pr-batch` el arranque de sesiones headless (`bin/lib/batch.sh`), así que
  agregar un harness al runner lo agrega a los dos.

### 4 ter. Tier por tamaño y escalado (`pr-review-all`, 2026-11-03)

Medido en la Sesión 6: con PRs chicas, un agente por PR gastaba más del doble que revisarlas en serie, y casi
todo era de los hijos (cada llamada relee la skill, sus referencias y las convenciones). El aislamiento se
mantiene, pero el costo pasa a depender del tamaño:

- **Clases**, calculadas por el orquestador con rutas y conteos de `gh` (nunca el diff): `trivial` (≤ 20 líneas,
  ≤ 3 archivos), `small` (≤ 100, ≤ 8) y `normal`. Una ruta que suena sensible (auth, permisos, secretos,
  migraciones, pagos, CI, despliegue) la deja en `normal`, sea del tamaño que sea.
- `small` y `trivial` corren con el tier budget del adapter y `pr-review --light`. Las `trivial` van de a cinco por
  agente, en serie; las `normal` siguen como antes. `--no-tiering` vuelve a lo de antes.
- **Escalado**: una corrida ligera que ve un candidato P0/P1, un cambio de comportamiento en auth, montos,
  escrituras destructivas, migraciones o secretos, o un defecto sospechado que no puede verificar dentro del
  límite termina con `escalate: true` y **no publica**, aunque tenga `--auto`. Escalar "por las dudas" no vale: la
  primera regla, más amplia, hizo escalar a Codex 2 de 6 PRs sin sospechar nada. El orquestador relanza esa PR
  una sola vez como `normal`. Así el tamaño elige el modelo, pero no baja el criterio, y nunca hay dos reviews.
- **Contrato**: campos opcionales `light`, `escalate` y `escalate_reason` en la línea de `pr-review`; el
  `summary.json` del lote agrega `tier` y `escalated` a cada línea. Una línea sin los campos nuevos sigue siendo
  válida.
- `pr-ready-all` no cambia: `pr-ready` no tiene modo ligero.

### 4 quater. `pr-fix`: la primera skill que escribe (2026-11-06)

`pr-review` y `pr-ready` nunca tocan el árbol; `pr-fix` corrige lo que pidieron los revisores y el CI y lo empuja a
la rama de la PR. Para que eso no rompa nada de lo anterior:

- **Worktree propio por PR**, desprendido en el head (`git worktree add --detach`), bajo
  `$AGENT_SKILLS_WORKTREES` o `~/.agent-skills/worktrees`, nunca dentro del run dir. El árbol del usuario no se
  toca, y en lote cada agente tiene el suyo. El fetch es `refs/pull/<n>/head` con `--no-write-fetch-head`: no
  actualiza ninguna ref, así que varios agentes sobre el mismo clon no se pisan. Requiere un clon local; la skill
  nunca clona.
- **La historia solo avanza**: `git push` simple de commits nuevos sobre el head. Nunca force, amend ni rebase de
  algo empujado, nunca `--no-verify`. Si la rama se movió durante la corrida, no empuja y deja el worktree.
- **Sin atribución a la IA**: ni commits ni respuestas llevan `Co-Authored-By`, `Generated with` ni mención de
  Claude, Copilot, Codex, Gemini, Cursor u otra herramienta, aunque el harness la agregue por defecto. Después de
  cada commit revisa el mensaje (un hook o el harness pueden sumar un trailer) y, antes del push, todos los del
  rango.
- **Hilos**: responde en cada uno con el commit, pero **nunca lo resuelve**; eso lo decide el revisor y lo audita
  `pr-ready`.
- **Personas antes que suposiciones**: un `[DECISION]`, un comentario que cree incorrecto, un conflicto con una
  regla del proyecto, algo fuera de alcance o una dependencia nueva se pregunta. Sin nadie a quien preguntar
  (lote, `--auto`) queda `PENDING` con su propuesta entre `<!-- pending:start -->` y `<!-- pending:end -->`, que
  el lote copia a `summary.md`, igual que la aprobación de `pr-ready`.
- **Convenciones del proyecto**: antes de editar busca y aplica las skills, agentes y reglas con alcance del propio
  repo (`.claude/skills`, `.agents/skills`, `.github/instructions`, `.cursor/rules`, …), además de los archivos de
  contexto que ya leían las otras skills. Se leen como convenciones, no como flujos: nunca pasan por encima de las
  reglas de `pr-fix`.
- **Sin huecos nuevos**: cada línea cambiada se justifica con un ítem, test para cada defecto, checks del repo al
  final (distinguiendo fallas previas) y una autorrevisión del diff propio con el mismo `quality-gate.md`.
- **Contrato** propio (`skills/pr-fix/references/contract.md`): mismo reporte y misma línea final, con `new_head`,
  `items` (`fixed`, `already_done`, `answered`, `pending`, `failed`), `commits`, `pushed`, `checks` y `worktree`.
  Veredictos `FIXED`, `PARTIAL`, `NOTHING_TO_FIX`, `PLANNED` (`--dry-run`), `ERROR`, `SKIPPED`.
- **Lote**: `pr-fix-all` usa el mismo `batch.md` que las otras `-all`, sin tiers, con `--parallel` 2 por defecto
  (cada agente instala dependencias y corre checks). `all` son **tus** PRs con feedback; las de otros, con
  `--any-author`. Las tres `-all` y `bin/pr-batch` aceptan además rangos (`401-410`), filtrados contra las PRs
  abiertas porque issues y PRs comparten numeración.

### 5. Reglas que no cambian por harness

- Ninguna skill aprueba ni mergea una PR, ni resuelve un hilo.
- `--auto` quita la pausa de confirmación, nada más: no relaja verificación, anclaje ni "un solo review por PR".
- `--dry-run` hace todo menos escribir en GitHub e implica no preguntar.
- Nada de un proyecto concreto en este repo; las convenciones se descubren al ejecutar.

## Alternativas descartadas

- **Una copia por harness** (como hasta ahora): ya divergió en dos meses.
- **Generar cada copia desde una plantilla con variables**: añade un paso de build y un lenguaje de plantillas
  para resolver diferencias que caben en un adapter de una página.
- **Solo `bin/pr-batch`, sin subagentes nativos**: funciona en todos, pero pierde la conversación interactiva
  (no se puede ajustar un hallazgo y seguir) y paga el arranque de una sesión entera por PR.
- **Lote en un solo contexto** (port de Codex): es justo lo que este proyecto quiere eliminar; el costo por PR
  crece con cada PR anterior.
- **Reporte en el repo revisado** (`./runs/`): ensucia el árbol de trabajo de otro proyecto.

## Consecuencias

- La Sesión 2 escribe `pr-review`/`pr-ready` contra capacidades y el contrato, y los adapters de Claude Code y
  Codex.
- `install.sh` instala en dos destinos (`~/.claude/skills`, `~/.agents/skills`) y tiene que detectar el
  duplicado que ven Copilot VS Code y Cursor (leen los dos).
- El soporte de Gemini depende de un envoltorio TOML y queda en duda por el reemplazo por Antigravity CLI.
- Lo marcado "sin confirmar" en la matriz se prueba antes de depender de ello.
