# Fixing, pushing and replying

Used by `pr-fix`, Steps 4, 7 and 8. Not read under `--dry-run`: nothing here runs without edits.

## Worktree

Every edit happens in a dedicated git worktree, never in the user's checkout, so a dirty working tree, another
branch or a parallel batch agent is never affected.

1. **Path.** `<worktrees>/<owner>-<repo>-pr-<n>`, where `<worktrees>` is the environment variable
   `AGENT_SKILLS_WORKTREES` if set and not empty, else `~/.agent-skills/worktrees` (resolve with `printenv`, as
   the report directory). `mkdir -p <worktrees>`. Use the absolute path everywhere.
2. The head is already fetched (Step 0 of the skill), with no ref updated.
3. **A worktree from an earlier run** at that path (`git -C <root> worktree list --porcelain`): remove it with
   `git -C <root> worktree remove <wt>` only if `git -C <wt> status --porcelain` is empty and
   `git -C <wt> log --oneline <headRefOid>..HEAD` is empty (no work of its own). Otherwise stop with `ERROR`:
   "<wt> holds unpushed work from an earlier run; push or remove it first". A path that exists but is not a
   worktree is the same error. Never delete someone's work to make room.
4. **Create it detached at the head:** `git -C <root> worktree add --detach <wt> <headRefOid>`. Detached, so no
   local branch name can collide; the push names the remote branch explicitly.
5. **Dependencies**, only when the checks need them and they are missing: the lockfile-frozen install of the
   detected tool inside the worktree (`npm ci`, `pnpm install --frozen-lockfile`, `yarn install --immutable`,
   `bun install --frozen-lockfile`, `uv sync --frozen`, `poetry install --no-root`, `dotnet restore`,
   `go mod download`, `bundle install`). Never update a lockfile. If installing fails or needs secrets or
   services you do not have, the checks that depend on it are "not run" and go to residual risk.

## Fix loop

Record `<original head>` = `<headRefOid>`. For each `FIX` item or group, in the order of `triage.md`:

1. Note `<before>` = `git -C <wt> rev-parse HEAD`.
2. Re-read the code at the worktree and the project sources from `project-context.md` that apply to these files.
3. **Make the smallest change that fully resolves the item**, in the project's style:
   - Apply it everywhere it applies: other call sites, the sibling handler, the parallel code path, the
     example config and deployment manifests for a new setting, the generated client after a schema change (by
     regenerating, not by hand).
   - If the item is a defect, add or adjust a test that fails without the fix, in the place and style the
     project uses for that area. When it is cheap, run it once before the fix to see it fail.
   - No unrelated edits: no renames, reordering, reformatting or "while I'm here" cleanups. Run the project's
     formatter on the files you changed only if it changes nothing beyond your own lines.
4. **Targeted checks**: the narrowest command that exercises the change (the affected test file, the linter
   and type-checker on the changed files or package).
5. **Review the item's diff** (`git -C <wt> diff`): every hunk traces to this item; no debug output, commented
   code, secrets, or edits to generated files by hand.
6. **Commit**:
   - `git -C <wt> add -- <each changed path>`. Never `add -A` or `add .`: build output and installed
     dependencies must never be committed.
   - Message in the repository's convention (`project-context.md` §3). The subject says what changed in the
     code ("validate tenant id before lookup"), not "address review". The body links the item: the thread URL
     `https://github.com/<owner>/<repo>/pull/<n>#discussion_r<first comment databaseId>`, or the check name.
   - **No AI attribution.** No `Co-Authored-By`, `Generated with`, `Assisted-by`, `Signed-off-by` for a tool, or
     any mention of an AI, agent, assistant or model (Claude, Copilot, Codex, Gemini, Cursor or any other), in
     the subject or the body. Harnesses add these by default; that default does not apply here. A
     `Co-Authored-By` for a real person is kept only if the repository's convention asks for it.
   - Write the message to a temporary file from `mktemp` and run `git -C <wt> commit -F <file>`; delete the
     file. Hooks run; if one fails, treat it as a failing check of this item. Never `--no-verify`.
   - Check the result with `git -C <wt> log -1 --format=%B`: a hook (`prepare-commit-msg`, `commit-msg`) or the
     harness may have appended a trailer. If an AI attribution appears, rewrite the message with
     `git -C <wt> commit --amend -F <file>` (allowed: the commit is not pushed yet). Before pushing, run
     `git -C <wt> log --format=%B <original head>..HEAD` once and confirm no commit carries one.
7. **Cannot fix it cleanly** (the checks still fail after two honest attempts, or the fix turns out to need a
   person or a change outside the PR's scope): `git -C <wt> reset --hard <before>`, which only discards this
   item's own unpushed work, and mark it `FAILED` with the reason, or turn it into `ASK` (`PENDING` with a
   proposal). Never leave a half-applied fix.

## Full checks

Unless `--no-checks`, after the last item run the checks that gate merging (from the CI workflows and the
project's scripts): lint, type-check, build and tests, scoped to the affected packages when the tool supports it.
Skip what needs secrets, external services or a deployment, and list it as not run.

If a check fails:

1. Note `<fixed head>` = `git -C <wt> rev-parse HEAD`, run `git -C <wt> switch --detach <original head>`, run
   that check again, and `git -C <wt> switch --detach <fixed head>`.
2. It also fails at `<original head>`: pre-existing, not caused by the fixes. Record it; it is not yours to fix
   unless it was itself a `ci` item.
3. It passes there: one of your commits broke it. Find which (the check's output usually names the file), fix it
   under that item, or reset that item away (`git -C <wt> revert --no-edit <sha>` if later commits depend on the
   same lines, otherwise reset it as in the fix loop) and mark it `FAILED`.

## Large PRs

When there are more than about eight `FIX` groups, or they span unrelated areas (for example frontend and backend
and a migration), and the harness can launch fresh agents, keep this session as the orchestrator: launch one
fresh agent per group (not a fork of this conversation), **one at a time**, because they share the worktree. Give
each exactly this prompt, filled in:

```text
You are fixing review feedback on <owner>/<repo>#<n> inside the git worktree <wt> (detached HEAD). Work only in
that directory, and run git as `git -C <wt> …`.
Items:
- [<id>] <path:line> — <what is asked, quoted from the comment> — <agreed approach, if any>
Read these project conventions first and follow them: <applied source paths for these files>
Commit message convention: <convention, with one recent example subject>
Follow these rules exactly: <the "Fix loop" section of this file, steps 1–7, verbatim>
Never push, never use --no-verify, never edit outside <wt>, never touch an item not listed above.
Never add a Co-Authored-By, Generated-with or any other AI or tool attribution to a commit message.
Nobody can answer questions in this session. If an item needs a decision, do not guess: reset it and report it.
Your final message must end with one line of JSON and nothing after it:
{"group":"<gid>","items":[{"id":"<id>","outcome":"FIXED|FAILED|ASK","commit":"<short sha or null>","note":"<= 25 words"}],"summary":"<= 40 words"}
```

Keep only each agent's last line. If it is missing or does not parse, treat its items as `FAILED` and reset the
worktree to the commit before that agent started. This session then runs the full checks, the self-review
(Step 5), the preview, the push and the replies itself.

## Push

1. The remote branch must still be where you started:
   `git -C <root> ls-remote <push target> refs/heads/<headRefName>` must print `<original head>`.
2. If it moved, someone pushed during the run. Push nothing, keep the worktree, set `pushed` `false`, and say
   in the report and `summary` that the branch moved and `pr-fix` should run again on the new head.
3. Otherwise: `git -C <wt> push <push target> HEAD:refs/heads/<headRefName>`. A plain push only: a
   non-fast-forward rejection, a protected branch or a failing server hook is recorded as is, never retried
   with force.
4. On success, `<new head>` = `git -C <wt> rev-parse HEAD`.

## Replies

Only after a successful push (or when there was nothing to push), so every SHA in a reply exists on the
remote. Templates: `reply-templates.md`.

- One reply per handled thread (`FIXED`, `ALREADY_DONE`, `ANSWERED`), in the existing thread:
  `gh api "repos/<owner>/<repo>/pulls/<n>/comments/<comment-id>/replies" --method POST --input <file>` with
  `{"body":"…"}` in a temporary file from `mktemp`, written with the write-file capability, deleted after.
  `<comment-id>` is the `databaseId` of the thread's first comment.
- Items without a thread (review bodies, PR comments, CI): one PR comment for all of them,
  `gh pr comment <n> --repo <owner>/<repo> --body-file <file>`.
- Nothing for `IGNORED`, `PENDING` or `FAILED` items: a `PENDING` item waits for its owner's answer, and a
  `FAILED` one is in the report.
- **Never resolve a thread**, not even one you fixed.
- A reply that fails is recorded in the report; the others still go out. Never retry in a loop.

## Cleanup

After a successful push (and the replies), `git -C <root> worktree remove <wt>`. If the run did not push
(`--no-push`, declined, nobody confirmed, branch moved, push rejected), keep the worktree and give its path in
the report and the JSON line, so the user can inspect or push it themselves.
