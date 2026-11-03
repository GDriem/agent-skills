# Plan

Objetivo: que `pr-review`, `pr-ready`, `pr-review-all`, `pr-ready-all` y `orchestrate` funcionen igual en Claude
Code, Codex, Copilot, Gemini CLI y Cursor desde una sola fuente. En las versiones por lote, cada PR corre en su
propio agente y con su propio contexto.

Se trabaja por sesiones: un prompt por sesión en
`~/.claude/prompts/agent-skills-sesionN.md`, y cada sesión termina actualizando este archivo y escribiendo el
prompt de la siguiente.

## Punto de partida (2026-11-02)

Hay **tres copias** de los comandos de PR, y ya divergieron:

| Copia | Qué tiene | Problema |
|---|---|---|
| `~/.claude/commands/pr-*.md` | Las 4, versión más usada. Las `-all` usan `Workflow` con un agente por PR | Solo funcionan en Claude Code |
| `<repo de trabajo>/.claude/commands/pr-{review,ready}.md` | 2 de las 4, versionadas en un repo de trabajo | Difieren de la copia global |
| `~/.codex/skills/pr-*` y `~/.codex/prompts/pr-*.md` | Port a Codex del 2026-09-22 | Las `-all` **prohíben subagentes** ("one ordered loop in this session"): todas las PRs comparten un contexto |

Codex 0.166 ya trae `multi_agent` activado (stable), así que el bloqueo que justificó ese port ya no existe.

## Fases

### Fase 0: inventario y diseño (Sesión 1)

- [x] Diff de las 3 copias de cada comando. Elegir la mejor versión de cada paso y anotar de dónde sale cada
      diferencia que se conserve. → [docs/inventory.md](docs/inventory.md)
- [x] Verificar contra la documentación oficial de cada harness y dejarlo en `docs/harness-matrix.md`:
      carpeta de skills (usuario y repo), cómo se invocan, si soportan `references/`, cómo se lanza un subagente
      con contexto propio, modo headless (flag y cómo sacar la salida final a archivo), y cómo se pasan
      argumentos (`$ARGUMENTS` o equivalente). → [docs/harness-matrix.md](docs/harness-matrix.md)
- [x] ADR en `docs/adr/0001-fuente-unica.md`: skills en formato abierto Agent Skills, adapters por harness, runner
      universal como respaldo, contrato de resultado por PR.

### Fase 1: core neutral (Sesión 2)

- [x] `skills/pr-review` y `skills/pr-ready` sin nombres de herramientas de un harness. Lo que cambia según el
      harness (cómo preguntar al usuario, cómo lanzar un agente) se describe por capacidad y se resuelve en el
      adapter.
- [x] Flag nuevo `--dry-run`: hace todo menos escribir en GitHub, e imprime lo que publicaría. Hace falta para los
      smokes.
- [x] Contrato de resultado por PR (JSON de una línea, resumen ≤ 60 palabras, reporte completo a
      `runs/<fecha>/<skill>-<n>.md`). Lo cumplen también las skills de una PR, para que el lote no tenga que adivinar.

### Fase 2: un agente por PR (Sesiones 2 y 3)

- [x] Adapters `adapters/claude-code.md` y `adapters/codex.md`, con lo "sin confirmar" de la matriz probado.

- [x] `pr-review-all` y `pr-ready-all` con un solo cuerpo (`references/batch.md`, idéntico en las dos) y una
      sección por harness:
  - Claude Code: `Workflow` o `Agent` (probado: en `-p` elige `Agent` en background).
  - Codex: `multi_agent` con `fork_turns:"none"` (probado), con `bin/pr-batch` como respaldo.
  - Copilot CLI (`/fleet`) y Cursor (Task): subagentes nativos, documentados con contexto propio y en paralelo.
  - Gemini CLI y Copilot en VS Code: `bin/pr-batch` hasta probar que sus subagentes corren en paralelo.
- [x] `bin/pr-batch --harness <h> [--parallel N] [--model M] <prs>`: lanza una sesión headless por PR, junta los
      JSON y escribe el resumen del lote. Es el respaldo universal y también sirve desde cron o CI. Claude y
      Codex implementados; Copilot, Gemini y Cursor responden "no implementado aún" (Sesión 6).
- [x] Ahorro de tokens: el orquestador nunca lee diffs, el modelo por PR se puede configurar, y los reintentos
      solo corren las fallidas. Medido en [docs/token-cost.md](docs/token-cost.md).

### Fase 3: instalación (Sesión 4)

- [ ] `install.sh` con `--harness`, `--check` (drift entre la fuente y lo instalado) y `--uninstall`. Usa
      symlinks y, antes de reemplazar algo, mueve lo que había a `~/.agent-skills-backup/<fecha>/`. Dos
      destinos: `~/.claude/skills` y `~/.agents/skills`; más el envoltorio TOML de Gemini y `agents/openai.yaml`
      de Codex. `--check` avisa del duplicado que ven Copilot VS Code y Cursor (leen ambos destinos).
- [ ] Reemplazar el port viejo de `~/.codex/skills/pr-*` y `~/.codex/prompts/pr-*` (prompts deprecados en
      Codex) y los comandos de `~/.claude/commands/pr-*`. En Claude Code la skill gana al comando de igual
      nombre (documentado), así que se puede instalar primero y borrar el comando después.

### Fase 4: resto de skills (Sesión 5)

- [ ] `orchestrate` neutral: hoy depende de `Workflow`. Para los demás harnesses, misma idea con `bin/pr-batch`
      generalizado (`bin/agent-batch`).
- [ ] Revisar qué otras skills personales son genéricas y entran aquí.
- [ ] Fuera de alcance: las skills propias de un proyecto siguen en el repo de ese proyecto. Para que Codex,
      Gemini y Copilot lean sus convenciones, ese repo necesita un `AGENTS.md` (o el archivo que use cada
      harness); las skills de aquí lo buscan, pero no lo crean.

### Fase 5: validación y release (Sesión 6)

- [ ] Smoke por harness contra una PR real con `--dry-run`, una de una PR y una `-all` de 2 PRs. Medir tokens
      del orquestador contra los del port secuencial viejo de Codex.
- [ ] README final, `v0.1.0`.

## Decisiones

- Repo personal y público (`GDriem/agent-skills`). **Nada de un proyecto concreto**: ni nombres de repos,
  servicios, usuarios, IDs ni URLs internas. Las skills detectan en tiempo de ejecución el repo, el usuario de
  `gh` y las convenciones (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`…) del directorio donde se ejecutan.
  Lo que se porte de las copias existentes se revisa con esa regla antes de commitear.
- Instrucciones de las skills en inglés; fases, reportes y comentarios en el idioma de la PR (como hoy).
- Ninguna skill aprueba PRs, en ningún harness.
- Sin referencias a Claude en commits ni en comentarios publicados.

## Bitácora

- **2026-11-02:** scaffold del repo, README y plan. Sigue la Sesión 1 (`~/.claude/prompts/agent-skills-sesion1.md`).
- **2026-11-02 (Sesión 1):** Fase 0 cerrada: inventario, matriz de harnesses con fuentes y ADR-0001. Cambios al
  diseño: dos destinos de instalación (`~/.claude/skills` y `~/.agents/skills`), argumentos descritos por
  capacidad (solo Claude Code documenta `$ARGUMENTS`), Gemini necesita un comando TOML, reportes fuera del repo
  revisado (`~/.agent-skills/runs`). Sigue la Sesión 2 (`~/.claude/prompts/agent-skills-sesion2.md`).
- **2026-11-02 (Sesión 2):** Fase 1 cerrada y adapters de Claude Code y Codex. Smoke `--dry-run` de
  `pr-review` y `pr-ready` contra una PR real en los dos harnesses: nada publicado, reporte escrito, última línea
  parsea con `jq`. Probado: Claude Code no lee `~/.agents/skills`; Codex no sustituye `$ARGUMENTS` pero recibe
  el texto; `spawn_agent` hereda el contexto del padre salvo `fork_turns:"none"`; Codex 0.166 todavía lee
  `~/.codex/skills` (el port viejo choca con la skill nueva, Fase 3 lo retira primero); `codex exec` necesita
  stdin cerrado; `claude -p` niega comandos compuestos aunque empiecen por `gh`. Enmienda al ADR: reporte
  `<skill>-<n>.md` y `--run-dir`. Las `-all` pasan a la Sesión 3 (`~/.claude/prompts/agent-skills-sesion3.md`).
- **2026-11-02 (Sesión 3):** Fase 2 cerrada. `pr-review-all` y `pr-ready-all` (cuerpo compartido en
  `references/batch.md`), `bin/pr-batch` (bash 3.2, `xargs -P`, `--retry-failed`, `--yes` para lotes que
  publican) y `docs/token-cost.md`. El contrato marca el bloque de aprobación con `<!-- approval:start/end -->`
  para que el lote lo copie del reporte, y `--dry-run` ya no carga `posting.md`. Smokes `--dry-run` sobre dos PRs
  reales: `pr-review-all` en los dos harnesses, `pr-ready-all` en Codex, `bin/pr-batch` con los dos; nada
  publicado. Probado: un hijo de Claude Code lee la skill hermana por ruta absoluta (symlink o real) también en
  `-p`; Codex pasa `fork_turns:"none"` solo con lo que dice `batch.md`. Ajuste tras medir: esperar a los hijos sin
  sondear y validar las líneas en una pasada (−46 % de input en el orquestador de Codex). Sigue la Sesión 4
  (`~/.claude/prompts/agent-skills-sesion4.md`): `install.sh` y retirar las copias viejas.
