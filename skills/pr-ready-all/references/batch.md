# Batch procedure

Shared by `pr-review-all` and `pr-ready-all`. The calling `SKILL.md` gives `<sibling>` (the one-PR skill) and
`<batch-skill>` (its own name). Same shell rule as the sibling: one simple command per call, pipes into `jq`
are fine, independent commands go in parallel calls.

The orchestrator's context should stay small no matter how many PRs there are: PR numbers and titles from `gh`,
one JSON line per PR, and nothing else. Never read a diff, a changed file, a PR's review threads or the
sibling's `references/` here; the PR agents do that.

## Step 1 — Parse the arguments

- PR numbers: comma- or space-separated integers greater than 0 (a leading `#` is fine). Drop duplicates and
  keep the order given. Anything else that is not a flag (a word, `0`, `-3`, `12a`) stops the batch before
  anything is launched: say which token is invalid.
- `all` or no numbers: list the repository (Step 2).
- `--repo owner/repo`, `--parallel N` (integer ≥ 1, default 3), `--model M`, `--dry-run`, `--lang=…`,
  `--focus="…"`. Keep `--lang` and `--focus` verbatim to forward them.

## Step 2 — Repository and PR list

1. Repository: `--repo` if given, else `gh repo view --json nameWithOwner -q .nameWithOwner`. If that fails,
   stop: the batch must run inside a clone with a GitHub remote, or get `--repo`.
2. With explicit numbers, use them as they are; their state is checked per PR in Step 6.
3. Otherwise:
   `gh pr list --repo <owner>/<repo> --state open --limit 1000 --json number,title,isDraft --jq '[.[] | select(.isDraft | not) | {number,title}]'`.
   `gh` pages through the API up to `--limit`. If it returns exactly 1000, say the list may be truncated.
4. No PRs: say so, write no run directory, and end with the batch line of Step 9 (`total` 0).

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
`mkdir -p <runs>/<timestamp>` → `<run-dir>` (absolute). Every PR agent gets `--run-dir=<run-dir>`, so all
reports of the batch and the batch summary end up together. Write nothing else there.

## Step 5 — Announce the scope

Tell the user: repository, number of PRs (with their numbers), `--parallel`, the model for PR agents (or "same
as this session"), `<sibling-path>`, `<run-dir>`, and whether it is a dry run.

- `--dry-run`: do not ask; continue.
- Otherwise every PR agent will post (it runs with `--auto`). Ask once for the whole batch and wait. If the user
  narrows the list, use the narrowed list; if they decline, stop with the batch line (`total` 0). If nobody can
  answer (headless, or the harness cannot ask), **do not launch**: stop and say that a batch that posts needs
  either a confirmation or `--dry-run`.

## Step 6 — Run one agent per PR

For each PR, in order, keeping at most `--parallel` agents running:

1. **Re-check right before launching**: `gh pr view <n> --repo <owner>/<repo> --json state,isDraft`. If it is
   not `OPEN`, or it is a draft, do not launch an agent: record a synthesized line (below) with `verdict`
   `SKIPPED` and `error` `closed`, `merged` or `draft`. If the call fails (PR not found), record `ERROR` with
   the message. When the harness launches agents from a script that cannot run shell commands, skip this and
   let the agent's own Step 0 do it; it stops with `SKIPPED` the same way.
2. **Launch a fresh agent** with its own context (not a fork of this conversation), the model from `--model` if
   given, and exactly this prompt, filling in the values:

   ```text
   Read the file <sibling-path> and follow it exactly for this invocation:
   <sibling> <owner>/<repo>#<n> --auto --run-dir=<run-dir> [--dry-run] [--lang=…] [--focus="…"]
   Nobody can answer questions in this session. If you cannot read that file, invoke the skill <sibling> by
   name with the same arguments instead. Your final message must end with the result line that skill defines.
   ```

3. **Wait for completion, not for progress.** Use the longest wait the harness offers and do not poll with
   short timeouts or sleep between checks: every check is one more turn of this orchestrator.
4. **Keep only the last line** of the agent's final message, as text. Do not read the agent's earlier output
   and do not repair the line; Step 7 checks all of them at once. If the agent returned nothing or died, record
   a synthesized `ERROR` line with `error` `no result line` (or the failure you saw).

**Synthesized line**: the sibling's contract with `skill` `<sibling>`, `repo`, `pr`, `head` `null`, the given
`verdict`, `max_priority` `null`, `findings` all `0`, `pending` `null`, `posted` `false`, `review_url` `null`,
`report` `null` (no agent ran, so there is no report), `summary` one short sentence, `error` the reason.

A failed PR never stops the batch, and nothing is retried automatically: the summary gives the retry command.

## Step 7 — Batch summary files

When every PR has a line:

1. Check every line in one pass: write them, one per line and in PR order, to a temporary file from `mktemp`
   (not in `<run-dir>`), then `jq -cR 'fromjson? // null' <file>`. Each output line is the parsed object, or
   `null` where a line did not parse. A `null`, a non-object, or an object whose `pr` is not that PR's number
   becomes a synthesized `ERROR` line with `error` `invalid result line`. Delete the temporary file.
2. `<run-dir>/summary.json`: a JSON array of the checked lines, in PR order. Write it with the write-file
   capability, then check it with `jq -e 'type == "array" and length == <count>' <run-dir>/summary.json`.
3. `<run-dir>/summary.md`, in the review language of the lines' `summary` (English if they disagree):
   - header: `<batch-skill>`, repository, date, flags, run directory;
   - one table, PR order: `PR | Verdict | Max priority | Blocking / Suggestion / Decision | Pending | Posted |
     Summary | Report`. `Pending` only for `pr-ready`; a `null` report shows as `—`;
   - `ERROR` and `SKIPPED` PRs listed again below the table with their `error`;
   - if any PR has `ERROR`, the retry invocation: `<batch-skill> <failed numbers, comma-separated>` with the same
     flags, plus `--repo` if one was used;
   - **`READY` PRs only (`pr-ready-all`)**: for each, a section `#<n> <title>` with its approval block taken from
     its report, between the lines `<!-- approval:start -->` and `<!-- approval:end -->`. Extract just that
     part (`sed -n '/<!-- approval:start -->/,/<!-- approval:end -->/p' <report>`); if the shell cannot, read the
     report and copy only that block. Never write it from memory. If the markers are missing, write "approval
     block not found in the report" and the report path.

## Step 8 — Tell the user

Print the table from `summary.md`, the `ERROR`/`SKIPPED` list, the retry invocation if any, and the paths of
`summary.md` and `summary.json`. For `pr-ready-all`, say that the approval comments are in `summary.md` and that
approving is the user's call, in the GitHub UI.

## Step 9 — Batch line

End the final message with one line of JSON and nothing after it:

```json
{"skill":"pr-review-all","repo":"owner/repo","run_dir":"/abs/run-dir","total":2,"counts":{"REQUEST_CHANGES":1,"COMMENT":0,"ERROR":1,"SKIPPED":0},"failed":[405],"dry_run":true,"summary_json":"/abs/run-dir/summary.json","summary_md":"/abs/run-dir/summary.md"}
```

`skill` is `<batch-skill>`; `counts` has one key per verdict of the calling skill, zeros included; `failed`
lists the PRs with `ERROR`. With no PRs, `run_dir`, `summary_json` and `summary_md` are `null`. Check it
parses with `jq` before printing it (temporary file from `mktemp`, `jq -c .`, delete the file).

## Launching one agent per PR

"Launch a fresh agent with its own context" is a capability; each harness meets it differently, and the adapter
for the harness has the details (`adapters/<harness>.md` under `<source-root>`):

| Harness | How |
|---|---|
| A workflow/scripting tool that spawns agents (Claude Code's `Workflow`) | one script, a pool of `--parallel` workers, one agent per PR; the prompt above as each agent's prompt |
| A tool that spawns one subagent per call (Claude Code's `Agent`) | up to `--parallel` calls per turn, then the next wave as they finish |
| Codex `multi_agent` | `spawn_agent` with `fork_turns: "none"` (otherwise the child inherits this whole conversation) and `model` if given; `wait_agent`; keep at most `--parallel` alive. Not under `codex exec --ephemeral` |
| No subagents, or they cannot be launched from a skill | run `<source-root>/bin/pr-batch --harness <harness> --skill <sibling> --repo <owner>/<repo> --run-dir <run-dir> --parallel N [--model M] [--dry-run \| --yes] [--lang L] [--focus F] <numbers>` (`--yes` because Step 5 already confirmed); it does Steps 6–7 with one headless session per PR. Then do Steps 8–9 from its `summary.json` |
