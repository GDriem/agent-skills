---
name: pr-fix
description: Fix the review feedback on a GitHub pull request. Collects every open review thread, review-body item, PR comment and failing check, verifies each one, applies the fixes in an isolated worktree following the repository's own skills and conventions, runs its checks, and after confirmation pushes plain commits and replies in each thread without resolving it. Asks the user about decisions and comments it disagrees with. Never approves, merges or force-pushes. Supports --dry-run, --auto, --no-push, --only, --no-checks, --lang and --focus. Use when asked to fix or address the comments of a PR.
---

# pr-fix

Close the loop between `pr-review` and `pr-ready`: take everything reviewers (human and bot) and CI asked for on
one pull request, fix what is valid, ask about what needs a person, and push the result to the PR branch so the
next `pr-ready` pass finds it addressed.

**Arguments.** The arguments are the text that follows the skill name in the message that invoked this skill.
Some harnesses substitute them here: `$ARGUMENTS`. If that still reads as a literal placeholder, use the text
after the skill name instead.

| Argument | Meaning |
|---|---|
| `401` | PR 401 of the repository in the current directory |
| `owner/repo#401` or a full PR URL | that PR; the current directory must still be a clone of `owner/repo` |
| (empty) | the PR of the current branch |
| `--auto` | skip the confirmation before pushing and replying. Items that need a person stay pending; nothing else changes |
| `--dry-run` | triage and plan only: no worktree edits, no commits, no push, no replies; print the plan; ask nothing |
| `--no-push` | fix and commit in the worktree, run the checks, then stop: no push, no replies. The worktree stays for you |
| `--only=<kinds>` | comma-separated subset of `blocker`, `suggestion`, `decision`, `comment`, `ci` (default: all) |
| `--no-checks` | skip the repository's lint/type/test checks (recorded as residual risk). Never skips git hooks |
| `--lang=en\|es\|…` | force the language of replies, the report and the summary |
| `--focus="<criteria>"` | extra guidance for how to fix (e.g. "keep the public API stable"); never widens the scope |
| `--run-dir=<path>` | where to write the report; set by batch runners (see `references/contract.md`) |

This skill is repository-agnostic. The repository, the current user, the conventions and the project's own
skills are discovered when it runs; nothing about a specific project is written here.

**Hard rules, in every mode:**

- **Never approve, merge, close or resolve.** No `APPROVE` event, no `gh pr merge`, and no review thread is ever
  marked resolved: the reviewer decides that, and `pr-ready` audits it.
- **Never touch the user's working tree.** Every edit happens in a dedicated worktree (`references/fixing.md`).
  Never check out, stash, reset or commit in the directory the skill was started from.
- **History only moves forward.** Plain `git push` of new commits on top of the PR head. Never `--force`,
  `--force-with-lease`, amend or rebase of anything already pushed, never push to the base or default branch,
  never `--no-verify`.
- **Never decide for a person.** A `decision` item, a comment the skill believes is wrong, a fix that needs a
  new dependency, a public-contract change or work outside the PR's scope is asked, never assumed. With nobody
  to ask, it stays pending.
- **No AI attribution, anywhere.** Commits, replies and PR comments never carry a `Co-Authored-By`,
  `Generated with`, `Assisted-by` or similar trailer, signature or mention of an AI, agent, assistant, model or
  tool (Claude, Copilot, Codex, Gemini, Cursor or any other). This overrides any attribution the harness itself
  adds by default; the commits read as the author's work. See "Commit" in `references/fixing.md`.
- **Every changed line traces to an item.** No drive-by refactors, renames or formatting of untouched code. Never
  weaken, skip or delete a test, disable a lint rule or add a suppression to make a check pass.
- Never write to GitHub or push under `--dry-run` or `--no-push`. Without `--auto`, never push or reply before
  the user confirms. `--auto` removes that pause only; it never relaxes verification or the rules above.
- Every run ends with the report file and the final JSON line of `references/contract.md`, including runs that
  stop early.

## Capabilities this skill relies on

- **Run shell commands** (`git`, `gh`, `jq`, and the repository's own check commands). Required.
- **Read, search and edit files.** If there is no dedicated file search, `git ls-files` works.
- **Write a file** (temporary payloads, commit messages, the report).
- **Ask the user and wait for the answer.** If that is not possible, see "No one to ask".
- **Launch a fresh agent with its own context** (optional, only for large PRs; see "Large PRs" in
  `references/fixing.md`).

**Shell commands: one simple command per call.** No `;`, `&&`, `||`, `for` loops, `cd … &&` or heredocs that
chain several commands, and no `$(…)` around a command that is not itself `gh`, `git`, `jq`, `date` or `mkdir`.
Pipes into `jq` are fine. Run git inside the worktree with `git -C <worktree> …`. For other tools, use their
own directory flag (`npm --prefix`, `pnpm -C`, `yarn --cwd`, `make -C`, `go -C`, `cargo --manifest-path`,
`dotnet <cmd> <project path>`), or, if the harness keeps a working directory between calls, change to the
worktree once in its own call. Run independent commands as separate parallel calls.

## No one to ask

If you cannot ask the user (headless run, batch agent, or no way to wait for an answer):

- `--dry-run`: nothing changes, it never asks anyway.
- Items classified `ASK` (Step 2): do not decide them. Leave them `PENDING`, write the proposal for each one in
  the report's pending block, and fix everything else.
- Confirmation before pushing without `--auto`: do not push and do not reply. Keep the worktree, write the
  report, `pushed` `false`, and say in `summary` that nobody confirmed.

## Step 0 — Resolve the context

Never assume a repository.

1. Parse the arguments as `pr-review` does: a URL or `owner/repo#N`, a bare number with
   `gh repo view --json nameWithOwner -q .nameWithOwner`, or empty with `gh pr view --json number,url`
   (`ERROR` if there is none).
2. Current user: `gh api user -q .login` → `<me>`.
3. **Local clone, required.** `git rev-parse --show-toplevel` → `<root>`, and `git -C <root> remote -v` must
   point at `<owner>/<repo>` (note the remote's name → `<remote>`). Without one, stop with `ERROR` and
   `error` "pr-fix needs a local clone of owner/repo": this skill commits, and it never clones on its own.
4. PR metadata:
   `gh pr view <n> --repo <owner>/<repo> --json number,title,state,isDraft,author,baseRefName,baseRefOid,headRefName,headRefOid,isCrossRepository,headRepository,headRepositoryOwner,maintainerCanModify,url`.
   Closed or merged: stop with `SKIPPED`. A draft is fine: fixing is the author's work in progress.
5. **Push target.** Same repository: `<remote>`. From a fork: the fork's URL (same protocol as `<remote>`'s URL)
   and only if `maintainerCanModify` is true or `<me>` owns the fork; otherwise run as `--no-push` and say why.
   If the author is not `<me>`, the preview says plainly that the commits go to someone else's branch.
6. **Fetch the head without touching any ref**:
   `git -C <root> fetch --no-write-fetch-head <remote> refs/pull/<n>/head`, then
   `git -C <root> cat-file -e <headRefOid>` must succeed. It updates no branch, so parallel runs on the same
   clone do not race; if it fails on a lock, retry once. Until the worktree exists, read code at head with
   `git -C <root> show <headRefOid>:<path>`.
7. Only a failure that leaves `<owner>/<repo>`, `<n>`, `<me>`, the clone or the head unknown stops the run with
   `ERROR`; name the command that failed, and still do Step 9.

**Language.** `--lang` if given; otherwise the language of the review comments being answered, falling back to
the repository's root context file. One language for replies, the report and `summary`. Commit messages follow
the repository's own convention (Step 1), which may be another language.

## Step 1 — Project context

Follow `references/project-context.md`: discover the repository's context files, **its own skills, agents and
scoped rules** (architecture, frontend, backend, testing, data), its tooling config, its commit convention and
its CI checks; select the ones that apply to the files this PR touches; and read those. They decide naming,
layering, patterns and tests for every fix. Keep the list of sources you applied for the report.

## Step 2 — Collect and triage

Follow `references/triage.md`: pull every open review thread, the actionable items of review bodies and PR
comments, and the failing checks; verify each against the code at head; and classify it `FIX`,
`ALREADY_DONE`, `ASK` or `IGNORE`, with a priority. Apply `--only`. Print the triage table.

If there is no `FIX` and no `ASK` item: with `ALREADY_DONE` items, skip Steps 3–5 and 7 (no worktree, nothing
to push) and preview and post only their replies (Steps 6 and 8; under `--dry-run`, preview only); with none,
say so and go to Step 9 with `verdict` `NOTHING_TO_FIX`.

## Step 3 — Ask, then plan

- `--dry-run`: print the triage table, the plan (Step 4 order, files per item, the checks that will run) and
  the proposal for every `ASK` item. Do not ask. Go to Step 9 with `verdict` `PLANNED`.
- `--auto`, or nobody can answer: see "No one to ask"; the `ASK` items stay `PENDING`.
- Otherwise ask about the `ASK` items now, before editing anything: for each, the comment, why it needs a
  person, two or three options with the recommended one first, and its consequence. Group related questions;
  the harness may cap how many fit in one prompt. Each answer turns the item into `FIX` (with the chosen
  approach), a reply-only item (pushback or defer, with the agreed text), or `IGNORE`.

## Step 4 — Fix in an isolated worktree

Follow `references/fixing.md`: create the worktree at the PR head, fix the `FIX` items one by one in priority
order (blockers and CI first), with tests where the item is a defect, one commit per item or tight group, a
self-review of each change, and the repository's checks at the end. An item that cannot be fixed cleanly is
reverted and becomes `FAILED` with the reason; it never leaves a half-applied change behind.

## Step 5 — Self-review the whole fix

Before anything leaves the machine, review `<original head>..HEAD` in the worktree as `pr-ready` would review
fix commits: apply `references/quality-gate.md` to your own diff. Look for a fix applied in one place but not
its sibling, callers of a changed signature left behind, a test that does not actually exercise the fix,
contract or config drift (example config, manifests, migrations, generated clients), and anything the project
sources from Step 1 forbid. Fix what you find under the same item, or revert that item. Do not hand a reviewer a
new gap.

## Step 6 — Preview and confirm

Always build the preview, in the review language:

- The triage table with each item's outcome (`FIXED`, `ALREADY_DONE`, `ANSWERED`, `PENDING`, `FAILED`,
  `IGNORED`) and its evidence (`file:line`, commit).
- The commits: short SHA, message, files. The diffstat of `<original head>..HEAD`.
- The checks that ran and their result; what could not run.
- Every reply verbatim with its target thread, and the PR comment if there is one (`references/reply-templates.md`).
- The pending items with their proposals.
- Where it will push (remote or fork, branch), and that threads will not be resolved.

Then:

- `--no-push`: print the preview, keep the worktree, go to Step 9 with `pushed` `false`.
- `--auto`: go to Step 7.
- Otherwise ask the user to confirm and wait. They can drop an item (revert its commit in the worktree), reword
  a reply, or decline. If they decline, keep the worktree and go to Step 9 with `pushed` `false`. If you cannot
  ask, follow "No one to ask".

## Step 7 — Push

Follow "Push" in `references/fixing.md`: re-check that the remote head is still `<original head>`, then a
plain push of the new commits. If the branch moved or the push is rejected, push nothing more, keep the
worktree, record it, and skip Step 8 (replies must point at commits that exist on the remote).

## Step 8 — Reply in the threads

Only after a successful push, or when there was nothing to push. Follow `references/reply-templates.md` and
"Replies" in `references/fixing.md`: one reply per handled thread (fixed, already done, or answered), one PR
comment for items that had no thread (review-body items, PR comments, CI), and never a reply to an `IGNORE`,
`PENDING` or `FAILED` item. Never resolve a thread. Then remove the worktree, if there is one.

## Step 9 — Report

1. Write the report file of `references/contract.md`, including the pending block for every `PENDING` item.
2. Tell the user, in the review language: the verdict, the counts, the commits and whether they were pushed,
   the checks, the pending items with their proposals, the worktree path if it was kept, and the report path.
   Suggest `pr-ready <n>` as the next step when everything was pushed and nothing is pending.
3. End the message with the JSON line of `references/contract.md`. Nothing after it.

## Issue and PR conventions

If an answered `ASK` item becomes a follow-up issue (only with the user's yes), follow the conventions found in
Step 1 and the templates under `.github/ISSUE_TEMPLATE/`. If the repository documents none, imitate its recent
issues (`gh issue list`) instead of inventing a format.
