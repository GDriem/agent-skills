# Matriz de harnesses (verificada 2026-11-02)

Cada dato cita la página oficial donde se leyó. "No documentado" significa que la documentación oficial no lo
dice; no es un "no". Solo `claude` (2.1.309) y `codex` (0.166.0) están instalados: Copilot, Gemini y Cursor se
documentaron **sin probar**, y la Sesión 6 los valida con smokes.

Las páginas de Codex en `developers.openai.com/codex` redirigen (308) a `learn.chatgpt.com/docs/…`; se citan las
URL finales.

## Resumen

| | Claude Code | Codex | Copilot CLI | Copilot VS Code | Gemini CLI | Cursor |
|---|---|---|---|---|---|---|
| Skills de usuario | `~/.claude/skills` | `~/.agents/skills` | `~/.copilot/skills`, `~/.agents/skills` | `~/.copilot/skills`, `~/.claude/skills`, `~/.agents/skills` | `~/.gemini/skills`, `~/.agents/skills` | `~/.cursor/skills`, `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills` |
| Skills de repo | `.claude/skills` | `.agents/skills` | `.github/skills`, `.claude/skills`, `.agents/skills` | `.github/skills`, `.claude/skills`, `.agents/skills` | `.gemini/skills`, `.agents/skills` | `.cursor/skills`, `.agents/skills`, `.claude/skills`, `.codex/skills` |
| Lee `.agents/skills` | No documentado | **Sí** (única ruta) | Sí | Sí | Sí (gana a `.gemini`) | Sí |
| Invocación | `/x` o implícita | `$x`, `/skills` o implícita | `/x` o implícita | `/x` o implícita | **Solo implícita** (`activate_skill`) | `/x` o implícita |
| Argumentos | `$ARGUMENTS`, `$N`; si no hay placeholder, se anexa | No documentado | No documentado | Texto libre tras `/x` | No documentado (los comandos TOML usan `{{args}}`) | No documentado |
| Subagentes con contexto propio | Sí (`Agent`) | Sí (hilos de agente) | Sí (`task`, `/fleet`) | Sí (`runSubagent`) | Sí (`.gemini/agents`) | Sí (Task) |
| En paralelo | Sí (hasta 20) | Sí | Sí (`/fleet`) | No documentado | No documentado | Sí (varias Task) |
| Headless | `claude -p` | `codex exec` | `copilot -p` | — | `gemini -p` | `cursor-agent -p` |
| Mensaje final a archivo | redirigir stdout (`--output-format json` → `.result`) | `-o FILE` | `-s` + redirigir | — | `-o json` → `.response` + redirigir | `--output-format json` → `.result` + redirigir |
| Contexto | `CLAUDE.md`; `AGENTS.md` solo si no hay `CLAUDE.md` | `AGENTS.md` (+ fallbacks) | `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md` | `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md` | `GEMINI.md` (configurable) | `AGENTS.md`, `.cursor/rules`; CLI también `CLAUDE.md` |

## Consecuencias para el diseño

1. **Dos destinos de instalación cubren los seis harnesses**: `~/.agents/skills` (Codex, Copilot CLI y VS Code,
   Gemini, Cursor) y `~/.claude/skills` (Claude Code, que no documenta `.agents`). El README listaba una carpeta
   por harness; se corrige.
2. **Riesgo de duplicados**: Copilot VS Code y Cursor leen *a la vez* `~/.agents/skills` y `~/.claude/skills`.
   Instalar en los dos destinos puede mostrar cada skill dos veces. Ninguna de las dos documenta cómo resuelve
   el empate. `install.sh --check` tiene que avisarlo; validarlo en la Sesión 6.
3. **El paso de argumentos solo está documentado en Claude Code.** El core no puede depender de `$ARGUMENTS`:
   se escribe "los argumentos son el texto que sigue al nombre de la skill en el mensaje que la invocó" (el patrón
   que ya usaba el envoltorio de Codex), y `$ARGUMENTS` queda como alias que Claude Code sustituye.
4. **Gemini no tiene `/x` para skills.** Para invocar con argumentos hace falta un comando TOML
   (`~/.gemini/commands/pr-review.toml` con `{{args}}`) que active la skill. Ese envoltorio es del adapter de
   Gemini.
5. **Comando vs skill con el mismo nombre en Claude Code: gana la skill.** Resuelve la duda de la Fase 3 del
   plan: se puede instalar la skill antes de borrar `~/.claude/commands/pr-*.md`.
6. **Los prompts personalizados de Codex (`~/.codex/prompts`) están deprecados**, y `~/.codex/skills` ya no
   figura entre las rutas de skills. El port viejo sobrevive por compatibilidad, no por diseño.
7. **Subagentes en todos menos Gemini y VS Code sin paralelismo documentado**: el adapter de esos dos cae a
   `bin/pr-batch`.
8. **Aprobar `gh`/`git` sin prompts tiene un mecanismo distinto en cada harness** (tabla de headless abajo). Lo
   resuelve `bin/pr-batch` por harness, no la skill.
9. Gemini CLI: geminicli.com muestra un aviso de que fue reemplazado por "Antigravity CLI" el 2026-06-18 para el
   plan gratuito y Google One. No se investigó Antigravity; el soporte de Gemini queda en duda hasta la Sesión 6.

## Claude Code

| Tema | Dato | Fuente |
|---|---|---|
| Carpetas | Usuario `~/.claude/skills/<n>/SKILL.md`; proyecto `.claude/skills/`; anidadas `<subdir>/.claude/skills/`; plugins; managed. Empate de nombre: enterprise > personal > proyecto. `.agents/skills` no documentado | https://code.claude.com/docs/en/skills |
| Formato | Todos los campos opcionales; `description` recomendado. Otros: `name`, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `model`, `context`, `agent`, … Archivos de apoyo y `scripts/` vía `${CLAUDE_SKILL_DIR}`; `references/` no tiene significado especial. Cuerpo < 500 líneas | https://code.claude.com/docs/en/skills |
| Invocación y argumentos | `/x` o implícita. `$ARGUMENTS`, `$ARGUMENTS[N]`/`$N`, nombres de `arguments`. Sin placeholder se anexa `ARGUMENTS: <valor>`. **Skill gana a comando de igual nombre** | https://code.claude.com/docs/en/skills |
| Subagentes | Contexto propio, solo vuelve el resumen. Herramienta `Agent` (antes `Task`). Agentes en `~/.claude/agents`, `.claude/agents`. Hasta 20 en paralelo (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`); 3 niveles de anidación | https://code.claude.com/docs/en/sub-agents |
| Skill que lanza subagentes | `context: fork` + `agent:` corre la skill en un subagente; también basta pedirlo en lenguaje natural | https://code.claude.com/docs/en/skills |
| `Workflow` | Herramienta de esta instalación para orquestar agentes con script; no aparece en la documentación pública consultada. El adapter la usa si existe y cae a `Agent` si no | (local, no documentado) |
| Headless | `claude -p "<prompt>"` o stdin. `--output-format text\|json\|stream-json` (`.result`); `--json-schema` → `.structured_output`. Sin flag de archivo: redirigir. `/x` dentro del prompt de `-p` se expande. `--bare` omite skills y CLAUDE.md | https://code.claude.com/docs/en/headless |
| Aprobar `gh`/`git` | `--allowedTools "Bash(gh *),Bash(git *)"` (el espacio antes de `*` importa); `--permission-mode`; desde 2.1.302 `-p` arranca en modo manual y niega lo no aprobado | https://code.claude.com/docs/en/headless |
| Contexto | `CLAUDE.md` de la raíz del sistema hacia el cwd, subdirectorios bajo demanda, `@imports`. `AGENTS.md` se lee nativo (2.1.277+) solo si no hay `CLAUDE.md`, `.claude/CLAUDE.md` ni `CLAUDE.local.md` | https://code.claude.com/docs/en/memory |

## Codex

| Tema | Dato | Fuente |
|---|---|---|
| Carpetas | Repo `.agents/skills` (cwd, padres dentro del repo y raíz); usuario `~/.agents/skills`; admin `/etc/codex/skills`; sistema. `~/.codex/skills` no está en la lista. Local: `~/.agents/skills` existe y tiene skills instaladas | https://learn.chatgpt.com/docs/build-skills |
| Formato | `name` y `description` obligatorios. Carpetas `scripts/`, `references/`, `assets/`, `agents/openai.yaml` (`interface`, `policy.allow_implicit_invocation`, `dependencies.tools`). Al arrancar solo carga nombre, descripción y ruta (tope 2 % del contexto u 8000 caracteres) | https://learn.chatgpt.com/docs/build-skills |
| Invocación y argumentos | `$x`, `/skills` o implícita. Paso de argumentos a una skill: **no documentado** | https://learn.chatgpt.com/docs/build-skills |
| Prompts personalizados | **Deprecados** ("use skills"). Se invocaban `/prompts:<n>` con `$1`–`$9`, `$ARGUMENTS` | https://learn.chatgpt.com/docs/custom-prompts |
| Subagentes | Hilos de agente en paralelo; se lanzan pidiéndolo o porque lo dice `AGENTS.md`/la skill. Config `agents.enabled`, `agents.max_concurrent_threads_per_session`, `default_subagent_model`. Agentes TOML en `~/.codex/agents`, `.codex/agents`. Nombres de herramientas (`spawn_agent`, `wait`) y contexto propio explícito: no documentados | https://learn.chatgpt.com/docs/agent-configuration/subagents |
| Feature flags (local) | `codex features list`: `multi_agent` stable **true**, `multi_agent_v2` stable false, `hooks` y `plugins` true | (local, 0.166.0) |
| Headless | `codex exec "<prompt>"` o `codex exec -` (stdin). Mensaje final a stdout. `-o/--output-last-message FILE`, `--json` (JSONL), `--output-schema FILE`, `-s read-only\|workspace-write\|danger-full-access` (read-only por defecto), `--approve-for-me`, `--dangerously-bypass-approvals-and-sandbox`, `-C`, `--ephemeral`, `--worktree`, `-m`. `--full-auto` ya no existe | https://learn.chatgpt.com/docs/non-interactive-mode · https://learn.chatgpt.com/docs/developer-commands?surface=cli · `codex exec --help` local |
| Aprobar `gh`/`git` | `approval_policy = "never"` / `-a never` quita prompts pero el sandbox sigue; en `workspace-write` la red está apagada salvo `[sandbox_workspace_write] network_access = true`. `prefix_rule(pattern=["gh"], decision="allow")` en `~/.codex/rules/*.rules` (experimental) corre el comando fuera del sandbox sin prompt | https://learn.chatgpt.com/docs/agent-approvals-security · https://learn.chatgpt.com/docs/agent-configuration/rules |
| Contexto | `~/.codex/AGENTS.override.md` o `AGENTS.md`; en el repo, de la raíz al cwd, uno por directorio: `AGENTS.override.md` > `AGENTS.md` > `project_doc_fallback_filenames`. Tope 32 KiB | https://learn.chatgpt.com/docs/agent-configuration/agents-md |

## GitHub Copilot CLI (sin probar)

| Tema | Dato | Fuente |
|---|---|---|
| Carpetas | Repo `.github/skills`, `.claude/skills`, `.agents/skills`; usuario `~/.copilot/skills`, `~/.agents/skills` | https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills |
| Formato | `name` y `description` obligatorios; `license`, `allowed-tools`, `argument-hint`, `user-invocable`, `disable-model-invocation` opcionales. Archivos de apoyo junto a `SKILL.md`, por ruta | misma · https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference (extracto de búsqueda) |
| Invocación y argumentos | `/x` o implícita. Argumentos no documentados | https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills |
| Subagentes | Agentes en `~/.copilot/agents`, `.github/agents`; integrados (Explore, Task, …). `/fleet`/`--fleet` corre subagentes en paralelo con contexto propio vía `task`. Que una skill los lance: no documentado | https://docs.github.com/en/copilot/how-tos/use-copilot-agents/use-copilot-cli · https://docs.github.com/en/copilot/concepts/agents/copilot-cli/fleet (extracto de búsqueda) |
| Headless | `copilot -p "<prompt>"`; `-s` solo la respuesta; `--output-format=json` (JSONL); `--share=PATH` guarda la transcripción; `--no-ask-user` | https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-programmatic-reference |
| Aprobar `gh`/`git` | `--allow-tool='shell(git:*), shell(gh:*)'`, `--deny-tool`, `--allow-all-tools` | misma |
| Contexto | `.github/copilot-instructions.md`, `.github/instructions/**`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`; raíz, cwd, intermedios y ruta de los archivos tocados | https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions |

## GitHub Copilot en VS Code (sin probar)

| Tema | Dato | Fuente |
|---|---|---|
| Carpetas | Proyecto `.github/skills`, `.claude/skills`, `.agents/skills`; usuario `~/.copilot/skills`, `~/.claude/skills`, `~/.agents/skills`; `chat.agentSkillsLocations` | https://code.visualstudio.com/docs/copilot/customization/agent-skills |
| Formato | `name` (= carpeta, ≤ 64) y `description` (≤ 1024) obligatorios; `argument-hint`, `user-invocable`, `disable-model-invocation`, `context: fork` (experimental) | misma |
| Invocación y argumentos | `/x` o implícita; el texto libre después de `/x` se pasa. Sin sustitución de placeholders | misma |
| Subagentes | `runSubagent`; contexto propio, sin historial; agentes en `.github/agents/*.agent.md`. Paralelo: no documentado | https://code.visualstudio.com/docs/copilot/agents/subagents |
| Headless | No aplica (IDE) | — |
| Contexto | `.github/copilot-instructions.md`; `AGENTS.md` raíz (anidados experimental, apagado); `CLAUDE.md` (encendido por defecto) | https://code.visualstudio.com/docs/copilot/customization/custom-instructions |

## Gemini CLI (sin probar)

| Tema | Dato | Fuente |
|---|---|---|
| Carpetas | Usuario `~/.gemini/skills` o `~/.agents/skills`; workspace `.gemini/skills` o `.agents/skills`; `.agents` gana dentro del mismo nivel | https://geminicli.com/docs/cli/skills/ |
| Formato | Frontmatter no documentado en esa página; scripts y datos del paquete legibles una vez activada | misma |
| Invocación | Implícita: el modelo llama `activate_skill` y el usuario confirma. `/skills` administra. **Sin `/x` ni argumentos** | misma |
| Comandos TOML | `~/.gemini/commands/*.toml`, `.gemini/commands/*.toml`; `prompt` y `description`; `{{args}}`; sin `{{args}}` se anexa el comando entero | https://geminicli.com/docs/cli/custom-commands/ |
| Subagentes | `.gemini/agents/*.md`, `~/.gemini/agents/*.md`; contexto propio; se invocan solos, con `@nombre` o como herramienta. Paralelo: no documentado | https://geminicli.com/docs/core/subagents/ |
| Headless | `-p/--prompt`; `-o text\|json\|stream-json` (`response`, `stats`, `error`); `--approval-mode default\|auto_edit\|yolo\|plan`; `--yolo` y `--allowed-tools` deprecados | https://geminicli.com/docs/cli/cli-reference/ · https://geminicli.com/docs/cli/headless/ |
| Aprobar `gh`/`git` | Policy Engine: TOML en `~/.gemini/policies/` con `toolName="run_shell_command"`, `commandPrefix="gh"`, `decision="allow"`. Las políticas del workspace hoy no tienen efecto | https://geminicli.com/docs/reference/policy-engine/ |
| Contexto | `GEMINI.md` por defecto, global, workspace y padres, y bajo demanda; `context.fileName` acepta lista (`["AGENTS.md","GEMINI.md"]`) | https://geminicli.com/docs/cli/gemini-md/ |

## Cursor (sin probar)

| Tema | Dato | Fuente |
|---|---|---|
| Carpetas | `.agents/skills`, `.cursor/skills`, `~/.agents/skills`, `~/.cursor/skills`, y por compatibilidad `.claude/skills`, `.codex/skills` (y sus `~`). Recursivo | https://cursor.com/docs/context/skills |
| Formato | `name` (= carpeta) y `description` obligatorios; `paths`, `disable-model-invocation`, `metadata`… Carpetas `scripts/`, `references/`, `assets/` | misma |
| Invocación y argumentos | `/x` o implícita. Argumentos no documentados (los comandos `.cursor/commands` tampoco documentan sintaxis) | misma · https://cursor.com/docs/context/commands |
| Subagentes | `.cursor/agents`, `.claude/agents`, `.codex/agents`; contexto propio; varios a la vez con varias llamadas a Task; editor, CLI y Cloud. Que una skill los lance: no documentado | https://cursor.com/docs/context/subagents |
| Headless | `cursor-agent -p`; `--output-format text\|json\|stream-json` (`.result`); `--force` para aplicar cambios; `CURSOR_API_KEY` | https://cursor.com/docs/cli/headless |
| Aprobar `gh`/`git` | `permissions.allow` en `~/.cursor/cli-config.json` o `.cursor/cli.json`, p. ej. `Shell(git)`; `Shell(gh)` por analogía, no confirmado | https://cursor.com/docs/cli/reference/permissions |
| Contexto | `.cursor/rules/*.mdc`; `AGENTS.md` en raíz y subdirectorios; el CLI también lee `CLAUDE.md` | https://cursor.com/docs/context/rules · https://cursor.com/docs/cli/using |

## Sin confirmar

- Claude Code: si lee `~/.agents/skills` (no documentado; probar en la Sesión 2 con un symlink de prueba).
- Codex: cómo llegan los argumentos a una skill; nombres de las herramientas de `multi_agent`; si un subagente
  tiene contexto propio (implícito). Probar en la Sesión 2.
- Codex: si `prefix_rule` con `allow` le da red a `gh` dentro de `workspace-write`.
- Copilot CLI: si el texto tras `/x` llega a la skill; si una skill puede pedir subagentes; si `-p` puede
  escribir solo el mensaje final a archivo.
- VS Code: subagentes en paralelo.
- Gemini: frontmatter aceptado, si lee `.claude/skills`, paralelo, estado frente a Antigravity CLI.
- Cursor: sintaxis de argumentos (hay un reporte en el foro de que el CLI descarta el texto tras un comando);
  si `-p` pide permiso para shell sin `--force`; `Shell(gh)`.
- Copilot VS Code y Cursor: qué pasa con una skill instalada a la vez en `~/.agents/skills` y `~/.claude/skills`.
