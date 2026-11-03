# Result contract

Shared by `pr-review` and `pr-ready`. Every run ends this way, whether it was invoked by a person, by a batch
skill, or by a headless runner. A batch never parses free text: it reads the report file and the last line.

## 1. Report file

Directory:

- If the arguments contain `--run-dir=<path>`, use that path as is. Batch runners pass it so every PR of one
  batch lands in the same directory.
- Otherwise `<runs>/<timestamp>`, where `<runs>` is the environment variable `AGENT_SKILLS_RUNS` if it is set
  and not empty, else `~/.agent-skills/runs`, and `<timestamp>` is the local start time of this run as
  `YYYY-MM-DDTHH-MM` (for example `2026-11-02T10-05`).

File: `<dir>/<skill>-<n>.md` (for example `pr-review-401.md`, `pr-ready-401.md`), so both skills can run on
the same PR in the same minute without clashing. Create the directory if it does not exist. Never write it
inside the repository being reviewed. If a file with that name already exists, overwrite it: it is a retry of
the same skill on the same PR. Write nothing else into the run directory; it holds only reports (and, for a
batch, the batch summary).

Resolve the path once, with simple commands, and use the absolute path everywhere after that, including in the
JSON line:

- `printenv AGENT_SKILLS_RUNS` (empty output or exit code 1 means it is not set) and `printenv HOME`;
- `date +%Y-%m-%dT%H-%M`;
- `mkdir -p <dir>`, then write the file with the harness's write-file capability.

Content, in the review language:

1. Header: skill, `<owner>/<repo>#<n>`, PR title, head SHA, base branch, date, flags used (`--dry-run`,
   `--auto`, `--lang`, `--focus`).
2. The findings table exactly as previewed (and, for `pr-ready`, the thread audit table).
3. The review body and every inline comment that was posted, or that would have been posted under
   `--dry-run`, each with its `path:line`.
4. Anything that failed to post (422s moved to the body, failed replies).
5. CI status and residual risk.
6. `pr-ready` with verdict `READY` only: the approval comment block for the user to paste, with the line
   `<!-- approval:start -->` right before it and `<!-- approval:end -->` right after it, each on its own line.
   Batch runs copy exactly what is between them into their summary, so put nothing else inside.

## 2. Final line

The **last line of the final message** is one line of JSON and nothing comes after it: no closing sentence, no
code fence around it, no trailing blank line. Everything a person should read goes above it.

```json
{"skill":"pr-review","repo":"owner/repo","pr":401,"head":"abc1234","verdict":"REQUEST_CHANGES","max_priority":"P1","findings":{"blocking":2,"suggestion":3,"decision":0},"pending":null,"posted":true,"review_url":"https://github.com/owner/repo/pull/401#pullrequestreview-1","report":"/home/u/.agent-skills/runs/2026-11-02T10-00/pr-review-401.md","summary":"...","error":null}
```

| Field | Value |
|---|---|
| `skill` | `pr-review` or `pr-ready` |
| `repo` | `owner/repo` |
| `pr` | PR number, as a number |
| `head` | short SHA (7 characters) of the head that was reviewed; `null` if it was never resolved |
| `verdict` | `pr-review`: `REQUEST_CHANGES` or `COMMENT`. `pr-ready`: `READY` or `NOT_READY`. Either: `ERROR` (the run could not finish) or `SKIPPED` (draft without a person to ask, closed, or merged) |
| `max_priority` | highest priority among surviving findings, `P0`–`P3`, or `null` if there are none |
| `findings` | counts after verification and deduplication, `{"blocking":N,"suggestion":N,"decision":N}`. In `pr-ready` these are the new gaps only |
| `pending` | `pr-ready`: number of threads not `ADDRESSED` or `DISMISSED_OK`. `pr-review`: `null` |
| `posted` | `true` only if something was written to GitHub in this run. Always `false` with `--dry-run`, when the user declined, and for `pr-ready` `READY` |
| `review_url` | URL of the posted review, or `null` |
| `report` | absolute path of the report file |
| `summary` | at most 60 words, in the review language, plain text |
| `error` | the reason when `verdict` is `ERROR` or `SKIPPED`, otherwise `null` |

`verdict` values stay in English whatever the review language: they are for machines. The report, comments and
`summary` are in the review language.

Escape the JSON correctly (quotes and backslashes in `summary`), keep it on one physical line, and check that it
parses before printing it: write it to a temporary file from `mktemp` (not in the run directory), run
`jq -c . <file>`, and delete the file.

## 3. Errors

If the run stops early (a context command fails, the PR cannot be read, the user aborts), still write the report
with whatever is known and still print the final line, with `verdict` `ERROR` or `SKIPPED`, the counts at `0`,
`posted` `false` unless something was already posted, and the reason in `error`.
