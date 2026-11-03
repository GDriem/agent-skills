# Thread audit

Used by `pr-ready`, Step 2. Resolved in the UI does not mean fixed, and unresolved does not mean ignored.

For **every** review thread, bot or human, resolved or not, open the file at the current head and read the code
the thread is about (it may have moved: follow the symbol, not the old line number). Then give the thread one
state:

| State | Meaning | Pending? |
|---|---|---|
| `ADDRESSED` | The code at head fixes it. Cite `file:line` as evidence. | no |
| `PARTIAL` | Fixed in one place, missed in another (another call site, the sibling handler, no test). Say exactly what is left. | yes |
| `NOT_ADDRESSED` | The code is unchanged, or the change does not address the point. | yes |
| `DISMISSED_OK` | The author replied with a reason that holds up. Say why it holds. | no |
| `DISMISSED_WITHOUT_BASIS` | The author replied but the reason does not hold. It goes back on the list. | yes |
| `UNANSWERED` | It was a decision item and nobody answered. Blocks readiness. | yes |

- A thread marked resolved with no code change and no reply is `NOT_ADDRESSED`.
- An outdated thread is still audited: outdated means the lines moved, not that the point was fixed.
- A bot thread that was wrong to begin with, and that a human already called wrong, is `DISMISSED_OK`.
- `pending` in the result contract is the number of threads in a "yes" state.

Print the state labels in the review language. Spanish: `ATENDIDO`, `PARCIAL`, `NO ATENDIDO`, `DESCARTADO OK`,
`DESCARTADO SIN BASE`, `SIN RESPONDER`. Keep the same six states in any language.

## Audit table

Always print it, before anything is posted:

```
## Thread audit

| # | Author | file:line | State | Evidence / what is missing |
```

Then the new gaps (Step 3 of the skill):

```
## New gaps (not covered by any thread)

| # | Priority | Tag | file:line | Finding |
```

Then the CI status and the counts: addressed, pending, new gaps by tag. Translate the headings to the review
language.
