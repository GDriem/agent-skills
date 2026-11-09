# Batch procedure

Shared by `pr-review-all`, `pr-ready-all` and `pr-fix-all`. The calling `SKILL.md` gives `<sibling>` (the one-PR
skill) and `<batch-skill>` (its own name). Same shell rule as the sibling: one simple command per call, pipes into `jq`
are fine, independent commands go in parallel calls.

The orchestrator's context should stay small no matter how many PRs there are: PR numbers and titles from `gh`,
one JSON line per PR, and nothing else. Never read a diff, a changed file, a PR's review threads or the
sibling's `references/` here; the PR agents do that.

## Step 1 — Parse the arguments

- PR numbers: comma- or space-separated integers greater than 0 (a leading `#` is fine). Drop duplicates and
  keep the order given. Anything else that is not a flag (a word, `0`, `-3`, `12a`) stops the batch before
  anything is launched: say which token is invalid.
- Ranges: `401-410` (both ends included, start ≤ end, at most 500 numbers) means the open PRs whose number falls
  in it; issues share the numbering, so a range is never expanded blindly (Step 2). Numbers and ranges mix:
  `401,405-410`.
- `all` or no numbers: list the repository (Step 2).
- `--repo owner/repo`, `--parallel N` (integer ≥ 1, default 3; default 2 for `pr-fix`, which edits and runs
  checks), `--model M`, `--small-model M`, `--no-tiering`, `--dry-run`, `--lang=…`, `--focus="…"`. For `pr-fix`
  also `--no-push`, `--only=…`, `--no-checks` and `--any-author`. Keep `--lang`, `--focus` and `--only` verbatim
  to forward them.

## Step 2 — Repository and PR list

1. Repository: `--repo` if given, else `gh repo view --json nameWithOwner -q .nameWithOwner`. If that fails,
   stop: the batch must run inside a clone with a GitHub remote, or get `--repo`.
   **`pr-fix` needs a local clone**: it commits in a worktree of the current directory's clone. If
   `<sibling>` is `pr-fix` and `gh repo view --json nameWithOwner -q .nameWithOwner` in the current directory
   is not `<owner>/<repo>` (also when `--repo` points elsewhere), stop: run the batch from a clone of that
   repository.
2. With explicit numbers, use them as they are; their state is checked per PR in Step 6. When tiering is on
   (Step 2b), get each one's size with
   `gh pr view <n> --repo <owner>/<repo> --json number,title,additions,deletions,changedFiles,files --jq '<size>'`.
   With ranges, list the open PRs as in item 3, with the same filters (for `pr-fix`, drafts included), and keep
   those whose number falls in a range, in ascending order, after the explicit numbers. A range with no open PR in it is not an
   error; say so in Step 5.
3. Otherwise:
   `gh pr list --repo <owner>/<repo> --state open --limit 1000 --json number,title,isDraft --jq '[.[] | select(.isDraft | not) | {number,title}]'`.
   `gh` pages through the API up to `--limit`. If it returns exactly 1000, say the list may be truncated. When
   tiering is on, ask for `number,title,isDraft,additions,deletions,changedFiles,files` instead, with
   `--jq '[.[] | select(.isDraft | not) | <size>]'`.
   **For `pr-fix`**, `all` means the open, non-draft PRs that have feedback to act on and, unless
   `--any-author` was given, whose author is the current user (`gh api user -q .login` → `<me>`): fixing
   someone else's branch is opt-in. Ask for
   `number,title,isDraft,author,reviewDecision,reviews,statusCheckRollup` and keep
   `select((.isDraft | not) and ($any or .author.login == $me) and (.reviewDecision == "CHANGES_REQUESTED" or (.reviews | length > 0) or ([.statusCheckRollup[]? | select(.conclusion == "FAILURE")] | length > 0)))`,
   passing `--arg me <me>` and `--argjson any true|false` to `jq` through a pipe if `gh --jq` cannot take them.
   A PR whose feedback turns out to be already handled ends `NOTHING_TO_FIX`, which is cheap.
4. No PRs: say so, write no run directory, and end with the batch line of Step 9 (`total` 0).

`<size>` is this `jq` expression. It reads file paths and line counts only, never the diff:

```jq
{number, title, lines: (.additions + .deletions), files: .changedFiles,
 sensitive: ([.files[].path | ascii_downcase | select(test("auth|login|session|token|permission|role|acl|security|crypto|secret|credential|password|migration|schema|payment|invoice|\\.github/workflows/|dockerfile|helm|terraform|k8s|deploy"))] | length > 0)}
```

## Step 2b — Size classes (only when `<sibling>` is `pr-review`)

Tiering is on when `<sibling>` is `pr-review` and `--no-tiering` was not given. Otherwise every PR is `normal`
and the rest of this step does not apply.

| Class | When | How it runs |
|---|---|---|
| `trivial` | `lines ≤ 20`, `files ≤ 3`, not `sensitive` | grouped, up to 5 PRs per agent, budget tier, `--light` |
| `small` | `lines ≤ 100`, `files ≤ 8`, not `sensitive` | one agent per PR, budget tier, `--light` |
| `normal` | everything else | one agent per PR, as before: `--model` if given, no `--light` |

A `trivial` PR left alone in its group runs as `small`. The **budget tier** is the `small` tier of the harness
adapter (`adapters/<harness>.md`); `--small-model M` replaces its model. Size never lowers the bar: a light run
that finds something serious escalates, and Step 7 reviews that PR again in full.

## Step 3 — Locate the sibling skill and this repository

The harness tells you where this skill was loaded from (a base directory or the path of this `SKILL.md`). From
that directory, `<this-dir>`:

- `realpath <this-dir>/../<sibling>/SKILL.md` → `<sibling-path>`. Installations use symlinks, so this gives
  the real file; pass its **absolute** path to the agents, never a relative one.
- `realpath <this-dir>/../..` → `<source-root>` (where `bin/pr-batch` lives, used only by the fallback in
  "Launching one agent per PR").

If `<sibling-path>` does not exist, stop: `<sibling>` is not installed next to `<batch-skill>`.

## Step 4 — Run directory

Resolve it once, with the rule of the sibling's result contract: `printenv AGENT_SKILLS_RUNS` (empty or exit
code 1 means unset, then `printenv HOME` and use `<home>/.agent-skills/runs`), `date +%Y-%m-%dT%H-%M`, and
`mkdir -p <runs>`, then `mkdir <runs>/<timestamp>` (without `-p`) → `<run-dir>` (absolute). If that `mkdir`
fails because the directory exists, another batch started in the same minute: try `<timestamp>-2`, `-3`, … until
one succeeds, so two batches never share a summary. Every PR agent gets `--run-dir=<run-dir>`, so all reports of
the batch and the batch summary end up together. Write nothing else there.

## Step 5 — Announce the scope

Tell the user: repository, number of PRs (with their numbers and, with tiering, their class), `--parallel`, the
model for `normal` PR agents (or "same as this session") and for the budget tier, `<sibling-path>`,
`<run-dir>`, and whether it is a dry run. For `pr-fix`, also each PR's author and whether it is someone else's
branch, and `--no-push` if given.

- `--dry-run`: do not ask; continue.
- `pr-fix` with `--no-push`: nothing is written to GitHub or pushed; do not ask; continue.
- Otherwise every PR agent will post (it runs with `--auto`); for `pr-fix`, it **pushes commits to every PR
  branch** and replies in its threads, and leaves decisions pending. Ask once for the whole batch and wait. If the user
  narrows the list, use the narrowed list; if they decline, stop with the batch line (`total` 0). If nobody can
  answer (headless, or the harness cannot ask), **do not launch**: stop and say that a batch that posts needs
  either a confirmation or `--dry-run`.

## Step 6 — Run one agent per PR (or per group of trivial PRs)

A **unit** is one PR (`normal`, `small`) or one group of up to 5 `trivial` PRs, in list order. For each unit, in
order, keeping at most `--parallel` agents running:

1. **Re-check right before launching**: `gh pr view <n> --repo <owner>/<repo> --json state,isDraft`. If it is
   not `OPEN`, or it is a draft (except for `pr-fix`, which works on drafts), do not launch an agent: record a
   synthesized line (below) with `verdict` `SKIPPED` and `error` `closed`, `merged` or `draft`. In a group, re-check each PR and launch the group with
   the ones still open. If the call fails (PR not found), record `ERROR` with
   the message. When the harness launches agents from a script that cannot run shell commands, skip this and
   let the agent's own Step 0 do it; it stops with `SKIPPED` the same way.
2. **Launch a fresh agent** with its own context (not a fork of this conversation), the model from `--model` if
   given, and exactly this prompt, filling in the values:

   ```text
   Read the file <sibling-path> and follow it exactly for this invocation:
   <sibling> <owner>/<repo>#<n> --auto --run-dir=<run-dir> [--light] [--dry-run] [--lang=…] [--focus="…"] [pr-fix flags]
   Nobody can answer questions in this session. If you cannot read that file, invoke the skill <sibling> by
   name with the same arguments instead. Your final message must end with the result line that skill defines.
   ```

   `[pr-fix flags]` are `--no-push`, `--only=…` and `--no-checks` when given, for `pr-fix` only. The agent
   needs the harness's file-edit capability and permission to run the repository's check commands (see the
   adapter). `--light` and the budget tier for `small`; neither for `normal`. A group of `trivial` PRs gets one agent with
   the budget tier and this prompt instead:

   ```text
   Read the file <sibling-path> once and follow it for each of these invocations, one after another:
   <sibling> <owner>/<repo>#<n1> --auto --run-dir=<run-dir> --light [--dry-run] [--lang=…] [--focus="…"]
   <sibling> <owner>/<repo>#<n2> …
   Finish one PR before starting the next, and never carry a finding or an assumption from one PR to another.
   Nobody can answer questions in this session. If you cannot read that file, invoke the skill <sibling> by
   name with the same arguments instead. Your final message must end with the result line of each PR, in the
   order above, one per line, with nothing after the last one.
   ```

3. **Wait for completion, not for progress.** Use the longest wait the harness offers and do not poll with
   short timeouts or sleep between checks: every check is one more turn of this orchestrator.
4. **Keep only the last line** of the agent's final message, as text (for a group, the last N lines, N = the
   PRs it got, matched to them in order). Do not read the agent's earlier output and do not repair the line;
   Step 7 checks all of them at once. If the agent returned nothing or died, record a synthesized `ERROR` line
   for each of its PRs with `error` `no result line` (or the failure you saw).

**Synthesized line**: the sibling's contract with `skill` `<sibling>`, `repo`, `pr`, `head` `null`, the given
`verdict`, `max_priority` `null`, `findings` all `0`, `pending` `null`, `posted` `false`, `review_url` `null`,
`report` `null` (no agent ran, so there is no report), `summary` one short sentence, `error` the reason. For
`pr-fix` it follows its own contract instead: `head` and `new_head` `null`, `items` all `0`, `commits` `[]`,
`pushed` and `posted` `false`, `checks`, `worktree` and `report` `null`, plus `summary` and `error`.

A failed PR never stops the batch, and nothing is retried automatically: the summary gives the retry command.

## Step 7 — Escalations and batch summary files

When every PR has a line:

1. Check every line in one pass: write them, one per line and in PR order, to a temporary file from `mktemp`
   (not in `<run-dir>`), then `jq -cR 'fromjson? // null' <file>`. Each output line is the parsed object, or
   `null` where a line did not parse. A `null`, a non-object, or an object whose `pr` is not that PR's number
   becomes a synthesized `ERROR` line with `error` `invalid result line`. Delete the temporary file.
2. **Escalations.** Every checked line with `escalate` `true` gets a second, full review: one fresh agent per
   PR, as `normal` (the first prompt of Step 6, no `--light`, `--model` if given), at most `--parallel` at a
   time. Its line replaces the light one; check the new lines the same way. A full run cannot escalate, so this
   happens at most once per PR. Under `--dry-run` nothing was posted; without it the light run did not post
   either (`pr-review` forbids it when escalating), so the full run is the only review.
3. Add two fields to every line before writing it: `tier` (the class the PR started in: `trivial`, `small` or
   `normal`; `normal` when tiering was off) and `escalated` (`true` if step 2 ran it again).
4. `<run-dir>/summary.json`: a JSON array of those lines, in PR order. Write it with the write-file
   capability, then check it with `jq -e 'type == "array" and length == <count>' <run-dir>/summary.json`.
5. `<run-dir>/summary.md`, in the review language of the lines' `summary` (English if they disagree):
   - header: `<batch-skill>`, repository, date, flags, run directory;
   - one table, PR order: `PR | Tier | Verdict | Max priority | Blocking / Suggestion / Decision | Pending |
     Posted | Summary | Report`. `Tier` shows `small → normal` when the PR escalated; `Pending` only for
     `pr-ready`; a `null` report shows as `—`. For `pr-fix` the table is `PR | Verdict | Fixed / Already /
     Answered / Pending / Failed | Commits | Pushed | Replied | Checks | Summary | Report`, with no `Tier`;
   - escalated PRs listed again below the table with the light run's `escalate_reason`;
   - `ERROR` and `SKIPPED` PRs listed again below the table with their `error`;
   - if any PR has `ERROR`, the retry invocation: `<batch-skill> <failed numbers, comma-separated>` with the same
     flags, plus `--repo` if one was used;
   - **`READY` PRs only (`pr-ready-all`)**: for each, a section `#<n> <title>` with its approval block taken from
     its report, between the lines `<!-- approval:start -->` and `<!-- approval:end -->`. Extract just that
     part (`sed -n '/<!-- approval:start -->/,/<!-- approval:end -->/p' <report>`); if the shell cannot, read the
     report and copy only that block. Never write it from memory. If the markers are missing, write "approval
     block not found in the report" and the report path.
   - **`pr-fix-all` only**: for every PR with `items.pending` > 0, a section `#<n> <title> — pending` with the
     block between `<!-- pending:start -->` and `<!-- pending:end -->` of its report, extracted the same way;
     then the list of worktrees that were kept (`worktree` not `null`), with the reason in each line's `error`.

## Step 8 — Tell the user

Print the table from `summary.md`, the `ERROR`/`SKIPPED` list, the retry invocation if any, and the paths of
`summary.md` and `summary.json`. For `pr-ready-all`, say that the approval comments are in `summary.md` and that
approving is the user's call, in the GitHub UI. For `pr-fix-all`, say how many items are pending a decision,
that their proposals are in `summary.md`, and that `pr-fix <n>` run interactively asks about them; and suggest
`pr-ready-all` on the PRs that ended `FIXED` with `pushed` `true`.

## Step 9 — Batch line

End the final message with one line of JSON and nothing after it:

```json
{"skill":"pr-review-all","repo":"owner/repo","run_dir":"/abs/run-dir","total":2,"counts":{"REQUEST_CHANGES":1,"COMMENT":0,"ERROR":1,"SKIPPED":0},"failed":[405],"dry_run":true,"summary_json":"/abs/run-dir/summary.json","summary_md":"/abs/run-dir/summary.md"}
```

`skill` is `<batch-skill>`; `counts` has one key per verdict of the calling skill, zeros included (for
`pr-fix-all`: `FIXED`, `PARTIAL`, `NOTHING_TO_FIX`, `PLANNED`, `ERROR`, `SKIPPED`); `failed`
lists the PRs with `ERROR`. With no PRs, `run_dir`, `summary_json` and `summary_md` are `null`. Check it
parses with `jq` before printing it (temporary file from `mktemp`, `jq -c .`, delete the file).

## Launching one agent per PR

"Launch a fresh agent with its own context" is a capability; each harness meets it differently, and the adapter
for the harness has the details (`adapters/<harness>.md` under `<source-root>`):

| Harness | How |
|---|---|
| A workflow/scripting tool that spawns agents (Claude Code's `Workflow`) | one script, a pool of `--parallel` workers, one agent per PR; the prompt above as each agent's prompt |
| A tool that spawns one subagent per call (Claude Code's `Agent`) | up to `--parallel` calls per turn, then the next wave as they finish |
| Codex `multi_agent` | `spawn_agent` with `fork_turns: "none"` (otherwise the child inherits this whole conversation), `model` if given, and the budget tier as `reasoning_effort`; `wait_agent`; keep at most `--parallel` alive. Not under `codex exec --ephemeral` |
| No subagents, or they cannot be launched from a skill | run `<source-root>/bin/pr-batch --harness <harness> --skill <sibling> --repo <owner>/<repo> --run-dir <run-dir> --parallel N [--model M] [--small-model M] [--no-tiering] [--dry-run \| --yes] [--lang L] [--focus F] [--no-push] [--only K] [--no-checks] [--allow-tool T]… <numbers>` (`--yes` because Step 5 already confirmed; for `pr-fix`, one `--allow-tool` per check command the repository needs, such as `"Bash(npm *)"`); it does Steps 6–7, tiering and escalations included, with one headless session per unit. Then do Steps 8–9 from its `summary.json` |
