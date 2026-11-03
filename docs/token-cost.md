# Costo en tokens de las versiones por lote

Medido el 2026-11-02 (Sesión 3) con `--dry-run` sobre dos PRs reales chicas de un repo de trabajo (+71/-2 y
+7/-6), ambas sin hallazgos. Claude Code 2.1.309 con el modelo por defecto de la cuenta; Codex 0.166.0 con el de
su `config.toml`. Todo headless, desde un directorio de prueba con las skills como symlinks y `CODEX_HOME`
aislado. Nada se publicó: los conteos de reviews y comentarios de las dos PRs no cambiaron.

## Cómo se midió

- **Claude Code**: `claude -p "/pr-review-all …" --output-format stream-json --verbose`. Los mensajes de un
  subagente traen `parent_tool_use_id`; cada bloque de contenido repite el mensaje, así que se agrupa por
  `message.id`. El evento final (`total_cost_usd`, `modelUsage`) suma padre e hijos. Para `bin/pr-batch`, el
  `--output-format json` de cada sesión.
- **Codex**: `codex exec --json` da el `turn.completed` del padre; cada hijo tiene su rollout en
  `$CODEX_HOME/sessions/…` (con `thread_spawn.parent_thread_id`) y su último evento `token_count` trae el total.
  `bin/pr-batch` lee el "tokens used" de cada sesión, que es input sin caché + output.

## Resultados

### Claude Code

| Corrida | Llamadas al modelo | Costo |
|---|---|---|
| `bin/pr-batch --harness claude`, PR chica 1 | 29 turnos | 0,76 USD |
| `bin/pr-batch --harness claude`, PR chica 2 | 31 turnos | 0,81 USD |
| **`pr-review-all` (padre + 2 hijos `Agent`)** | padre 16, hijos ~30 c/u | **1,71 USD** |
| de eso, el orquestador | 16 (675 k de caché leída, 37 k escrita, < 1 k de output) | ≈ 0,13 USD (total − las dos sesiones de `pr-batch`) |

El orquestador eligió `Agent` en background, no `Workflow`, aunque los dos estaban permitidos. Leyó solo
`SKILL.md` y `batch.md`, no leyó ningún diff, y el resto de sus turnos fueron `gh pr view`, la validación y los
archivos del resumen.

### Codex

Tokens de input (con caché incluida / sin caché) y output.

| Corrida | Input total | Sin caché | Output |
|---|---|---|---|
| `bin/pr-batch --harness codex`, PR 1 | 580 k | 79 k | 3,9 k |
| `bin/pr-batch --harness codex`, PR 2 | 734 k | 86 k | 4,4 k |
| `pr-review-all`, hijo 1 | 623 k | 78 k | 4,0 k |
| `pr-review-all`, hijo 2 | 801 k | 64 k | 4,1 k |
| **`pr-review-all`, orquestador (antes del ajuste)** | **575 k** | **67 k** | 3,1 k |
| **`pr-ready-all`, orquestador (después del ajuste)** | **312 k** | **24 k** | 2,7 k |

Antes del ajuste el orquestador hizo unas 19 llamadas sobre un contexto base de ~24–34 k: cuatro `wait_agent`
con `timeout_ms: 10000`, un `sleep` de 20 s, y `mktemp` + `jq` + `rm` por cada PR para validar su línea. Cada
llamada relee todo el contexto, así que cada vuelta extra cuesta ~30 k de input (casi todo en caché).

## Qué se cambió en esta sesión

| Cambio | Efecto |
|---|---|
| El orquestador no lee diffs, ni archivos del repo, ni las `references/` de la skill hermana | Su contexto no crece con el tamaño de las PRs (verificado en los dos harnesses) |
| `--dry-run` no lee `references/posting.md` | Una referencia menos por PR (verificado: ningún hijo la abrió) |
| Esperar a que termine el hijo, sin sondear ni dormir | Codex: de 4 `wait_agent` cortos + `sleep` a 2 `wait_agent` de 60 s |
| Validar todas las líneas en una sola pasada (`jq -cR 'fromjson? // null'`) al final | 3 llamadas menos por PR |
| `--model M` para los agentes por PR | Disponible en las dos `-all` y en `bin/pr-batch`; no se midió con un modelo más barato |
| `--retry-failed` / lista de números | Los reintentos corren solo las PRs con `ERROR` |

Los dos últimos ajustes juntos bajaron el input del orquestador de Codex un 46 % (un 64 % sin caché). La
comparación es entre `pr-review-all` y `pr-ready-all`, pero el orquestador hace lo mismo en las dos; la hermana
solo cambia lo que hacen los hijos.

## Evaluado y descartado

- **Cache de convenciones por lote** (leer `AGENTS.md` y compañía una vez y pasárselo a cada hijo): cada hijo
  necesita las convenciones en su propio contexto de todas formas, así que solo ahorraría unas lecturas, no
  tokens. Además obligaría al orquestador a leer archivos del repo, que es justo lo que se quiere evitar.
- **`Workflow` en vez de `Agent` en Claude Code**: no se fuerza. En `-p` el orquestador eligió `Agent` y el
  costo del padre ya es ~8 % del lote.

## Conclusiones

- El orquestador cuesta lo mismo con 2 PRs que con 20: su contexto es la skill, `batch.md` y una línea por PR.
  Con 2 PRs pesa ~8 % en Claude Code y ~21 % en Codex (input total de `pr-ready-all`, después del ajuste); con más PRs baja.
- `bin/pr-batch` no tiene orquestador con modelo, así que es la opción más barata cuando no hace falta
  conversar con el lote (cron, CI), al precio de arrancar una sesión completa por PR.
- Pendiente para la Sesión 6: medir con `--model` más barato en los hijos y comparar contra el port secuencial
  viejo de Codex.
