---
name: pr-fix-all
description: Run pr-fix on a batch of GitHub pull requests (your open PRs with review feedback, a list, or a range of PR numbers) with one fresh agent per PR, each in its own worktree, so no PR shares context or files with another. Collects each agent's result line into a batch summary with the decisions left pending for you. Never approves, merges or force-pushes. Supports --dry-run, --no-push, --only, --no-checks, --any-author, --parallel, --model, --lang, --focus and --repo. Use when asked to fix or address the review comments of several PRs.
---

# pr-fix-all

Fix the review feedback of a batch of pull requests by running the sibling skill `pr-fix` once per PR, each in
its own agent with its own context and its own git worktree. This session only lists, launches and collects; the
fixing logic lives in `pr-fix` and is never repeated here.

**Arguments.** The arguments are the text that follows the skill name in the message that invoked this skill.
Some harnesses substitute them here: `$ARGUMENTS`. If that still reads as a literal placeholder, use the text
after the skill name instead.

| Argument | Meaning |
|---|---|
| (empty) or `all` | your open, non-draft PRs that have review feedback or a failing check |
| `401,405,410` | only these PR numbers (also how you retry the ones that failed) |
| `401-410` | the open PRs numbered 401 to 410; mixes with numbers: `401,405-410` |
| `--any-author` | with `all` or a range, include PRs authored by others too (their branches get your commits) |
| `--repo owner/repo` | must be the repository of the current directory's clone: `pr-fix` commits in it |
| `--parallel N` | at most N PR agents at a time; default 2 (each one edits and runs the checks); `1` runs them in series |
| `--model M` | model for the PR agents (the orchestrator keeps the session's model) |
| `--dry-run` | every agent runs `pr-fix --dry-run`: triage and plan only, nothing edited, pushed or posted, nothing asked |
| `--no-push` | every agent fixes and commits in its worktree but pushes and posts nothing |
| `--only=<kinds>` | forwarded: `blocker`, `suggestion`, `decision`, `comment`, `ci` |
| `--no-checks` | forwarded: skip the repository's checks (residual risk) |
| `--lang=en\|es\|…` | forwarded to every PR agent |
| `--focus="<criteria>"` | forwarded to every PR agent |

This skill is repository-agnostic: the repository, the PR list and the sibling skill's path are resolved when it
runs.

**Hard rules, in every mode:**

- **Never approve, merge, force-push or resolve a thread**, here or in any agent.
- The orchestrator never reads a diff, a changed file, a review thread or the sibling's `references/`. It reads
  PR metadata from `gh`, each agent's last line and, for every PR with pending items, the pending block of its
  report.
- Every PR agent runs with `--auto`: there is nobody to answer it, so its decisions stay pending and everything
  else is fixed, pushed and replied to. Without `--dry-run` or `--no-push` the batch asks once for the whole
  scope before launching (see `references/batch.md`).
- Each agent works in its own worktree; the user's working tree is never touched.
- One PR failing never stops the batch.

## What to do

| Value used by `references/batch.md` | For this skill |
|---|---|
| `<sibling>` | `pr-fix` |
| `<batch-skill>` | `pr-fix-all` |
| Verdicts in the summary | `FIXED`, `PARTIAL`, `NOTHING_TO_FIX`, `PLANNED`, `ERROR`, `SKIPPED` |

Follow `references/batch.md` from Step 1 to the end. Size tiering does not apply to `pr-fix`.
