# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/); versiones con
[SemVer](https://semver.org/lang/es/).

## [Sin publicar]

### Agregado

- CI en GitHub Actions: `shellcheck`, validación de las skills y tests en Ubuntu y en macOS (bash 3.2).
- `tests/run.sh`: tests de `bin/pr-batch`, `bin/agent-batch` e `install.sh` con `gh` y `claude` falsos, sin red
  ni modelo.
- `shared/references/` como fuente de las referencias que comparten varias skills, y
  `scripts/sync-references.sh` (`--check`) para copiarlas o verificar que no divergieron.
- `scripts/lint-skills.sh`: frontmatter de cada `SKILL.md` (nombre igual a la carpeta, largo de la descripción) y
  referencias mencionadas que existen.
- `LICENSE` (MIT).
- Barreras en el harness para las sesiones headless de Claude Code: `bin/pr-batch` y `bin/agent-batch` las lanzan
  con `--disallowedTools` (force, `+refspec`, `--mirror` y borrado de ramas, push a `main`/`master`,
  `--no-verify`, `gh pr merge`/`close`/`--approve` y resolver hilos). Probadas con sesiones reales. Las tareas de
  `orchestrate` además no pueden hacer ningún `git push`.

### Cambiado

- `pr-fix`: probada en Claude Code, con un push real y una ronda completa `pr-review` → `pr-fix` → `pr-ready`.
- `bin/pr-batch` permite `rm` solo bajo `$TMPDIR`, donde las skills crean sus archivos temporales; antes, en
  cualquier ruta.
- El detalle del tier por tamaño y de `bin/agent-batch` pasa del README a [`docs/batch.md`](docs/batch.md).

### Corregido

- `install.sh`: el `default_prompt` de `agents/openai.yaml` usaba `$n` en la misma línea `local` que lo
  asignaba. En bash 3.2 salía bien solo porque quien llamaba tenía otra variable `n` con el mismo valor.
- `bin/agent-batch --task-file` sin valor ya no depende de que falle un `shift 2`.
- Todos los avisos de `shellcheck`, corregidos o justificados en la línea.

## [0.3.0] - 2026-11-06

### Agregado

- `pr-fix`: corrige el feedback de una PR en un worktree aparte, corre los checks, hace push sin force y responde
  en cada hilo sin resolverlo.
- `pr-fix-all`: `pr-fix` en lote, un agente y un worktree por PR.
- Rangos de PRs en las `-all` y en `bin/pr-batch` (`401-410`, combinables con `401,405-410`).

### Corregido

- `install.sh` resuelve la ruta del checkout con el case real del disco (macOS). Llegó a `main` después del tag.

## [0.2.0] - 2026-11-03

### Agregado

- Tier por tamaño en `pr-review-all` y `bin/pr-batch`: PRs triviales y chicas en un modelo barato con
  `--light`, y escalado a una revisión completa si ven algo serio.

## [0.1.0] - 2026-11-03

### Agregado

- `pr-review` y `pr-ready` con `--dry-run` y el contrato de resultado de una línea de JSON.
- `pr-review-all` y `pr-ready-all`, con un agente por PR.
- `bin/pr-batch`: una sesión headless por PR (Claude Code y Codex).
- `orchestrate` y `bin/agent-batch`, con `bin/lib/batch.sh` compartido.
- `install.sh` con symlinks, backup, `--check`, `--retire-conflicts` y `--uninstall`.
- Adapters de Claude Code y Codex, matriz de harnesses, costo medido y ADR-0001.

[Sin publicar]: https://github.com/GDriem/agent-skills/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/GDriem/agent-skills/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/GDriem/agent-skills/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/GDriem/agent-skills/releases/tag/v0.1.0
