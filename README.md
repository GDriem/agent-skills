# agent-skills

Skills personales de code review y orquestación que funcionan igual en varios harnesses de agentes:
**Claude Code, Codex, GitHub Copilot (CLI y VS Code), Gemini CLI y Cursor**.

Hay una sola fuente: cada skill es una carpeta `skills/<nombre>/SKILL.md` en el formato abierto de Agent
Skills, y un script la instala en cada harness. Las versiones por lote (`-all`) corren **cada PR en un agente
aparte con su propio contexto**, así que revisar diez PRs cuesta lo mismo por PR que revisar una.

> **Estado:** en construcción. Ver [PLAN.md](PLAN.md). Hasta que cierre la Fase 3, las secciones de
> instalación y uso describen cómo va a quedar, no lo que ya funciona.

## Skills

| Skill | Qué hace | Escribe en GitHub |
|---|---|---|
| `pr-review <PR>` | Primera pasada: hallazgos como comentarios in-line (`[BLOQUEANTE]`, `[SUGERENCIA]`, `[DECISION]`), sin repetir lo que ya marcó Copilot u otro bot | Sí, después de confirmar |
| `pr-ready <PR>` | Segunda pasada: confirma, leyendo el código en head, que cada hilo quedó atendido, busca huecos en los commits de fix y da veredicto. **Nunca aprueba**: si la PR está lista, te entrega el comentario de aprobación para que lo pegues tú | Solo comentarios de pendientes |
| `pr-review-all` | `pr-review` para todas las PRs abiertas que no son draft, o para una lista. Un agente por PR | Sí |
| `pr-ready-all` | `pr-ready` en lote. Un agente por PR | Solo pendientes |
| `orchestrate` | Parte un prompt con varias tareas en un grafo de dependencias y lo ejecuta con una flota de agentes | Según la tarea |

Todas detectan el repo, el usuario y las convenciones en tiempo de ejecución, sin nada propio de un proyecto
escrito en la skill. Por defecto escriben en el idioma de la PR; `--lang=en|es` lo fuerza.

## Requisitos

- `git` y `gh` autenticado (`gh auth status`)
- `jq`
- Al menos uno de estos harnesses: `claude`, `codex`, `copilot`, `gemini` o `cursor-agent`

## Instalación

```bash
git clone git@github.com:GDriem/agent-skills.git ~/Source/agent-skills
cd ~/Source/agent-skills
./install.sh                     # detecta qué harnesses tienes y los instala en todos
./install.sh --harness codex     # solo uno
./install.sh --check             # dice qué está instalado y si algo quedó desactualizado
./install.sh --uninstall
```

`install.sh` crea symlinks, no copias, así que un `git pull` deja todo al día. Bastan dos destinos a nivel
usuario, porque todos los harnesses menos Claude Code leen `~/.agents/skills`:

| Harness | Carpeta de skills | Cómo se invoca |
|---|---|---|
| Claude Code | `~/.claude/skills/` | `/pr-review 401` |
| Codex | `~/.agents/skills/` | `$pr-review 401` |
| GitHub Copilot (CLI y VS Code) | `~/.agents/skills/` | `/pr-review 401` |
| Gemini CLI | `~/.agents/skills/` + comando en `~/.gemini/commands/` | `/pr-review 401` (el comando activa la skill; Gemini no invoca skills con `/`) |
| Cursor | `~/.agents/skills/` | `/pr-review 401` |

Copilot en VS Code y Cursor también leen `~/.claude/skills`, así que pueden ver cada skill dos veces;
`install.sh --check` lo avisa. Detalle y fuentes en [docs/harness-matrix.md](docs/harness-matrix.md).

## Uso

```text
pr-review 401                    # una PR del repo del directorio actual
pr-review owner/repo#401         # otro repo
pr-review                        # la PR de la rama actual
pr-review 401 --auto             # publica sin pedir confirmación
pr-review 401 --dry-run          # hace todo menos escribir en GitHub

pr-ready 401

pr-review-all                    # todas las abiertas que no son draft
pr-review-all 401,405,410        # solo esas (útil para reintentar fallidas)
pr-review-all --repo owner/repo 12,15
```

### Cómo funcionan las versiones `-all`

El agente principal solo lista las PRs y lanza un agente nuevo por cada una. Ese agente sigue la skill de una
PR completa y termina con un resultado corto y fijo, una línea de JSON (contrato completo en
[ADR-0001](docs/adr/0001-fuente-unica.md)):

```json
{ "skill": "pr-review", "repo": "owner/repo", "pr": 401, "verdict": "REQUEST_CHANGES", "max_priority": "P1",
  "findings": { "blocking": 2, "suggestion": 3, "decision": 0 }, "posted": true,
  "report": "~/.agent-skills/runs/2026-11-02T10-00/pr-401.md", "summary": "≤ 60 palabras" }
```

El reporte completo se queda en `~/.agent-skills/runs/<fecha>/pr-<n>.md` (o bajo `$AGENT_SKILLS_RUNS`), nunca
dentro del repo revisado. El agente principal nunca ve diffs ni archivos de otra PR, solo esas líneas. Cómo se
lanza cada agente depende del harness:

| Harness | Un agente por PR con |
|---|---|
| Claude Code | herramienta `Workflow` (o `Agent`) |
| Codex | `multi_agent` nativo, con `codex exec` por PR como respaldo |
| Copilot CLI y Cursor | subagentes nativos (`/fleet` en Copilot, Task en Cursor) |
| Gemini CLI y Copilot en VS Code | el runner universal, hasta confirmar que sus subagentes corren en paralelo |
| Cualquiera | `bin/pr-batch --harness <h>`, que lanza una sesión headless por PR (`claude -p`, `codex exec`, `copilot -p`, `gemini -p`, `cursor-agent -p`) |

## Estructura

```text
skills/<nombre>/SKILL.md     fuente única, sin herramientas propias de un harness
skills/<nombre>/references/  instrucciones largas que se cargan bajo demanda
adapters/<harness>.md        cómo se lanza un subagente y dónde se instala, por harness
bin/pr-batch                 runner universal: una sesión headless por PR
install.sh                   instala en cada harness y detecta drift
docs/                        inventario, matriz de capacidades por harness y ADRs
```
