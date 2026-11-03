# Plan

Objetivo: que `pr-review`, `pr-ready`, `pr-review-all`, `pr-ready-all` y `orchestrate` funcionen igual en Claude
Code, Codex, Copilot, Gemini CLI y Cursor desde una sola fuente. En las versiones por lote, cada PR corre en su
propio agente y con su propio contexto.

Se trabaja por sesiones, igual que la migración a .NET 10 de payment: un prompt por sesión en
`~/.claude/prompts/agent-skills-sesionN.md`, y cada sesión termina actualizando este archivo y escribiendo el
prompt de la siguiente.

## Punto de partida (2026-11-02)

Hay **tres copias** de los comandos de PR, y ya divergieron:

| Copia | Qué tiene | Problema |
|---|---|---|
| `~/.claude/commands/pr-*.md` | Las 4, versión más usada. Las `-all` usan `Workflow` con un agente por PR | Solo funcionan en Claude Code |
| `gxs-be/.claude/commands/pr-{review,ready}.md` | 2 de las 4 (las `-all` quedaron en `backup-pr-commands/`) | Difieren de la copia global |
| `~/.codex/skills/pr-*` y `~/.codex/prompts/pr-*.md` | Port a Codex del 2026-09-22 | Las `-all` **prohíben subagentes** ("one ordered loop in this session"): todas las PRs comparten un contexto |

Codex 0.166 ya trae `multi_agent` activado (stable), así que el bloqueo que justificó ese port ya no existe.

## Fases

### Fase 0: inventario y diseño (Sesión 1)

- [ ] Diff de las 3 copias de cada comando. Elegir la mejor versión de cada paso y anotar de dónde sale cada
      diferencia que se conserve.
- [ ] Verificar contra la documentación oficial de cada harness y dejarlo en `docs/harness-matrix.md`:
      carpeta de skills (usuario y repo), cómo se invocan, si soportan `references/`, cómo se lanza un subagente
      con contexto propio, modo headless (flag y cómo sacar la salida final a archivo), y cómo se pasan
      argumentos (`$ARGUMENTS` o equivalente).
- [ ] ADR en `docs/adr/0001-fuente-unica.md`: skills en formato abierto Agent Skills, adapters por harness, runner
      universal como respaldo, contrato de resultado por PR.

### Fase 1: core neutral (Sesión 2)

- [ ] `skills/pr-review` y `skills/pr-ready` sin nombres de herramientas de un harness. Lo que cambia según el
      harness (cómo preguntar al usuario, cómo lanzar un agente) se describe por capacidad y se resuelve en el
      adapter.
- [ ] Flag nuevo `--dry-run`: hace todo menos escribir en GitHub, e imprime lo que publicaría. Hace falta para los
      smokes.
- [ ] Contrato de resultado por PR (JSON de una línea, resumen ≤ 60 palabras, reporte completo a
      `runs/<fecha>/pr-<n>.md`). Lo cumplen también las skills de una PR, para que el lote no tenga que adivinar.

### Fase 2: un agente por PR (Sesiones 2 y 3)

- [ ] `pr-review-all` y `pr-ready-all` con un solo cuerpo y una sección por harness:
  - Claude Code: `Workflow` (lo que ya hay), con `Agent` como respaldo si `Workflow` no está disponible.
  - Codex: `multi_agent`, con `codex exec` por PR como respaldo.
  - Copilot, Gemini y Cursor: subagentes nativos si la Fase 0 confirma que existen y aíslan el contexto.
- [ ] `bin/pr-batch --harness <h> [--parallel N] [--model M] <prs>`: lanza una sesión headless por PR, junta los
      JSON y escribe el resumen del lote. Es el respaldo universal y también sirve desde cron o CI.
- [ ] Ahorro de tokens: el orquestador nunca lee diffs, el modelo por PR se puede configurar, y los reintentos
      solo corren las fallidas.

### Fase 3: instalación (Sesión 4)

- [ ] `install.sh` con `--harness`, `--check` (drift entre la fuente y lo instalado) y `--uninstall`. Usa
      symlinks y, antes de reemplazar algo, mueve lo que había a `~/.agent-skills-backup/<fecha>/`.
- [ ] Reemplazar el port viejo de `~/.codex/skills/pr-*` y `~/.codex/prompts/pr-*` y los comandos de
      `~/.claude/commands/pr-*`. Si un comando y una skill tienen el mismo nombre, confirmar cuál gana en Claude
      Code antes de borrar el comando.

### Fase 4: resto de skills (Sesión 5)

- [ ] `orchestrate` neutral: hoy depende de `Workflow`. Para los demás harnesses, misma idea con `bin/pr-batch`
      generalizado (`bin/agent-batch`).
- [ ] Decidir qué de `~/.claude/skills/cu-*` (ClickUp) es personal y entra aquí.
- [ ] Fuera de alcance: las skills propias de gxs-be (doc-service, postgres-*, data-architect,
      sql-query-review, postman-update) siguen en ese repo. Como mucho, una PR aparte en gxs-be que agregue
      `AGENTS.md` (hoy no existe, así que Codex, Gemini y Copilot no leen las convenciones del monorepo).

### Fase 5: validación y release (Sesión 6)

- [ ] Smoke por harness contra una PR real con `--dry-run`, una de una PR y una `-all` de 2 PRs. Medir tokens
      del orquestador contra los del port secuencial viejo de Codex.
- [ ] README final, `v0.1.0`.

## Decisiones

- Repo personal (`GDriem/agent-skills`), no en ClickUp ni en gxs-be.
- Instrucciones de las skills en inglés; fases, reportes y comentarios en el idioma de la PR (como hoy).
- Ninguna skill aprueba PRs, en ningún harness.
- Sin referencias a Claude en commits ni en comentarios publicados.

## Bitácora

- **2026-11-02:** scaffold del repo, README y plan. Sigue la Sesión 1 (`~/.claude/prompts/agent-skills-sesion1.md`).
