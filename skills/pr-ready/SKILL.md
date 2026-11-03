---
name: pr-ready
description: Second-pass check of a GitHub pull request after a review round. Audits every review thread against the code at head, reviews the fix commits for new gaps, and gives a READY or NOT_READY verdict. Never approves; when ready it hands over an approval comment to paste. Supports --dry-run, --auto, --lang and --focus. Use when asked whether a PR is ready to approve.
---

# pr-ready

Verify a pull request after a review round: check that every comment, human and bot, was actually addressed in
the code, look for gaps the fixes introduced, and decide whether it is ready to approve.

**Arguments.** The arguments are the text that follows the skill name in the message that invoked this skill.
Some harnesses substitute them here: `$ARGUMENTS`. If that still reads as a literal placeholder, use the text
after the skill name instead.

| Argument | Meaning |
|---|---|
| `355` | PR 355 of the repository in the current directory |
| `owner/repo#355` or a full PR URL | that PR, whatever the current directory is |
| (empty) | the PR of the current branch |
| `--auto` | skip the confirmation before posting pending items. Nothing else changes |
| `--dry-run` | do everything except write to GitHub; print the full preview; ask nothing |
| `--lang=en\|es\|…` | force the review language |
| `--focus="<criteria>"` | extra criteria for the fresh gap sweep; never replaces the thread audit |
| `--run-dir=<path>` | where to write the report; set by batch runners (see `references/contract.md`) |

This skill is repository-agnostic. The repository, the current user and the conventions are detected when it
runs; nothing about a specific project is written here.

**Hard rules, in every mode:**

- **Never approve.** No `APPROVE` event, no `gh pr review --approve`. When the PR is ready, the skill writes an
  approval comment for the user to post from the GitHub UI.
- Never write to GitHub under `--dry-run`. Without `--auto`, never write before the user confirms.
- `--auto` removes the confirmation pause only. It does not relax verification, anchoring, or "one review per
  PR".
- Never check out a branch, edit, stage or commit anything in the working tree.
- Every run ends with the report file and the final JSON line of `references/contract.md`, including runs that
  stop early.

## Capabilities this skill relies on

- **Run shell commands** (`git`, `gh`, `jq`). Required.
- **Read files** and **search files by name**. If there is no dedicated file search, `git ls-files` works.
- **Write a file** (the temporary payload, the report).
- **Ask the user and wait for the answer.** If that is not possible, see "No one to ask".

**Shell commands: one simple command per call.** No `;`, `&&`, `||`, `for` loops, `cd … &&` or heredocs that
chain several commands, and no `$(…)` around a command that is not itself `gh`, `git`, `jq`, `date` or
`mkdir`. Pipes into `jq` are fine. Harnesses pre-approve commands by prefix (`gh`, `git`), and a compound
command usually falls outside the rule and is denied when no one can approve it. Run independent commands as
separate parallel calls instead.

## No one to ask

If you cannot ask the user (headless run, batch agent, or no way to wait for an answer):

- `--dry-run`: nothing changes, it never asks anyway.
- Draft PR: stop with `verdict` `SKIPPED` and `error` "draft".
- Confirmation before posting without `--auto`: do not post. Write the report, `posted` `false`, and say in
  `summary` that it was not posted because nobody confirmed.

## Step 0 — Resolve the context

Never assume a repository.

1. Parse the arguments. A full URL or `owner/repo#N` gives `<owner>/<repo>` and `<n>`; a bare number uses
   `gh repo view --json nameWithOwner -q .nameWithOwner`; empty means the current branch's PR
   (`gh pr view --json number,url`), and `ERROR` if there is none.
2. Current user: `gh api user -q .login` → `<me>`.
3. Local checkout (optional): `git rev-parse --show-toplevel` → `<root>`, used only if the current
   directory's remote is `<owner>/<repo>`. If either command fails, or the remote is another repository, that
   is **not** an error: read everything through `gh` (contents and trees at the head SHA).
4. Only a failure that leaves `<owner>/<repo>`, `<n>` or `<me>` unknown stops the run (a bare number or empty
   argument with no usable remote, `gh` not authenticated, PR not found). Then stop with `ERROR`, name the
   command that failed, and still do Step 6 (report file and final JSON line). Do not guess.
5. Closed or merged PR: `SKIPPED`. Draft: under `--dry-run` continue and note it; otherwise ask (or follow
   "No one to ask").
6. If the author is `<me>`, any posting uses `COMMENT`.

**Language.** `--lang` if given; otherwise the language of the human review comments already on the PR,
falling back to the repository's root context file. One language for everything.

**Focus.** Keep `--focus` verbatim and apply it during the gap sweep (Step 3). It never suppresses the audit of
earlier comments, regressions, contracts, security or CI.

## Step 1 — Pull the full review state

```bash
gh api graphql -f owner=<owner> -f repo=<repo> -F number=<n> -f query='
query($owner:String!,$repo:String!,$number:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      isDraft state reviewDecision mergeable baseRefOid headRefOid
      commits(last:1){ nodes{ commit{ oid statusCheckRollup{ state } } } }
      reviews(first:50){ nodes{ author{login} state submittedAt body } }
      reviewThreads(first:100){
        nodes{
          id isResolved isOutdated path line
          comments(first:30){ nodes{ databaseId author{login} body createdAt } }
        }
      }
    }
  }
}'
```

In parallel:

```bash
gh pr view <n> --repo <owner>/<repo> --json title,body,author,baseRefName,headRefName,additions,deletions,changedFiles,url
gh pr diff <n> --repo <owner>/<repo>
gh pr checks <n> --repo <owner>/<repo>
gh api "repos/<owner>/<repo>/pulls/<n>/commits" --paginate --jq '.[] | "\(.sha[0:8]) \(.commit.committer.date) \(.commit.message | split("\n")[0])"'
```

`gh pr checks` exits non-zero when a check fails or is pending; that is data, not an error.

Classify thread authors from the data: a login ending in `[bot]`, or `Copilot`, `coderabbitai`, `sonarcloud`,
`codecov` and similar, is a bot; everyone else is human. Audit both.

If the PR has no reviews and no threads yet, say so: there is no previous round to audit. Continue with the gap
sweep over the whole diff, and recommend `pr-review` in the report.

**Fix commits.** The commits pushed after each review's `submittedAt` are the fixes, and they are what Step 3
reviews. With a local checkout: `git fetch origin <headRefName>` and `git diff <last-sha-before-review>..<headRefOid>`.
Without one, use `gh api "repos/<owner>/<repo>/compare/<last-sha-before-review>...<headRefOid>"` and contents
reads at the head SHA instead of fetching into an unrelated working tree.

## Step 1a — Fresh review at head

Readiness is not only a comment-resolution audit.

- Scope: `merge-base(baseRefOid, headRefOid)..headRefOid`, remotely the current `gh pr diff`, locally
  `git diff <merge-base>..<head>` when there is a local checkout.
- Never include unrelated local files, switch branches or edit the working tree.
- Pin every conclusion to the head SHA. If it changes during the audit, refresh the diff, threads, CI and the
  affected files before deciding.
- Review both the full PR diff and the fix delta since the previous review. The delta finds regressions; the
  full diff finds interactions and original gaps.
- Raise only defects the PR introduces or materially worsens.

## Step 1b — Conventions

At the repository root, read whichever exist: `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `.cursor/rules/`,
`CONTRIBUTING.md`, `.github/copilot-instructions.md`, and `.agents/pr-conventions.md` or
`.claude/pr-conventions.md` (which wins for review-specific rules: severity, tags, extra checks, deployment and
migration rules, language). For every changed file, also read the nearest context file up its directory chain.
Find candidates by listing files; never guess a path. Detect the stack from the repository's manifests and CI
workflows. A rule the repository does not document is not a convention finding.

## Step 2 — Audit every thread on the code

Follow `references/thread-audit.md`: read the code at head for every thread, resolved or not, and give each one
of the six states with evidence.

## Step 3 — Sweep for gaps the fixes introduced

The fix commits are new code nobody reviewed. Review them:

- Did a fix break something else? Read the callers of anything whose signature or behavior changed.
- Was a fix applied in one branch of the code but not the parallel one (the sibling module, the other handler,
  the retry path)?
- Tests: does every fixed bug have a test that would have caught it? Do new tests follow the repository's
  documented test conventions?
- Contracts: a config value added but missing from the example config or the deployment manifests; a changed
  message key or payload without the consumer updated; a migration that is not backward compatible. Check how
  this repository applies migrations (on boot, in CI, by hand); if by hand, a PR that needs one must say so.
- Repository conventions from Step 1b, only the ones actually documented.
- If the PR is linked to a tracker task and the session has a tool for it, check every acceptance criterion,
  not only the review comments.
- CI: any failing or pending check is a blocker until it is green or explained.
- `--focus`, if given.

Apply `references/quality-gate.md` to every new gap: verify it, assign `P0`–`P3`, keep only what the PR
introduces, anchor it minimally, sort P0 → P3. P0/P1 block readiness; P2 blocks when merging is unsafe; P3
never blocks unless a documented repository rule says so.

## Step 4 — Audit table

Print the tables of `references/thread-audit.md`, then the CI status and the counts.

## Step 5 — Verdict

**READY** requires all of these:

- zero threads in a pending state (`PARTIAL`, `NOT_ADDRESSED`, `DISMISSED_WITHOUT_BASIS`, `UNANSWERED`);
- zero new blocker-level gaps;
- CI green, or a failure the user explicitly accepted in this conversation.

Open suggestions do not block; list them as optional follow-ups. Otherwise the verdict is **NOT_READY**. State
it plainly; do not soften NOT_READY into a maybe.

### READY

Post nothing. Write the approval comment from `references/comment-templates.md`, in the review language, as a
single copy-paste block, and put it in the report too. `posted` is `false`. Go to Step 6.

### NOT_READY

Build the review of pending items and new gaps:

- Comments for unaddressed threads are **replies in the existing thread** (the template "still open from the
  previous round"); new gaps are inline comments in one review. Templates: `references/comment-templates.md`.
- Event: `REQUEST_CHANGES` if any blocker remains, otherwise `COMMENT`; `COMMENT` if the author is `<me>`.
- Preview: the audit tables, the event, the body verbatim, and under `--dry-run` every reply and inline comment
  verbatim with its target (thread or `path:line`), plus "Dry run: nothing was posted." (in the review language)

Then:

- `--dry-run`: print the preview and go to Step 6. Do not ask anything.
- `--auto`: post.
- Otherwise: ask the user to confirm and wait; apply any edits; if they decline, go to Step 6 with `posted`
  `false`. If you cannot ask, follow "No one to ask".

Posting follows `references/posting.md`: one review in one call with a temporary payload file and `commit_id`,
the line-anchoring and 422 rules, and one reply call per unaddressed thread.

## Step 6 — Report

1. Write the report file described in `references/contract.md`. With READY it includes the approval comment.
2. Tell the user, in the review language: the verdict, the counts (addressed, pending, new gaps), the review URL
   if something was posted, the CI status and the report path. With READY, remind them that the approval is
   theirs to post from the UI. Offer to move a linked tracker task; do not change it unasked.
3. If nothing is pending and there are no new gaps, say so plainly and list any residual risk (tests that could
   not run, a pending external check). Never invent a low-value finding to fill the audit.
4. End the message with the JSON line of `references/contract.md` (`skill` `pr-ready`, `verdict` `READY` or
   `NOT_READY`, `pending` = threads in a pending state, `findings` = new gaps). Nothing after it.

## Issue and PR conventions

If this run opens an issue for a deferred finding, follow the conventions found in Step 1b. If the repository
documents none, imitate its recent issues (`gh issue list`) instead of inventing a format.
