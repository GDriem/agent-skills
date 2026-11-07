# Reply templates

Used by `pr-fix`, Steps 6 and 8. Spanish and English are given; for any other language, translate the labels
and keep the shape. Plain and direct, short sentences, no emojis, no signature, and never mention an AI, an
agent, an assistant, a model or any tool by name (Claude, Copilot, Codex, Gemini, Cursor or any other), nor add
a "generated with" footer: the text reads as the author's answer. Link commits by full SHA or the short one
GitHub autolinks (7+ characters).

## In a thread

### Spanish

`FIXED`:

```
Corregido en <sha>: <qué cambió, en una o dos frases, con `archivo:línea` si ayuda>.
<si aplica: Test agregado en `ruta/del/test`.>
```

`ALREADY_DONE`:

```
Esto ya está cubierto en el head actual: <evidencia concreta, `archivo:línea`, y el commit si se corrigió antes>.
```

`ANSWERED` after a decision the user made:

```
Decisión: <la opción elegida, en una línea>. <por qué, en una frase>.
Aplicado en <sha>.
```

`ANSWERED` as pushback the user approved:

```
Lo revisé y creo que no aplica: <la razón concreta, con la evidencia: el caso que ya está cubierto, la regla
del proyecto que lo pide así, o el input que muestra que no falla>.
Si ves un caso que se me escapa, dime y lo ajusto.
```

`ANSWERED` as a deferral the user approved:

```
De acuerdo, pero queda fuera del alcance de esta PR: <por qué>. Lo dejo en <#issue o "un PR aparte">.
```

### English

`FIXED`:

```
Fixed in <sha>: <what changed, in one or two sentences, with `file:line` if it helps>.
<if any: Added a test in `path/to/test`.>
```

`ALREADY_DONE`:

```
This is already covered at the current head: <concrete evidence, `file:line`, and the commit if it was fixed earlier>.
```

`ANSWERED` after a decision the user made:

```
Decision: <the chosen option, in one line>. <why, in one sentence>.
Applied in <sha>.
```

`ANSWERED` as pushback the user approved:

```
I looked into this and I don't think it applies: <the concrete reason, with evidence: the case that is already
handled, the project rule that asks for it this way, or the input that shows it does not fail>.
If you see a case I'm missing, let me know and I'll adjust it.
```

`ANSWERED` as a deferral the user approved:

```
Agreed, but it is outside the scope of this PR: <why>. Tracking it in <#issue or "a separate PR">.
```

## PR comment for items without a thread

```markdown
## Comentarios atendidos

- <fuente: review de @autor / comentario de @autor / check `nombre`> — <qué se pidió>: corregido en <sha>
- <...> — ya cubierto: <evidencia>
```

```markdown
## Review feedback addressed

- <source: review by @author / comment by @author / check `name`> — <what was asked>: fixed in <sha>
- <...> — already covered: <evidence>
```

Write `@author` in a backtick span (`` `@author` ``) unless notifying them is the point: they are already on the
PR. Drop the comment entirely when there are no such items.

## Pending block (report only, never posted)

For each `PENDING` item, in the report between `<!-- pending:start -->` and `<!-- pending:end -->` (see
`contract.md`):

```markdown
### #<item> <path:line> — <kind> (<subtype>)

<the comment, quoted briefly, and its author>

Por qué necesita a una persona / Why it needs a person: <one sentence>
Opciones / Options:
A) <recommended> — <consequence>
B) <...> — <consequence>
Respuesta propuesta / Proposed reply: <the reply text that would go in the thread for A>
```

Use only the labels of the review language.
