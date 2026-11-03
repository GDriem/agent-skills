# Quality gate

Shared by `pr-review` (every finding) and `pr-ready` (every new gap). A candidate that fails any rule is fixed,
downgraded, or dropped. It never reaches the preview as is.

## Verify first

For each candidate, argue the opposite and try to disprove it. Write down, for yourself, the concrete input or
state and the wrong output, crash or corrupted record it leads to. If you cannot write that failure path, the
candidate becomes a suggestion or is dropped. Re-read the exact lines once more before keeping it: most false
positives come from context you did not open.

Drop anything that only reads as "this could be cleaner" with no defect and no measurable benefit.

## Rules

- **Prioritized.** Assign an internal priority before the repo-facing tag:
  - `P0` catastrophic or global (data loss, outage, security hole open to anyone)
  - `P1` urgent, likely to break production or a core workflow
  - `P2` normal, actionable defect
  - `P3` low impact, concrete improvement

  Sort P0 → P3. Do not raise a priority because the fix is easy.
- **Introduced here.** Point to the changed behavior that caused or exposed the issue. If the PR did not
  introduce it, or did not materially worsen it or make it newly reachable, drop it.
- **Actionable.** One discrete problem per finding: the triggering input or state, the observable impact, and a
  concrete correction. Split unrelated problems.
- **Evidence-backed.** Confirm the claim against the full file and its callers, tests, contracts or docs. Never
  infer a bug from a symbol name or a diff fragment alone.
- **High confidence.** If a reasonable repository-specific assumption would make the code correct, check that
  assumption first. If it stays genuinely undecidable, make it a decision item; do not present uncertainty as a
  defect.
- **Minimal location.** Anchor to the smallest useful changed-line range, normally one to five lines, never a
  whole function when fewer lines identify the cause. The range must overlap the PR diff (see `posting.md`).
- **No noise.** Formatter, linter and type-checker output belongs to CI unless it reveals a behavioral defect.
  Do not restate the diff or praise the implementation inside a finding.

## Priority → tag

Keep the repository's own tag names when its conventions define them (see the skill's conventions step).
Otherwise use the review language:

| Kind | Spanish | English | Effect on the review event |
|---|---|---|---|
| blocker | `[BLOQUEANTE]` | `[BLOCKER]` | forces `REQUEST_CHANGES` |
| suggestion | `[SUGERENCIA]` | `[SUGGESTION]` | `COMMENT` |
| decision | `[DECISION]` | `[DECISION]` | `COMMENT`; the author must answer in the thread |

- `P0` and `P1` are blockers.
- `P2` is a blocker when merging it is unsafe, otherwise a suggestion.
- `P3` is a suggestion, and only when the benefit is concrete and measurable. In `pr-ready` it never blocks
  readiness unless a documented repository rule says so.
- Decisions stay decisions until answered, whatever their priority.

Keep the priority in the preview and the report even when the comments use only the repository's tags.
