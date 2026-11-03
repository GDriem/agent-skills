# agent-skills

Skills personales de code review y orquestación escritas una sola vez para varios harnesses de agentes:
**Claude Code y Codex** (probados), y GitHub Copilot (CLI y VS Code), Gemini CLI y Cursor (documentados).

Hay una sola fuente: cada skill es una carpeta `skills/<nombre>/SKILL.md` en el formato abierto de Agent
Skills, y un script la instala en cada harness. Las versiones por lote (`-all`) corren **cada PR en un agente
aparte con su propio contexto**, así que la décima PR se revisa con el contexto tan limpio como la primera.

## Estado (`v0.2.0`)

| Harness | Estado |
|---|---|
| Claude Code | **Probado**: las cinco skills (también headless con `claude -p`), `bin/pr-batch`, `bin/agent-batch` e `install.sh` |
| Codex | **Probado**: lo mismo, con `codex exec` |
| GitHub Copilot (CLI y VS Code), Gemini CLI, Cursor | Documentado, pendiente: la instalación los contempla, pero nada se probó y los runners todavía no los soportan |

Qué se probó y cómo, en [`adapters/`](adapters) (lo marcado **probado**) y en [PLAN.md](PLAN.md).

## Skills

| Skill | Qué hace | Escribe en GitHub |
|---|---|---|
| `pr-review <PR>` | Primera pasada: hallazgos como comentarios in-line (`[BLOQUEANTE]`, `[SUGERENCIA]`, `[DECISION]`), sin repetir lo que ya marcó Copilot u otro bot | Sí, después de confirmar |
| `pr-ready <PR>` | Segunda pasada: confirma, leyendo el código en head, que cada hilo quedó atendido, busca huecos en los commits de fix y da veredicto. **Nunca aprueba**: si la PR está lista, te entrega el comentario de aprobación para que lo pegues tú | Solo comentarios de pendientes |
| `pr-review-all` | `pr-review` para todas las PRs abiertas que no son draft, o para una lista. Un agente por PR | Sí |
| `pr-ready-all` | `pr-ready` en lote. Un agente por PR | Solo pendientes |
| `orchestrate` | Parte un prompt con varias tareas en un grafo de dependencias y lo ejecuta con un agente nuevo por tarea: lecturas en paralelo, escrituras en serie, y al final los checks del repo | No (con `--commit`, un commit local por tarea; nunca push) |

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
./install.sh --dry-run           # muestra qué haría, sin tocar nada
./install.sh                     # detecta qué harnesses tienes, muestra el plan y pide confirmación
./install.sh --harness codex     # solo uno (repetible o separado por comas; también `all`)
./install.sh --check             # qué está instalado, qué quedó desactualizado y qué choca
./install.sh --retire-conflicts  # además retira copias viejas con el mismo nombre (ver abajo)
./install.sh --uninstall         # quita lo instalado y restaura lo que había antes
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

- **Nada se borra sin backup.** Lo que ocupaba un destino (una carpeta, un archivo, un symlink ajeno o roto) se
  mueve a `~/.agent-skills-backup/<fecha>/<ruta bajo $HOME>` y queda anotado en `manifest.tsv`.
  `--uninstall` quita solo los symlinks y archivos generados de este checkout y devuelve desde el backup lo que
  falte en su lugar original.
- **`--retire-conflicts`** mueve al backup las copias viejas con el nombre de una skill: `~/.codex/skills/<n>`
  (Codex 0.166 la sigue leyendo y mezcla sus instrucciones con la skill nueva), `~/.codex/prompts/<n>.md`
  (prompts deprecados) y `~/.claude/commands/<n>.md` (la skill gana, pero el comando sobra). Conviene instalar,
  probar `/pr-review … --dry-run` y recién entonces retirar.
- **Codex:** se genera `skills/<n>/agents/openai.yaml` (ignorado por git). Las `-all` llevan
  `allow_implicit_invocation: false`: no aparecen en la lista implícita y solo corren con `$pr-review-all`.
- **Gemini (sin probar):** `~/.gemini/commands/<n>.toml` activa la skill y le pasa `{{args}}`.
- Requiere solo bash 3.2 y coreutils; `HOME=<otro dir> ./install.sh …` instala en otro lado para probar.

## Uso

```text
pr-review 401                    # una PR del repo del directorio actual
pr-review owner/repo#401         # otro repo
pr-review                        # la PR de la rama actual
pr-review 401 --auto             # publica sin pedir confirmación
pr-review 401 --dry-run          # hace todo menos escribir en GitHub
pr-review 401 --light            # pasada barata para una PR chica; si ve algo serio, pide una completa

pr-ready 401

pr-review-all                    # todas las abiertas que no son draft
pr-review-all 401,405,410        # solo esas (útil para reintentar fallidas)
pr-review-all --repo owner/repo 12,15
pr-review-all --dry-run --parallel 2 --model <modelo>   # 2 agentes a la vez, modelo propio para las PRs normales
pr-review-all --small-model <modelo>                    # modelo del tier budget (PRs chicas y triviales)
pr-review-all --no-tiering       # todas como normales: una revisión completa por agente, sin agrupar
pr-ready-all                     # pr-ready en lote; los LISTA traen su comentario de aprobación en summary.md
```

Sin `--dry-run`, una `-all` pide confirmación una sola vez para todo el lote (cada agente corre con `--auto`
y publica). `--parallel 1` corre las PRs una detrás de otra.

**Tier por tamaño (`pr-review-all` y `bin/pr-batch --skill pr-review`).** Con las rutas y los conteos de cada PR,
sin leer el diff, el lote las separa en tres clases:

| Clase | Cuándo | Cómo corre |
|---|---|---|
| trivial | ≤ 20 líneas y ≤ 3 archivos | de a cinco por agente, en serie, tier budget, `--light` |
| small | ≤ 100 líneas y ≤ 8 archivos | un agente por PR, tier budget, `--light` |
| normal | el resto, o cualquier ruta que suene sensible (auth, permisos, secretos, migraciones, pagos, CI, despliegue) | como siempre |

Tier budget: `haiku` en Claude Code y esfuerzo de razonamiento bajo en Codex (o `--small-model`). Si la pasada
ligera ve un posible bloqueante, algo sensible o algo que no puede verificar, no publica nada y el lote revisa esa
PR de nuevo, completa. `summary.md` muestra la clase de cada PR y por qué escaló. `pr-ready-all` no usa clases.

### `bin/pr-batch`

El mismo lote sin subagentes: una sesión headless por PR. Sirve para harnesses sin subagentes, para cron o CI,
y lo usa la `-all` como respaldo.

```bash
bin/pr-batch --harness claude --dry-run 401,405          # o --harness codex
bin/pr-batch --harness codex --skill pr-ready --parallel 2 all
bin/pr-batch --harness claude --yes --repo owner/repo 12  # publica; --yes hace falta si stdin no es una terminal
bin/pr-batch --harness claude --retry-failed ~/.agent-skills/runs/2026-11-02T10-00   # solo las que dieron ERROR
```

Deja `summary.json` y `summary.md` en el directorio del lote, imprime la tabla y sale con código 1 si alguna PR
terminó en `ERROR`. Copilot, Gemini y Cursor todavía no están implementados en el runner. Costo medido en
[docs/token-cost.md](docs/token-cost.md).

### `orchestrate`

```text
orchestrate "auditar el módulo a; documentar el b; con lo del primero, corregir a" --dry-run   # solo el grafo
orchestrate "…" --yes                      # sin pausa de confirmación
orchestrate "…" --read-only                # nadie edita: solo investigan y reportan
orchestrate "…" --commit                   # un commit por tarea de escritura (árbol limpio, rama no default)
orchestrate --only t3,t5 --run-dir=<dir>   # re-lanza esas tareas de un run anterior
```

Cada tarea corre en un agente nuevo y termina con una línea de JSON (`status`, `summary` ≤ 60 palabras,
`files_changed`, `artifacts`); lo largo queda en `<run-dir>/orchestrate-<id>.md`. El orquestador no lee código ni
diffs. En vez de nombres de modelo, el grafo usa `tier: small|default|large`, y cada adapter lo traduce (Claude
Code a modelo, Codex a esfuerzo de razonamiento).

### `bin/agent-batch`

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

### Cómo funcionan las versiones `-all`

El agente principal solo lista las PRs y lanza un agente nuevo por cada una. Ese agente sigue la skill de una
PR completa y termina con un resultado corto y fijo, una línea de JSON (contrato completo en
[ADR-0001](docs/adr/0001-fuente-unica.md)):

```json
{ "skill": "pr-review", "repo": "owner/repo", "pr": 401, "verdict": "REQUEST_CHANGES", "max_priority": "P1",
  "findings": { "blocking": 2, "suggestion": 3, "decision": 0 }, "posted": true,
  "report": "~/.agent-skills/runs/2026-11-02T10-00/pr-review-401.md", "summary": "≤ 60 palabras" }
```

El reporte completo se queda en `~/.agent-skills/runs/<fecha>/<skill>-<n>.md` (o bajo `$AGENT_SKILLS_RUNS`), nunca
dentro del repo revisado. El agente principal nunca ve diffs ni archivos de otra PR, solo esas líneas. Al final
escribe `summary.json` (las líneas de todas las PRs) y `summary.md` (la tabla) en el mismo directorio que los
reportes. Cómo se
lanza cada agente depende del harness:

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
conviene aislar. Números en [docs/token-cost.md](docs/token-cost.md).

## Estructura

```text
skills/<nombre>/SKILL.md     fuente única, sin herramientas propias de un harness
skills/<nombre>/references/  instrucciones largas que se cargan bajo demanda
adapters/<harness>.md        cómo se lanza un subagente y dónde se instala, por harness
bin/pr-batch                 runner universal: una sesión headless por PR
bin/agent-batch              runner universal de orchestrate: una sesión headless por tarea, en olas
bin/lib/batch.sh             lo que comparten los dos runners (arranque headless por harness, run dir)
install.sh                   instala en cada harness, detecta drift y retira copias viejas con backup
docs/                        inventario, matriz de capacidades por harness y ADRs
```
