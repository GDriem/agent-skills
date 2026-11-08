# agent-skills

Skills personales de code review y orquestación escritas una sola vez para varios harnesses de agentes:
**Claude Code y Codex** (probados), y GitHub Copilot (CLI y VS Code), Gemini CLI y Cursor (documentados).

Hay una sola fuente: cada skill es una carpeta `skills/<nombre>/SKILL.md` en el formato abierto de Agent
Skills, y un script la instala en cada harness. Las versiones por lote (`-all`) corren **cada PR en un agente
aparte con su propio contexto**, así que la décima PR se revisa con el contexto tan limpio como la primera.

## Estado (`v0.3.0`)

| Harness | Estado |
|---|---|
| Claude Code | **Probado**: las cinco skills de `v0.2.0` (también headless con `claude -p`), `bin/pr-batch`, `bin/agent-batch` e `install.sh`. `pr-fix` interactiva: **probada** con un push real y una ronda completa `pr-review` → `pr-fix` → `pr-ready`. `pr-fix-all` y `pr-fix` headless: sin probar |
| Codex | **Probado**: lo mismo, con `codex exec`. `pr-fix` y `pr-fix-all`: sin probar |
| GitHub Copilot (CLI y VS Code), Gemini CLI, Cursor | Documentado, pendiente: la instalación los contempla, pero nada se probó y los runners todavía no los soportan |

Qué se probó y cómo, en [`adapters/`](adapters) (lo marcado **probado**).

Pendiente, sin fecha:

- `pr-fix`: probar `--dry-run`, `--no-push` y `bin/pr-batch --skill pr-fix` en Claude Code, y todo en Codex.
  `pr-fix-all`: probarla en los dos.
- Copilot, Gemini y Cursor: probarlos, sumarlos a `bin/pr-batch` y `bin/agent-batch` y escribir sus adapters. Lo
  que falta confirmar de cada uno está en [docs/harness-matrix.md](docs/harness-matrix.md).
- Correr el orquestador de las `-all` en un modelo más barato: con el tier por tamaño, en Claude Code es la mayor
  parte del costo del lote.
- Un modo ligero para `pr-ready`, para que `pr-ready-all` también use clases por tamaño.

## Skills

| Skill | Qué hace | Escribe en GitHub |
|---|---|---|
| `pr-review <PR>` | Primera pasada: hallazgos como comentarios in-line (`[BLOQUEANTE]`, `[SUGERENCIA]`, `[DECISION]`), sin repetir lo que ya marcó Copilot u otro bot | Sí, después de confirmar |
| `pr-ready <PR>` | Segunda pasada: confirma, leyendo el código en head, que cada hilo quedó atendido, busca huecos en los commits de fix y da veredicto. **Nunca aprueba**: si la PR está lista, te entrega el comentario de aprobación para que lo pegues tú | Solo comentarios de pendientes |
| `pr-review-all` | `pr-review` para todas las PRs abiertas que no son draft, o para una lista. Un agente por PR | Sí |
| `pr-ready-all` | `pr-ready` en lote. Un agente por PR | Solo pendientes |
| `pr-fix <PR>` | Corrige lo que pidieron los revisores (humanos y bots) y el CI: hilos abiertos, puntos del cuerpo del review, comentarios de la PR y checks en rojo. Verifica cada uno, sigue las skills y convenciones propias del proyecto (arquitectura, front, back, tests), corrige en un worktree aparte, corre los checks, se revisa a sí misma y, tras confirmar, hace push y responde en cada hilo **sin resolverlo**. Las decisiones y los comentarios con los que no está de acuerdo te los pregunta | Sí, después de confirmar: commits (nunca force-push) y respuestas |
| `pr-fix-all` | `pr-fix` en lote: tus PRs con feedback, una lista o un rango. Un agente y un worktree por PR; las decisiones quedan pendientes en `summary.md` | Sí |
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
pr-review-all 401-410            # las PRs abiertas de ese rango (sirve en las tres -all; se mezcla: 401,405-410)

pr-fix 401                       # corrige, muestra el plan y el diff, y pide confirmar antes del push
pr-fix 401 --dry-run             # solo triage y plan: no edita, no hace push, no responde
pr-fix 401 --no-push             # corrige y commitea en el worktree; tú revisas y empujas
pr-fix 401 --only=blocker,ci     # solo bloqueantes y checks en rojo
pr-fix-all                       # tus PRs abiertas con feedback (con --any-author, también las de otros)
pr-fix-all 401-410 --no-push
```

**Ciclo:** `pr-review` → `pr-fix` → `pr-ready`. `pr-fix` trabaja en un worktree propio bajo
`~/.agent-skills/worktrees` (o `$AGENT_SKILLS_WORKTREES`), así que nunca toca tu árbol de trabajo y varias PRs
corren en paralelo sin pisarse; necesita correr dentro de un clon del repo. Antes de editar busca las skills,
agentes y reglas del proyecto (`.claude/skills`, `.agents/skills`, `.github/instructions`, `.cursor/rules`,
`AGENTS.md`, ADRs, config de linters) y aplica las que corresponden a los archivos que toca. Solo hace `git push`
simple sobre el head de la PR: si la rama se movió, no empuja y deja el worktree. Un `[DECISION]`, un comentario
que cree incorrecto, algo fuera de alcance o una dependencia nueva siempre te lo pregunta; en lote (o con
`--auto`) queda pendiente con su propuesta.

Las reglas duras (nunca force-push, nunca `--no-verify`, nunca merge ni aprobar) están en la skill, y en Claude
Code headless además las impone el harness: `bin/pr-batch` y `bin/agent-batch` lanzan cada sesión con
`--disallowedTools` (lista en `bin/lib/batch.sh`) y solo permiten `rm` bajo `$TMPDIR`. Para el uso interactivo,
la misma lista va en `permissions.deny` de `~/.claude/settings.json`
([adapters/claude-code.md](adapters/claude-code.md#pr-fix-and-pr-fix-all)). Codex no tiene lista de denegación:
ahí, y como defensa para cualquier harness, conviene un ruleset de GitHub que bloquee force push y borrado de ramas.

Sin `--dry-run`, una `-all` pide confirmación una sola vez para todo el lote (cada agente corre con `--auto`
y publica). `--parallel 1` corre las PRs una detrás de otra.

`pr-review-all` separa las PRs por tamaño: las triviales y chicas van a un modelo barato con `--light` y escalan a
una revisión completa si ven algo serio (con dos PRs chicas, el lote bajó de 1,71 a 0,65 USD en Claude Code). Cómo
funcionan las `-all`, el tier por tamaño, el costo y `bin/agent-batch`, en [docs/batch.md](docs/batch.md).

### `bin/pr-batch`

El mismo lote sin subagentes: una sesión headless por PR. Sirve para harnesses sin subagentes, para cron o CI,
y lo usa la `-all` como respaldo.

```bash
bin/pr-batch --harness claude --dry-run 401,405          # o --harness codex
bin/pr-batch --harness codex --skill pr-ready --parallel 2 all
bin/pr-batch --harness claude --yes --repo owner/repo 12  # publica; --yes hace falta si stdin no es una terminal
bin/pr-batch --harness claude --retry-failed ~/.agent-skills/runs/2026-11-02T10-00   # solo las que dieron ERROR
bin/pr-batch --harness claude --skill pr-fix --allow-tool "Bash(npm *)" --yes 401-410  # pr-fix: permisos para los checks
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
Code a modelo, Codex a esfuerzo de razonamiento). Sin subagentes, `bin/agent-batch` corre el mismo grafo con una
sesión headless por tarea ([docs/batch.md](docs/batch.md#binagent-batch)).

## Desarrollo

```bash
tests/run.sh                        # tests de los runners e install.sh, con gh y claude falsos (sin red ni modelo)
tests/run.sh prb_                   # solo los que contienen "prb_"
scripts/lint-skills.sh              # frontmatter y referencias de cada SKILL.md
scripts/sync-references.sh          # copia shared/references/ a las skills que las usan (--check solo verifica)
shellcheck -x install.sh bin/pr-batch bin/agent-batch bin/lib/batch.sh scripts/*.sh tests/run.sh tests/fakes/*
```

El CI (`.github/workflows/ci.yml`) corre todo eso en cada push y PR, con los tests en Ubuntu y en macOS (bash 3.2).

Las referencias que usan varias skills (`batch.md`, `quality-gate.md`, `comment-templates.md`, `posting.md` y el
contrato de `pr-review`/`pr-ready`) se editan en `shared/references/` y se copian con
`scripts/sync-references.sh`. Cada skill lleva su copia porque se instala sola, con su propio symlink.

`HOME=<otro dir> ./install.sh` aísla los symlinks, pero no los `agents/openai.yaml` de Codex, que se generan dentro
del checkout: un `--uninstall` de prueba con otro `HOME` los borra también para tu instalación real (se recuperan
con `./install.sh --harness codex`). Los tests instalan sobre una copia del checkout por eso.

## Estructura

```text
skills/<nombre>/SKILL.md     fuente única, sin herramientas propias de un harness
skills/<nombre>/references/  instrucciones largas que se cargan bajo demanda
adapters/<harness>.md        cómo se lanza un subagente y dónde se instala, por harness
bin/pr-batch                 runner universal: una sesión headless por PR
bin/agent-batch              runner universal de orchestrate: una sesión headless por tarea, en olas
bin/lib/batch.sh             lo que comparten los dos runners (arranque headless por harness, run dir)
install.sh                   instala en cada harness, detecta drift y retira copias viejas con backup
shared/references/           fuente de las referencias que comparten varias skills
scripts/                     sync-references.sh y lint-skills.sh
tests/                       tests/run.sh y los gh y claude falsos que usa
docs/                        cómo corren los lotes, matriz de capacidades por harness, costo medido y ADRs
```
