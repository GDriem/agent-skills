# Task contract

What every task agent receives and returns. `bin/agent-batch` builds the same prompt and reads the same line, so
a graph runs the same way from this skill or from the runner.

## 1. Task prompt

Send exactly this to the task agent, filling in the values. Lines in `[…]` appear only when they apply.

```text
<task prompt from the graph>

--- Execution rules ---
You have no access to any earlier conversation, and no other agent is working on your files.
<mode line>
Scope: <files of the task joined with ", ", or "the scope described above">
Done when: <done of the task, or "the task above is complete and self-consistent.">
[Conclusions of the tasks you depend on (read their artifact files yourself if you need detail):
- [<dep id>] <dep summary>[ · artifacts: <dep artifacts joined with ", ">]]
If you produce anything longer than a short summary (a report, a plan, an inventory), write it to
<run-dir>/orchestrate-<id>.md and list that path in artifacts.
Nobody can answer questions in this session. If you cannot finish, set status to "failed" and say why in error
instead of guessing or half-doing it.
Your final message must end with exactly one line of JSON and nothing after it:
{"skill":"orchestrate","task":"<id>","kind":"<kind>","status":"ok","summary":"...","files_changed":[],"artifacts":[],"follow_ups":[],"error":null}
summary: at most 60 words. files_changed: at most 15 repository-relative paths. Never put file contents, diffs or
command output in any field.
```

Mode line:

- read task, or any task under `--read-only`: `READ-ONLY: you must not create, edit or delete any file in the
  repository. Report only. Writing your report under <run-dir> is allowed.`
- write task: `You may edit files, but ONLY within: <files>. Do not touch anything else. Do not commit and do
  not push.`

## 2. Task line

| Field | Value |
|---|---|
| `skill` | `orchestrate` |
| `task` | task id, as given in the graph |
| `kind` | `read` or `write` |
| `status` | `ok` or `failed` from the agent. The orchestrator adds `blocked` (a dependency did not end `ok`, or a dependency cycle) and `skipped` (never launched: deferred by `--max`, out of budget, or not in `--only`) |
| `summary` | at most 60 words, plain text, in the language of the user's prompt |
| `files_changed` | repository-relative paths, at most 15; `[]` for read tasks |
| `artifacts` | absolute paths written under the run directory; `[]` if none |
| `follow_ups` | work deliberately left out, short phrases; `[]` if none |
| `error` | the reason when `status` is not `ok`, otherwise `null` |
| `commit` | added by the orchestrator under `--commit`, write tasks only: `{"committed":true,"sha":"abc1234","error":null}` or `{"committed":false,"sha":null,"error":"<why>"}` |

**Synthesized line** (no agent ran, or its line did not parse): the fields above with the given `status`,
`summary` one short sentence, `files_changed`, `artifacts` and `follow_ups` empty, and the reason in `error`.
`status` values stay in English: they are for machines.

## 3. Run directory

`<run-dir>` holds only what this run produced:

| File | Written by | Content |
|---|---|---|
| `graph.json` | orchestrator, before launching | `{"prompt":"<the user's prompt, verbatim>","flags":"<flags>","tasks":[…]}` with the tasks of Step 2 of `run.md` |
| `orchestrate-<id>.md` | task agents, optional | long-form output of one task |
| `summary.json` | orchestrator, at the end | `{"tasks":[<one task line per task, in graph order>],"verify":<verify object or null>}` |
| `summary.md` | orchestrator, at the end | the table and sections of Step 8 of `run.md` |

`verify` object: `{"all_passed":true,"checks":[{"label":"build","cmd":"npm run build","passed":true,"error":null}]}`;
`error` is the single most relevant line, at most 200 characters, only when the check failed.

## 4. Run line

The orchestrator's final message ends with one line of JSON and nothing after it:

```json
{"skill":"orchestrate","run_dir":"/abs/run-dir","graph":"/abs/run-dir/graph.json","total":3,"counts":{"ok":2,"failed":1,"blocked":0,"skipped":0},"failed":["t2"],"dry_run":false,"commits":["abc1234"],"verify":{"all_passed":true},"summary_json":"/abs/run-dir/summary.json","summary_md":"/abs/run-dir/summary.md"}
```

- `failed` lists the ids with `failed` or `blocked`: what `--only` should re-run.
- `commits`: the shas in order under `--commit`, else `null`. `verify`: `{"all_passed":…}` or `null` when no check
  ran.
- `--dry-run`: `counts` all `0`, `failed` `[]`, `commits`/`verify`/`summary_json`/`summary_md` `null`; `total`
  and `graph` are set.
- A one-task prompt that the orchestrator did itself, without a fleet: `run_dir`, `graph` and the summary paths
  `null`, `total` 1.

Check every JSON you print or write parses (`jq`) before relying on it.
