# Comment and body templates

Shared by `pr-review` and `pr-ready`. Spanish and English are given; for any other review language, translate
the labels and keep the shape. Use the repository's own tag names if its conventions define them.

When the fix is a concrete edit on the commented lines, add a fenced block whose info string is `suggestion`,
containing the exact replacement for those lines, correctly indented. GitHub renders it with an apply button.
Do not put a triple-backtick fence inside a `suggestion` block (it closes the block early); if the replacement
itself contains one, describe the edit in prose instead.

## Inline comments

### Spanish

```
**[BLOQUEANTE] Título corto del problema**

Qué pasa: una o dos frases con el defecto concreto.
Por qué importa: el impacto real (cobro duplicado, 500 en producción, fila corrupta, fuga entre tenants).
Cómo corregirlo: pasos concretos.
```

```
**[SUGERENCIA] Título corto**

Qué pasa: ...
Por qué conviene: ...
Cómo hacerlo: ...
```

```
**[DECISION] La pregunta en una línea**

Contexto: por qué esto no es obvio desde el código.
Pregunta: qué necesitas saber.
Opciones: A) ... B) ...

Responde en este hilo antes del merge.
```

`pr-ready`, for an item left from the previous round:

```
**[BLOQUEANTE] Título corto** (pendiente de la ronda anterior)

Lo señalado: qué se pidió.
Estado actual: qué hace el código hoy y por qué no alcanza.
Cómo corregirlo: pasos concretos.
```

### English

```
**[BLOCKER] Short title of the problem**

What happens: one or two sentences with the concrete defect.
Why it matters: the real impact (double charge, 500 in production, corrupted row, cross-tenant leak).
How to fix it: concrete steps.
```

```
**[SUGGESTION] Short title**

What happens: ...
Why it helps: ...
How to do it: ...
```

```
**[DECISION] The question in one line**

Context: why this is not obvious from the code.
Question: what you need to know.
Options: A) ... B) ...

Please answer in this thread before merging.
```

`pr-ready`, for an item left from the previous round:

```
**[BLOCKER] Short title** (still open from the previous round)

Raised: what was asked.
Current state: what the code does today and why it is not enough.
How to fix it: concrete steps.
```

## `pr-review` body

```markdown
## Resumen del review

<2-3 frases: qué hace la PR y el estado general>

**Bloqueantes:** N · **Sugerencias:** N · **Decisiones por responder:** N

### Bloqueantes
- `archivo:línea` — una línea

### Decisiones que necesitan respuesta
- `archivo:línea` — la pregunta

### Ya cubierto por <bot>
- <lo que encontró y sigue siendo válido>

### Hallazgos sin línea en el diff
- <si aplica>

### CI
<estado de los checks; si algo falla, cuál y por qué>
```

```markdown
## Review summary

<2-3 sentences: what the PR does and its overall state>

**Blockers:** N · **Suggestions:** N · **Decisions to answer:** N

### Blockers
- `file:line` — one line

### Decisions that need an answer
- `file:line` — the question

### Already covered by <bot>
- <what it found that is still valid>

### Findings with no line in the diff
- <if any>

### CI
<check status; if something fails, which one and why>
```

Drop empty sections.

## `pr-ready` body (verdict NOT_READY)

```markdown
## Segunda revisión

De los N comentarios de la ronda anterior, N quedaron atendidos y N siguen pendientes.

### Pendientes
- `archivo:línea` — una línea

### Gaps nuevos
- `archivo:línea` — una línea

### Atendidos correctamente
- `archivo:línea` — resuelto

### CI
<estado>
```

```markdown
## Second review

Of the N comments from the previous round, N were addressed and N are still open.

### Still open
- `file:line` — one line

### New gaps
- `file:line` — one line

### Addressed
- `file:line` — resolved

### CI
<status>
```

## `pr-ready` approval comment (verdict READY, never posted by the skill)

```markdown
## Aprobado

Revisé los comentarios de la ronda anterior y todos quedaron atendidos:

- <comentario> — resuelto en `archivo:línea`
- <decisión> — respondida y de acuerdo con el enfoque

También revisé los commits posteriores al review y no introducen regresiones. CI en verde.

Opcional para un siguiente PR (no bloquea):
- <sugerencia>
```

```markdown
## Approved

I went through the comments from the previous round and all of them were addressed:

- <comment> — fixed in `file:line`
- <decision> — answered, and I agree with the approach

I also reviewed the commits pushed after the review and they introduce no regressions. CI is green.

Optional for a follow-up PR (not blocking):
- <suggestion>
```

Adapt the content to what actually happened and keep the structure. Drop the optional section if it is empty.
