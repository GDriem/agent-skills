---
name: pr-review-all
description: Run pr-review on every open, non-draft pull request of a GitHub repository, or on a list of PR numbers, with one fresh agent per PR so no PR shares context with another. Small PRs run on a cheaper tier in light mode and escalate to a full review when they find something serious. Collects each agent's result line into a batch summary. Never approves. Supports --dry-run, --parallel, --model, --small-model, --no-tiering, --lang, --focus and --repo. Use when asked to review all open PRs or a batch of PRs.
---

# pr-review-all

Review a batch of pull requests by running the sibling skill `pr-review` once per PR, each in its own agent with
its own context. This skill only lists, launches and collects; the review logic lives in `pr-review` and is
never repeated here.

**Arguments.** The arguments are the text that follows the skill name in the message that invoked this skill.
Some harnesses substitute them here: `$ARGUMENTS`. If that still reads as a literal placeholder, use the text
after the skill name instead.

| Argument | Meaning |
|---|---|
| (empty) or `all` | every open, non-draft PR of the repository |
| `401,405,410` | only these PR numbers (also how you retry the ones that failed) |
| `401-410` | the open PRs numbered 401 to 410; mixes with numbers: `401,405-410` |
| `--repo owner/repo` | target another repository instead of the current directory's |
| `--parallel N` | at most N PR agents at a time; default 3; `1` runs them one after another |
| `--model M` | model for the `normal` PR agents (the orchestrator keeps the session's model) |
| `--small-model M` | model for the budget tier (`trivial` and `small` PRs); default: the harness's small tier |
| `--no-tiering` | every PR runs as `normal`: one full review per agent, no light mode, no grouping |
| `--dry-run` | every PR agent runs `pr-review --dry-run`: nothing is written to GitHub, nothing is asked |
| `--lang=en\|es\|…` | forwarded to every PR agent |
| `--focus="<criteria>"` | forwarded to every PR agent |

This skill is repository-agnostic: the repository, the PR list and the sibling skill's path are resolved when
it runs.

**Hard rules, in every mode:**

- Never approve a PR.
- The orchestrator never reads a diff, a changed file or the sibling's `references/`. It reads PR metadata from
  `gh`, each agent's last line, and, for the summary, nothing else.
- Every PR agent runs with `--auto`: there is nobody to answer it. Without `--dry-run` that means it posts, so
  the batch asks once for the whole scope before launching (see `references/batch.md`).
- One PR failing never stops the batch.
- Size picks the tier, never the bar: a light run that finds something serious escalates and the PR gets a
  full review (Step 2b and Step 7 of `references/batch.md`).

## What to do

| Value used by `references/batch.md` | For this skill |
|---|---|
| `<sibling>` | `pr-review` |
| `<batch-skill>` | `pr-review-all` |
| Verdicts in the summary | `REQUEST_CHANGES`, `COMMENT`, `ERROR`, `SKIPPED` |

Follow `references/batch.md` from Step 1 to the end.
