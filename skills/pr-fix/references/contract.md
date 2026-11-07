# Result contract

Used by `pr-fix`. Same shape as the contract of `pr-review` and `pr-ready` (report file plus one final JSON
line), with fields of its own. Every run ends this way, whether invoked by a person, by `pr-fix-all` or by a
headless runner. A batch never parses free text: it reads the report file and the last line.

## 1. Report file

Directory, exactly as in the other PR skills:

- `--run-dir=<path>` if given, as is.
- Otherwise `<runs>/<timestamp>`: `<runs>` is `AGENT_SKILLS_RUNS` if set and not empty, else
  `~/.agent-skills/runs`; `<timestamp>` is the local start time as `YYYY-MM-DDTHH-MM`.

File: `<dir>/pr-fix-<n>.md`. Create the directory if needed (`mkdir -p`), never inside the repository being fixed,
overwrite a file of the same name (a retry), and write nothing else into the run directory. Resolve the path once
with simple commands (`printenv AGENT_SKILLS_RUNS`, `printenv HOME`, `date +%Y-%m-%dT%H-%M`) and use the
absolute path everywhere after.

Content, in the review language:

1. Header: skill, `<owner>/<repo>#<n>`, PR title, original head SHA, new head SHA (if pushed), base branch,
   push target, date, flags used.
2. **Conventions applied**: the list from `project-context.md` §6.
3. The triage table with the `Outcome` column (`FIXED`, `ALREADY_DONE`, `ANSWERED`, `PENDING`, `FAILED`,
   `IGNORED`) and the evidence of each item.
4. The commits: SHA, subject, files, and the item each one resolves.
5. Checks: each command, passed / failed / not run, pre-existing failures marked as such.
6. Every reply and the PR comment that was posted (or, under `--dry-run`, `--no-push` or without confirmation,
   that would have been posted), with its target. Anything that failed to post.
7. Pending items: every `PENDING` item with its proposal (`reply-templates.md`), between a line
   `<!-- pending:start -->` and a line `<!-- pending:end -->`, each on its own line. Batch runs copy exactly what
   is between them into their summary, so put nothing else inside. Omit the markers when nothing is pending.
8. The worktree path if it was kept, and residual risk (checks not run, searches that could not be exhaustive).

## 2. Final line

The **last line of the final message** is one line of JSON and nothing comes after it.

```json
{"skill":"pr-fix","repo":"owner/repo","pr":401,"head":"abc1234","new_head":"def5678","verdict":"PARTIAL","items":{"fixed":4,"already_done":1,"answered":1,"pending":2,"failed":0},"commits":["1a2b3c4","def5678"],"pushed":true,"posted":true,"checks":{"all_passed":true,"not_run":1},"worktree":null,"report":"/home/u/.agent-skills/runs/2026-11-06T10-00/pr-fix-401.md","summary":"...","error":null}
```

| Field | Value |
|---|---|
| `skill` | `pr-fix` |
| `repo` | `owner/repo` |
| `pr` | PR number, as a number |
| `head` | short SHA (7 characters) of the PR head the run started from; `null` if never resolved |
| `new_head` | short SHA of the head after the push; `null` if nothing was pushed |
| `verdict` | `FIXED`: no item left `PENDING` or `FAILED`. `PARTIAL`: at least one is. `NOTHING_TO_FIX`: triage found nothing to fix or ask. `PLANNED`: a `--dry-run`. `ERROR`: the run could not finish. `SKIPPED`: the PR is closed or merged |
| `items` | counts by outcome, `{"fixed":N,"already_done":N,"answered":N,"pending":N,"failed":N}`. Under `--dry-run`, the plan: `fixed` = items planned as `FIX`, `pending` = `ASK` items |
| `commits` | short SHAs of the commits this run created and kept, oldest first; `[]` if none |
| `pushed` | `true` only if the commits reached the PR branch in this run |
| `posted` | `true` only if at least one reply or PR comment was written in this run |
| `checks` | `{"all_passed":bool,"not_run":N}` for the full checks (`all_passed` ignores pre-existing failures); `null` with `--no-checks`, `--dry-run`, or when no commit was made |
| `worktree` | absolute path of the worktree when it was kept, otherwise `null` |
| `report` | absolute path of the report file |
| `summary` | at most 60 words, in the review language, plain text |
| `error` | the reason when `verdict` is `ERROR` or `SKIPPED`, or when the push did not happen for a reason other than a flag (declined, nobody confirmed, branch moved, rejected); otherwise `null` |

`verdict` values stay in English whatever the review language: they are for machines.

Escape the JSON correctly, keep it on one physical line, and check that it parses before printing it: write it
to a temporary file from `mktemp` (not in the run directory), run `jq -c . <file>`, and delete the file.

## 3. Errors

If the run stops early, still write the report with whatever is known and still print the final line, with
`verdict` `ERROR` or `SKIPPED`, the counts at what actually happened (usually `0`), `pushed` and `posted` `false`
unless something already went out, `worktree` set if one was created and kept, and the reason in `error`.
