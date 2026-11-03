# Run procedure

Same shell rule as `SKILL.md`: one simple command per call, pipes into `jq` are fine, independent commands go in
parallel calls. The task prompt, the task line and the run directory files are defined in `contract.md`.

## Step 1 — Parse the arguments

Flags as listed in `SKILL.md`; everything else is the prompt. `--parallel` and `--max` are integers ≥ 1
(default `--parallel` 3). `--only` is a comma-separated list of task ids and requires `--run-dir`. Any invalid
value stops the run before anything is written: say which one.

## Step 2 — Repository and run directory

1. `git rev-parse --show-toplevel` → `<root>` (empty when not in a repository; then there are no write tasks
   with a fence to check, `--commit` is refused and the run is effectively read-only unless the user says the
   tasks write elsewhere). `git status --porcelain` tells whether the tree is dirty.
2. Run directory: `--run-dir` if given; otherwise `printenv AGENT_SKILLS_RUNS` (empty or exit code 1 means unset,
   then `printenv HOME` and use `<home>/.agent-skills/runs`), `date +%Y-%m-%dT%H-%M`, and
   `<runs>/<timestamp>-orchestrate`. `mkdir -p <runs>`, then `mkdir` the run directory without `-p`; if it
   already exists, another run started in the same minute: add `-2`, `-3`, … until one `mkdir` succeeds. A given
   `--run-dir` (for `--only`) is used as is. Use its absolute path everywhere. Never put it inside `<root>`.
3. `realpath <this-dir>/../..` → `<source-root>`, where `<this-dir>` is the directory this skill was loaded from
   (the harness gives it). Used only for `bin/agent-batch` and `adapters/`.

**With `--commit`**, two preconditions, both refusals (stop, do not work around them):

- `git status --porcelain` must be empty. `git add -A -- <fence>` stages everything under a fence, so a file the
  user was already editing would be swept into a task's commit. Name the files in the way and let the user commit
  or stash them.
- `git rev-parse --abbrev-ref HEAD` must not be the default branch (`git symbolic-ref --short
  refs/remotes/origin/HEAD`, minus the `origin/` prefix; if that fails, treat `main` and `master` as default).
  Ask the user to create the branch: its name is theirs to choose.

Without `--commit`, if the tree is dirty and the graph will have write tasks, say so once in Step 4 and let the
user decide. Do not stash or commit anything yourself.

**With `--only`**: read `<run-dir>/graph.json` and `<run-dir>/summary.json` (both must exist; stop otherwise),
skip Step 3, and run only the listed ids. Their dependencies outside the list take their line from
`summary.json`; a dependency that was not `ok` there makes the task `blocked` again. At the end, merge the new
lines into `summary.json` by `task` and rewrite `summary.md`.

## Step 3 — Build the task graph

Do this **in your own context, from the prompt alone**. Do not read source files to plan. If the prompt names
code you cannot place, launch one fresh read-only agent that returns only file paths with a one-line
description each, nothing else.

- **One task = one deliverable one agent can finish in one context.** More than ~10 files, or two separate
  components, means two tasks.
- **Split by seam, not by step.** Two packages are two tasks; "write the code" and "write its tests" for the
  same module is one.
- **`kind` is `read` or `write`.** `read`: research, audit, review, planning, answering a question; the agent may
  not edit anything. `write`: it changes files. Ambiguous means `write`. Under `--read-only`, every task is
  `read`, and a task that only makes sense as a write is reported as deferred.
- **`deps` only when real**: B cannot start without A's *conclusion*. Touching the same file is not a dependency;
  writes are serial anyway. Extra dependencies serialize the whole run.
- **`files` is the scope fence**: the paths or globs the agent may touch, relative to `<root>`. Required for
  write tasks. Under `--commit` it is also what gets staged, so it must cover everything the task writes and
  nothing it does not.
- **`commit`** is the commit message, write tasks only, in the repository's own style (look at
  `git log --oneline -5` if unsure). Under `--commit`, a write task without one is left uncommitted and reported.
- **`prompt` is self-contained**: the agent sees no earlier conversation.
- **Do not invent tasks.** If the prompt holds a single task, say so, do it yourself without a fleet, and end with
  the one-task run line of `contract.md`.
- With `--max N`, keep the N most valuable tasks and list the rest as deferred.

```json
{
  "id": "t1",
  "title": "short imperative title",
  "kind": "read",
  "deps": [],
  "files": ["packages/a/**"],
  "tier": "default",
  "effort": null,
  "prompt": "fully self-contained instructions",
  "done": "the acceptance criterion, in one sentence",
  "commit": null
}
```

**Tier.** The default is `default`: the agent gets the session's model. Move `effort` before moving `tier`.

| Task shape | `tier` | `effort` |
|---|---|---|
| Mechanical and fully specified: renames, moving files, formatting, extracting a list, running a command and reporting the result | `small` | `low` |
| Ordinary work in one component: a feature in one module with its tests, a doc page, reviewing a small change | `default` | `null` |
| Ambiguous or cross-cutting: architecture, contracts between components, debugging an unknown cause, data migrations, security review, anything where being wrong is expensive | `large` | `high` |

A task whose failure silently corrupts data or breaks production gets `large`/`high` however small it looks.
The adapter of each harness says what a tier and an effort become; a harness with no such setting ignores them.

## Step 4 — Show the graph and confirm

Write `{"prompt":…,"flags":…,"tasks":[…]}` to `<run-dir>/graph.json` with the write-file capability and check it
with `jq -e '.tasks | length'`. Then show, in the language of the user's prompt:

```
| id | Task | Kind | Tier | Effort | Depends on | Scope |
```

Below it: how many tasks run in parallel and how many in series, the run directory, the check commands of
Step 7 you intend to run, deferred tasks, the dirty-tree warning if any, and, under `--commit`, that the checks
run after all commits (if they fail, the commits already exist and the fix is a follow-up commit).

- `--dry-run`: stop here and end with the dry-run line of `contract.md`.
- `--yes`: continue.
- Otherwise ask once and wait. If the user edits the graph, rewrite `graph.json`; if they decline, stop with the
  dry-run line.

**No one to ask** (headless, or the harness cannot wait for an answer): without `--yes`, a graph with write tasks
is not launched (stop and say it needs `--yes`, `--read-only` or `--dry-run`); a read-only graph runs.

## Step 5 — Run the graph in waves

A wave is every task whose dependencies all have a line. Repeat until every task has a line:

1. If no task is ready but some remain, they form a cycle: give each a synthesized `blocked` line with `error`
   `dependency cycle` and stop the loop.
2. A ready task with a dependency that is not `ok` gets a synthesized `blocked` line naming that dependency.
3. **Read tasks of the wave**: launch them, at most `--parallel` at a time, each a fresh agent with the task
   prompt of `contract.md` and the task's tier and effort.
4. **Write tasks of the wave**: after the reads, one at a time. Right after each one ends `ok`, commit it
   (Step 6).
5. **Wait for completion, not for progress**: use the longest wait the harness offers, never short polls or
   sleeps; every check is one more turn of this orchestrator.
6. Keep **only the last line** of each agent's final message, as text. Do not read anything else it said. If it
   returned nothing or died, synthesize `failed` with `error` `no result line`.

Check the lines of a wave in one pass before the next wave needs them: write them, one per line, to a temporary
file from `mktemp` (not in the run directory), run `jq -cR 'fromjson? // null' <file>`, and delete the file. A
`null`, a non-object, or an object whose `task` is not that task's id becomes a synthesized `failed` line with
`error` `invalid result line`.

## Step 6 — Commit (only with `--commit`)

For each write task that ended `ok`, before the next write task starts, from `<root>`:

1. No `commit` message, or no `files`: record `{"committed":false,"sha":null,"error":"<that reason>"}`.
2. `git add -A -- <each path of files>`.
3. `git diff --cached --quiet`: exit code 0 means nothing staged; record `committed:false`, `error`
   `nothing to commit`.
4. Otherwise `git commit -m "<commit>"`, then `git rev-parse --short HEAD` → `sha`.

Never amend, rebase, reset, check out or push. A failed or blocked write task is not committed.

## Step 7 — Checks (skipped with `--no-verify`, `--read-only`, or when no task changed a file)

The repository's own build, lint and test commands, scoped to what the write tasks touched: whatever the repo's
convention files (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, the package manifest's scripts) say. Run each from
`<root>`, one per call, and record pass or fail, with the single most relevant error line (≤ 200 characters)
when it fails. Do not fix anything here. Never paste full output into your context or the summary.

## Step 8 — Summary files

1. `<run-dir>/summary.json` as in `contract.md`, tasks in graph order; check it with `jq -e`.
2. `<run-dir>/summary.md`, in the language of the user's prompt:
   - header: prompt (first line), date, flags, run directory;
   - `| id | Task | Kind | Tier | Status | Files | Summary |`, plus a `Commit` column (`sha` or `—`) under
     `--commit`;
   - **Failures and blocked**: one line each with its `error`;
   - **Commits** (under `--commit`): shas in order, and every write task that was not committed with its reason.
     Uncommitted work is loose in the tree; say so, because the next `git add -A` would swallow it. End with the
     branch name and that nothing was pushed;
   - **Checks**: pass or fail per command. A failure is the headline of the report, not a footnote;
   - **Artifacts**: the run directory and every artifact path;
   - **Pending**: the union of every `follow_ups`, plus what `--max` deferred;
   - **Retry**: `orchestrate --only <failed and blocked ids> --run-dir=<run-dir>` with the same flags.

## Step 9 — Tell the user

Print the table and the sections of `summary.md`, and the paths of `summary.md` and `summary.json`. Never claim a
task succeeded because its agent returned: report the `status` it gave, and if a check failed, say the work is
incomplete.

## Step 10 — Run line

End the final message with the run line of `contract.md`, checked with `jq` (temporary file from `mktemp`,
`jq -c .`, delete the file).

## Launching one agent per task

"Launch a fresh agent with its own context" is a capability; each harness meets it differently, and
`<source-root>/adapters/<harness>.md` has the details, including what `tier` and `effort` become:

| Harness | How |
|---|---|
| A workflow/scripting tool that spawns agents (Claude Code's `Workflow`) | the script in the adapter, as is, with the graph passed as data; it does Steps 5–7 and returns the lines |
| A tool that spawns one subagent per call (Claude Code's `Agent`) | up to `--parallel` read tasks per turn, write tasks one per turn |
| Codex `multi_agent` | `spawn_agent` with `fork_turns: "none"` (otherwise the child inherits this whole conversation), `reasoning_effort` from the tier, `wait_agent` with the longest timeout. Not under `codex exec --ephemeral` |
| No subagents, or they cannot be launched from a skill | `<source-root>/bin/agent-batch --harness <harness> --tasks <run-dir>/graph.json --run-dir <run-dir> --parallel N --yes [--read-only] [--commit] [--verify "label=cmd"]…` (`--yes` because Step 4 already confirmed). It does Steps 5–8 with one headless session per task; then do Steps 9–10 from its `summary.json` |
