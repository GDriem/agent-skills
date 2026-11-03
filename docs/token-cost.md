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
- `--model` más barato en los hijos sigue sin medirse.

## Sesión 6 (2026-11-03)

Mismas versiones (Claude Code 2.1.309, Codex 0.166.0, modelo por defecto de cada uno). Las PRs son las mismas dos
de la Sesión 3, con `--dry-run` y un `gh` envoltorio que bloquea toda escritura; los conteos de reviews y
comentarios no cambiaron. `orchestrate` corrió en un repo de prueba: dos lecturas y una escritura que depende
de la primera, sobre dos archivos de tres líneas.

### `pr-review-all` de 2 PRs en Codex: skill nueva contra el port secuencial viejo

El port viejo (el que se retiró en la Sesión 4) revisa las PRs una tras otra en la misma sesión. No tiene
`--dry-run`, así que se le pidió frenar en la vista previa de cada PR y no publicar. Cada corrida tuvo su
`CODEX_HOME` y un `HOME` que solo veía las skills de PR, para que la lista de skills fuera comparable.

| Corrida | Input total | Sin caché | Output |
|---|---|---|---|
| Port viejo, secuencial (una sesión) | 797 k | 69 k | 4,9 k |
| **Skill nueva, orquestador** | **261 k** | **14 k** | 2,7 k |
| Skill nueva, hijo 1 | 510 k | 45 k | 3,5 k |
| Skill nueva, hijo 2 | 954 k | 66 k | 4,4 k |
| Skill nueva, total | 1 725 k | 125 k | 10,5 k |

- Con dos PRs chicas, la versión de un agente por PR gasta **más del doble** que la secuencial. Cada hijo arranca
  de cero y relee las convenciones, la skill y el repo. Además, los hijos verificaron más: uno bajó el tarball
  del head y buscó usos en el repo. La calidad de las dos revisiones no se comparó; las dos llegaron al mismo
  veredicto (`COMMENT`, sin hallazgos).
- Lo que se compra con eso: el contexto del port viejo crece con cada PR (797 k para dos PRs, en una sola
  conversación), y el del orquestador nuevo no; se puede paralelizar; y una PR que falla no contamina las
  demás. Con muchas PRs o PRs grandes, el port secuencial acaba compactando o mezclando hallazgos de una PR en
  otra.
- El orquestador bajó de 312 k (Sesión 3, `pr-ready-all`) a 261 k.

### `orchestrate` de 3 tareas

| Corrida | Orquestador | Agentes de las tareas |
|---|---|---|
| Codex (3 hijos con `spawn_agent`) | 580 k de input (36 k sin caché), 4,8 k de output | 292 k (78 k sin caché), 2,1 k de output |
| Claude Code por `Workflow` (4 agentes: 3 tareas + checks) | 678 k de caché leída, 51 k escrita, 11,2 k de output | 430 k leída, 102 k escrita, 6,7 k de output |
| Claude Code, `--only t3` (1 `Agent`) | 414 k de caché leída, 36 k escrita, 6,0 k de output | 148 k leída, 32 k escrita, 2,3 k de output (0,72 USD la sesión) |
| Codex, `--only t3` | 290 k de input | 73 k de input |

La corrida de Claude Code costó 1,36 USD en total. Calculado con las proporciones habituales de precio (caché
leída 0,1×, escritura 1,25×, output 5× el input), el orquestador es ≈ 53 % de ese costo.

- **El orquestador tiene un costo fijo** de ~0,6–0,7 USD en Claude Code y ~250–600 k de input en Codex: arma el
  grafo, confirma, valida las líneas, corre los checks y escribe los resúmenes. Con tareas de tres líneas eso
  supera el trabajo de las tareas mismas. Conviene cuando las tareas son grandes o tienen que aislarse (que una
  no vea lo que leyó otra); dos o tres cambios chicos salen más baratos pedidos directo, en una sola sesión.
- `--only` no reduce mucho ese costo: el orquestador vuelve a leer la skill, el grafo y el resumen anterior.

## Tier por tamaño (2026-11-03, después de la Sesión 6)

Cambios medidos: `pr-review --light`, tier budget para PRs `small`/`trivial`, lotes de triviales y escalado
(ADR-0001 §4 ter). Mismas PRs, mismas versiones, `--dry-run` y `gh` sin escrituras.

| Corrida | Antes | Después |
|---|---|---|
| Claude Code, `pr-review-all` de 2 PRs chicas | 1,71 USD | **0,65 USD** (−62 %) |
| de eso, los dos hijos | ≈ 1,58 USD | **0,04 USD** (`haiku`, `--light`) |
| de eso, el orquestador | ≈ 0,13 USD | 0,61 USD |
| Codex, `pr-review-all` de 2 PRs chicas, input total | 1 725 k (125 k sin caché) | **968 k (100 k)** (−44 %) |
| Codex, port secuencial viejo, mismo par | 797 k (69 k) | — |
| Codex, 4 PRs de 2 líneas (3 en un lote + 1 por ruta sensible) | — | 1 239 k (149 k) |

- En Claude Code los hijos casi desaparecen del costo. Ahora el que pesa es el orquestador: 0,61 USD, el 94 % del
  lote, y más que antes (el anuncio por clase y las líneas nuevas le suman turnos). La próxima palanca es correr el
  orquestador en un modelo más barato.
- En Codex el tier budget es solo esfuerzo bajo con el mismo modelo, así que el ahorro viene de `--light`: cada
  hijo hizo 7–10 llamadas en vez de 16–24. Cada llamada sigue releyendo ~35–40 k de contexto base (la skill y las
  convenciones), así que una PR cuesta 300–400 k aunque sea mínima. Con `--small-model` y un modelo más chico
  bajaría más; no se midió.
- El lote de tres triviales costó 518 k, contra 300–400 k que cuesta cada PR suelta.
- Veredictos y hallazgos iguales a los de la revisión completa en las seis PRs (todas `COMMENT`, sin hallazgos).
- **Escalado de más, corregido**: la primera versión de la regla ("toca datos persistidos, despliegue o un contrato")
  hizo que Codex escalara dos de las seis PRs sin sospechar nada (un `tsconfig` de build, conversiones que
  alimentan datos guardados), y cada escalado costó 760–860 k. La regla quedó en "cambia lo que hace el código"
  en auth, montos, escrituras destructivas, migraciones o secretos, con build, CI y dependencias fuera, y "nunca
  escalar solo por ser minucioso". Con eso, cero escalados en la segunda corrida.
