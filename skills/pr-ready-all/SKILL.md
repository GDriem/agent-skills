---
name: pr-ready-all
description: Run pr-ready on every open, non-draft pull request of a GitHub repository, or on a list of PR numbers, with one fresh agent per PR so no PR shares context with another. Collects each agent's result line into a batch summary with the approval comment of every READY PR. Never approves. Supports --dry-run, --parallel, --model, --lang, --focus and --repo. Use when asked which open PRs are ready to approve.
---

# pr-ready-all

Check a batch of pull requests after a review round by running the sibling skill `pr-ready` once per PR, each
in its own agent with its own context. This skill only lists, launches and collects; the readiness logic lives
in `pr-ready` and is never repeated here.

**Arguments.** The arguments are the text that follows the skill name in the message that invoked this skill.
Some harnesses substitute them here: `$ARGUMENTS`. If that still reads as a literal placeholder, use the text
after the skill name instead.

| Argument | Meaning |
|---|---|
| (empty) or `all` | every open, non-draft PR of the repository |
| `401,405,410` | only these PR numbers (also how you retry the ones that failed) |
| `--repo owner/repo` | target another repository instead of the current directory's |
| `--parallel N` | at most N PR agents at a time; default 3; `1` runs them one after another |
| `--model M` | model for the PR agents (the orchestrator keeps the session's model) |
| `--dry-run` | every PR agent runs `pr-ready --dry-run`: nothing is written to GitHub, nothing is asked |
| `--lang=en\|es\|…` | forwarded to every PR agent |
| `--focus="<criteria>"` | forwarded to every PR agent |

This skill is repository-agnostic: the repository, the PR list and the sibling skill's path are resolved when
it runs.

**Hard rules, in every mode:**

- **Never approve.** A `READY` verdict means the approval comment is in the summary for the user to post from
  the GitHub UI.
- The orchestrator never reads a diff, a changed file or the sibling's `references/`. It reads PR metadata from
  `gh`, each agent's last line and, for every `READY` PR, the approval block of its report.
- Every PR agent runs with `--auto`: there is nobody to answer it. Without `--dry-run` that means it posts the
  pending-items review of every `NOT_READY` PR, so the batch asks once for the whole scope before launching (see
  `references/batch.md`).
- One PR failing never stops the batch.

## What to do

| Value used by `references/batch.md` | For this skill |
|---|---|
| `<sibling>` | `pr-ready` |
| `<batch-skill>` | `pr-ready-all` |
| Verdicts in the summary | `READY`, `NOT_READY`, `ERROR`, `SKIPPED` |

Follow `references/batch.md` from Step 1 to the end.
