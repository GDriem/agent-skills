# Lotes: las `-all`, el tier por tamaño y `bin/agent-batch`

Detalle de cómo corren los lotes. El uso básico está en el [README](../README.md).

## Cómo funcionan las versiones `-all`

El agente principal solo lista las PRs y lanza un agente nuevo por cada una. Ese agente sigue la skill de una
PR completa y termina con un resultado corto y fijo, una línea de JSON (contrato completo en
[ADR-0001](adr/0001-fuente-unica.md)):

```json
{ "skill": "pr-review", "repo": "owner/repo", "pr": 401, "verdict": "REQUEST_CHANGES", "max_priority": "P1",
  "findings": { "blocking": 2, "suggestion": 3, "decision": 0 }, "posted": true,
  "report": "~/.agent-skills/runs/2026-11-02T10-00/pr-review-401.md", "summary": "≤ 60 palabras" }
```

El reporte completo se queda en `~/.agent-skills/runs/<fecha>/<skill>-<n>.md` (o bajo `$AGENT_SKILLS_RUNS`), nunca
dentro del repo revisado. El agente principal nunca ve diffs ni archivos de otra PR, solo esas líneas. Al final
escribe `summary.json` (las líneas de todas las PRs) y `summary.md` (la tabla) en el mismo directorio que los
reportes. Cómo se lanza cada agente depende del harness:

| Harness | Un agente por PR con | Estado |
|---|---|---|
| Claude Code | herramienta `Workflow` (o `Agent`) | probado |
| Codex | `multi_agent` nativo, con `codex exec` por PR como respaldo | probado |
| Copilot CLI y Cursor | subagentes nativos (`/fleet` en Copilot, Task en Cursor) | documentado, pendiente |
| Gemini CLI y Copilot en VS Code | el runner universal, hasta confirmar que sus subagentes corren en paralelo | documentado, pendiente |
| Claude Code y Codex | `bin/pr-batch --harness claude\|codex`, que lanza una sesión headless por PR (`claude -p`, `codex exec`) | probado |

**Costo.** Un agente por PR arranca de cero, así que sin más trabajo las PRs chicas pagan como las grandes. El tier
por tamaño lo corrige: con dos PRs chicas, el lote bajó de 1,71 a 0,65 USD en Claude Code y un 44 % de tokens en
Codex, sin cambiar los veredictos. Lo que se mantiene es que el contexto del agente principal no crece con cada
PR, que las PRs corren en paralelo y que una PR no contamina a la otra. Lo mismo
vale para `orchestrate`: su orquestador tiene un costo fijo que solo compensa con tareas grandes o que
conviene aislar. Números en [token-cost.md](token-cost.md).

## Tier por tamaño

En `pr-review-all` y `bin/pr-batch --skill pr-review`. Con las rutas y los conteos de cada PR,
sin leer el diff, el lote las separa en tres clases:

| Clase | Cuándo | Cómo corre |
|---|---|---|
| trivial | ≤ 20 líneas y ≤ 3 archivos | de a cinco por agente, en serie, tier budget, `--light` |
| small | ≤ 100 líneas y ≤ 8 archivos | un agente por PR, tier budget, `--light` |
| normal | el resto, o cualquier ruta que suene sensible (auth, permisos, secretos, migraciones, pagos, CI, despliegue) | como siempre |

Tier budget: `haiku` en Claude Code y esfuerzo de razonamiento bajo en Codex (o `--small-model`). Si la pasada
ligera ve un posible bloqueante, algo sensible o algo que no puede verificar, no publica nada y el lote revisa esa
PR de nuevo, completa. `summary.md` muestra la clase de cada PR y por qué escaló. `pr-ready-all` no usa clases.

## `bin/agent-batch`

`orchestrate` sin subagentes: una sesión headless por tarea, en olas según las dependencias. Lo usa la skill como
respaldo y sirve desde cron o CI.

```bash
bin/agent-batch --harness codex --tasks graph.json --dry-run       # olas y prompts, sin lanzar nada
bin/agent-batch --harness claude --task "auditar a" --task "auditar b" --wave --task "unir las dos auditorías" --yes
bin/agent-batch --harness claude --tasks graph.json --commit --verify "build=npm run build" --allow-tool "Bash(npm *)" --yes
bin/agent-batch --harness codex --retry-failed ~/.agent-skills/runs/2026-11-02T10-00-orchestrate
```

`--tasks` toma el `graph.json` que escribe la skill. Con `--task`, cada `--wave` corta una ola: las tareas
siguientes dependen de todas las de la ola anterior. Deja `graph.json`, `summary.json` y `summary.md` en el run dir
y sale con código 1 si alguna tarea no terminó `ok`. Comparte con `pr-batch` el arranque de sesiones
(`bin/lib/batch.sh`).
