---
name: pr-review
description: First-pass review of a GitHub pull request. Reads the diff and the surrounding code, verifies each finding, deduplicates against bot reviewers, and posts one review with inline comments tagged blocker, suggestion or decision. Never approves. Supports --dry-run, --auto, --lang and --focus. Use when asked to review a PR.
---

# pr-review

Review one pull request and post the findings as a single GitHub review with inline comments, taking any
existing bot review (Copilot, CodeRabbit, Sonar and similar) into account.

**Arguments.** The arguments are the text that follows the skill name in the message that invoked this skill.
Some harnesses substitute them here: `$ARGUMENTS`. If that still reads as a literal placeholder, use the text
after the skill name instead.

| Argument | Meaning |
|---|---|
| `401` | PR 401 of the repository in the current directory |
| `owner/repo#401` or a full PR URL | that PR, whatever the current directory is |
| (empty) | the PR of the current branch |
| `--auto` | skip the confirmation before posting. Nothing else changes |
| `--dry-run` | do everything except write to GitHub; print the full preview; ask nothing |
| `--lang=en\|es\|…` | force the review language |
| `--focus="<criteria>"` | extra review criteria for this run; never turns the general review off |
| `--run-dir=<path>` | where to write the report; set by batch runners (see `references/contract.md`) |

This skill is repository-agnostic. The repository, the current user and the review conventions are detected
when it runs; nothing about a specific project is written here.

**Hard rules, in every mode:**

- Never approve a PR and never post an `APPROVE` event.
- Never write to GitHub under `--dry-run`. Without `--auto`, never write before the user confirms.
- `--auto` removes the confirmation pause only. It does not relax verification, anchoring, or "one review per
  PR".
- Never check out a branch, edit, stage or commit anything in the working tree.
- Every run ends with the report file and the final JSON line of `references/contract.md`, including runs that
  stop early.

## Capabilities this skill relies on

The skill names capabilities, not tools. Use whatever the current harness provides for each:

- **Run shell commands** (`git`, `gh`, `jq`). Required.
- **Read files** and **search files by name**. If there is no dedicated file search, `git ls-files` works.
- **Write a file** (the temporary payload, the report).
- **Ask the user and wait for the answer.** If the harness cannot ask, or no person is in the loop, behave as
  described under "No one to ask" below.

**Shell commands: one simple command per call.** No `;`, `&&`, `||`, `for` loops, `cd … &&` or heredocs that
chain several commands, and no `$(…)` around a command that is not itself `gh`, `git`, `jq`, `date` or
`mkdir`. Pipes into `jq` are fine. Harnesses pre-approve commands by prefix (`gh`, `git`), and a compound
command usually falls outside the rule and is denied when no one can approve it. Run independent commands as
separate parallel calls instead.

## No one to ask

If you cannot ask the user (headless run, batch agent, or the harness has no way to wait for an answer):

- `--dry-run`: nothing changes, it never asks anyway.
- Draft PR: stop with `verdict` `SKIPPED` and `error` "draft".
- Confirmation before posting without `--auto`: do not post. Write the report, `posted` `false`, and say in
  `summary` that it was not posted because nobody confirmed.

## Step 0 — Resolve the context

Never assume a repository.

1. Parse the arguments.
   - A full URL or `owner/repo#N` gives `<owner>/<repo>` and `<n>`.
   - A bare number uses the repository of the current directory:
     `gh repo view --json nameWithOwner -q .nameWithOwner`.
   - Empty: `gh pr view --json number,url` for the current branch. If there is no PR, stop with `ERROR`.
2. Current user: `gh api user -q .login` → `<me>`.
3. Local checkout (optional): `git rev-parse --show-toplevel` → `<root>`, used only if the current
   directory's remote is `<owner>/<repo>`. If either command fails, or the remote is another repository, that
   is **not** an error: there is just no local checkout, and you read everything through `gh` (see "Reading
   code at head" in Step 2).
4. Only a failure that leaves `<owner>/<repo>`, `<n>` or `<me>` unknown stops the run: a bare number or empty
   argument with no usable remote, `gh` not authenticated, PR not found. Then stop with `ERROR`, name the
   command that failed, and still do Step 9 (report file and final JSON line). Do not guess.
5. PR state: if it is closed or merged, stop with `SKIPPED`. If it is a draft: under `--dry-run`, continue and
   note it in the report; otherwise ask whether to continue (or follow "No one to ask").
6. If the author is `<me>`, the event will be `COMMENT` (GitHub rejects `REQUEST_CHANGES` on your own PR).

**Language.** `--lang` if given. Otherwise the language of the human review comments already on this PR and on
the repository's recent PRs, falling back to the language of the repository's root context file. Use one
language for every comment, the body, the report and the `summary`.

**Focus.** Keep the `--focus` text verbatim. Apply it after the six categories of Step 3. It narrows attention;
it never hides an obvious blocker elsewhere.

## Step 1 — Gather everything before forming an opinion

Run these in parallel when the harness allows it:

```bash
gh pr view <n> --repo <owner>/<repo> --json number,title,body,author,isDraft,state,baseRefName,headRefName,additions,deletions,changedFiles,labels,url
gh pr diff <n> --repo <owner>/<repo>
gh pr view <n> --repo <owner>/<repo> --json files -q '.files[] | "\(.path) +\(.additions) -\(.deletions)"'
gh pr checks <n> --repo <owner>/<repo>
gh api "repos/<owner>/<repo>/pulls/<n>/commits" --paginate --jq '.[] | "\(.sha[0:8]) \(.commit.message | split("\n")[0])"'
gh api "repos/<owner>/<repo>/pulls/<n>" --jq '{baseSha: .base.sha, headSha: .head.sha}'
```

`gh pr checks` exits non-zero when a check fails or is pending; that is data, not an error.

Existing review state, which keeps you from repeating a bot:

```bash
gh api graphql -f owner=<owner> -f repo=<repo> -F number=<n> -f query='
query($owner:String!,$repo:String!,$number:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      reviewDecision
      reviewThreads(first:100){
        nodes{
          isResolved isOutdated path line
          comments(first:20){ nodes{ author{login} body createdAt } }
        }
      }
    }
  }
}'
```

Classify thread authors from the data, never from a fixed list of people:

- **Bots**: login ends in `[bot]`, or is `Copilot`, `coderabbitai`, `sonarcloud`, `codecov` or similar.
  You deduplicate against these in Step 5.
- **Humans**: everyone else. Their comments are authoritative context; never re-open a point a maintainer
  already settled in a thread.

## Step 1a — Scope: merge base to head

Review the PR as a branch against its merge base, not as arbitrary local changes.

- The scope is the change from the merge base with the base branch to the current head SHA. `gh pr diff` is
  its remote form.
- With a local checkout and when you need more history, fetch without checking out
  (`git fetch origin <baseRefName> pull/<n>/head`), compute `git merge-base <baseSha> <headSha>`, and use
  `git diff <merge-base>..<headSha>`. Never include unrelated staged, unstaged or untracked files.
- Review the head SHA you recorded. If it changes during the review, refresh the diff and the affected context
  before posting.
- Report only defects this PR introduces, or pre-existing ones it materially worsens or makes newly reachable.
  A PR review is not an inventory of legacy problems.
- Keep the PR, base branch, head SHA, changed files and criteria in your working notes so the scope does not
  drift.

## Step 1b — Conventions the findings are judged against

Discover them; do not assume them. At the repository root, read whichever of these exist:

- `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`
- `.cursor/rules/` (every rule file)
- `CONTRIBUTING.md`, `.github/copilot-instructions.md`
- `.agents/pr-conventions.md` or `.claude/pr-conventions.md`: if present, it wins over the others for
  review-specific rules (severity policy, extra checks, tag names, title and issue conventions, review language)

For every changed file, also read the nearest context file up its directory chain (`AGENTS.md`, `CLAUDE.md`,
`GEMINI.md`, or a context file under a `.github/` or `.claude/` folder at that level), up to the root. Find
candidates by listing files (file search, `git ls-files`, or the tree at head through `gh`); never guess a path.

Detect the stack from the repository itself (`package.json`, `pyproject.toml`, `go.mod`, `*.csproj`,
`Cargo.toml`, lockfiles, CI workflows) so comments match the tooling actually in use.

If the PR title or branch references an issue tracker and the session has a tool for that tracker, read the
task and treat its acceptance criteria as part of the scope. If there is no such tool, skip this silently.

## Step 2 — Read the code, not only the diff

A diff hides the bugs that matter. For every non-trivial changed file, read the whole file at head and its
immediate collaborators: the caller, the entity or schema, the data-access method, the consumer of the event or
message, the existing test file. Check specifically:

- Every caller of a changed signature (search for the symbol): were all call sites updated?
- Whether a similar helper already exists in the same module (duplicated logic is a real finding).
- The test file next to the change: does the new branch have coverage?

**Reading code at head.** With a local checkout, `git show <headSha>:<path>` after fetching (no checkout).
Without one, `gh api "repos/<owner>/<repo>/contents/<path>?ref=<headSha>" -H "Accept: application/vnd.github.raw"`,
and `gh api "repos/<owner>/<repo>/git/trees/<headSha>?recursive=1" --jq '.tree[].path'` to list files. Find
callers with `gh search code "<symbol>" --repo <owner>/<repo>` (it searches the default branch, not the PR head)
or by reading the likely files, and say in the report when a search could not be exhaustive.

## Step 3 — Find real problems, in this order

1. **Correctness**: wrong logic, off-by-one, inverted condition, unhandled null or error return, missing
   `await`, promise not returned, unreachable branch, resource never closed.
2. **Data integrity**: money and rounding, dates and time zones, a destructive write where the repository's
   convention is soft or append-only, several writes without a transaction, a non-idempotent handler on a queue
   or webhook that redelivers.
3. **Security and auth**: missing or misapplied guard, permission or scope not enforced, fail-open auth, tenant
   or account scope leak, secret in logs, injection, unvalidated input reaching a query, path traversal.
4. **Contract breaks**: changed response shape, changed message key or payload without the consumer updated,
   a migration that is not backward compatible, a config value read but missing from the example config and
   the deployment manifests.
5. **Repository conventions**: only what the files from Step 1b state. Cite the file when you raise one. If the
   repository documents no rule on a point, it is not a convention finding.
6. **Reuse and simplification**: duplicated logic, dead code, needless complexity, N+1 queries, a loop of
   awaits that should be batched.

Then apply `--focus`, if given.

Do not comment on formatting an auto-formatter handles, personal naming taste, "add a comment here", speculative
future requirements, or anything without a concrete failure behind it.

## Step 4 — Verify every finding

Apply `references/quality-gate.md` to every candidate: verify it by trying to disprove it, assign `P0`–`P3`,
keep only what this PR introduces or worsens, anchor it to the minimal changed-line range, and map priority to
a tag. Sort P0 → P3.

## Step 5 — Deduplicate against bots and classify

- A bot already raised it and it is correct: do not repeat it. List it in the body under "already covered" so
  the author knows it still counts.
- A bot raised it and it is wrong or misleading: post a comment saying so, so the author does not waste time.
- Ignore threads that are `isOutdated` and already fixed at head.

Tags and their effect on the event: `references/quality-gate.md` ("Priority → tag").

## Step 6 — Write the comments

Use `references/comment-templates.md`, in the review language. No emojis, no signature, never mention an AI, an
agent or any tool. Say what to do, not only what is wrong. Add a `suggestion` block when the fix is a concrete
edit on the commented lines.

## Step 7 — Preview

Always build the preview:

- A findings table sorted by priority: `# | Priority | Tag | file:line | Finding (one line)`.
- The event (`REQUEST_CHANGES` or `COMMENT`) and why.
- The review body verbatim.
- Under `--dry-run`, also every inline comment verbatim with its `path:line` (or `start_line-line`), exactly
  as it would be posted, and the line "Dry run: nothing was posted." (in the review language)

Then:

- `--dry-run`: print the preview and go to Step 9. Do not ask anything, and do not read `references/posting.md`:
  nothing is posted.
- `--auto`: print the preview and go to Step 8.
- Otherwise: print the preview, ask the user to confirm, and wait. If they drop or reword findings, apply it and
  show the table again. If they decline, go to Step 9 with `posted` `false`. If you cannot ask, follow
  "No one to ask".

If no finding survived, say so plainly in the preview, list any residual risk (tests not runnable, a pending
external check, a search that could not be exhaustive), and do not invent a suggestion to fill the review. With
no findings, do not post an empty review: go to Step 9 with `verdict` `COMMENT` and `posted` `false`.

## Step 8 — Post one review

Follow `references/posting.md`: one call, payload in a unique temporary file, `commit_id` = the reviewed head,
the line-anchoring rules, 422 handling, and the event rule.

## Step 9 — Report

1. Write the report file described in `references/contract.md`.
2. Tell the user, briefly and in the review language: the review URL (or that nothing was posted and why),
   counts per tag, the event, anything that failed to post, the CI status, and the report path. If the PR is
   linked to a tracker task and there are blockers, offer to move its status; do not change it unasked.
3. End the message with the JSON line of `references/contract.md`. Nothing after it.

## Issue and PR conventions

If this run opens an issue or a PR, follow the conventions found in Step 1b (and the templates under
`.github/ISSUE_TEMPLATE/`). If the repository documents none, imitate its recent issues and PRs
(`gh issue list`, `gh pr list`) instead of inventing a format.
