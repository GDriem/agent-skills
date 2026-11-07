# Triage

Used by `pr-fix`, Step 2. Every piece of feedback becomes one item with a class, a priority and evidence before
anything is edited. A comment is a claim to verify, not an order: reviewers and bots are wrong sometimes, and
fixing a non-problem adds risk for nothing.

## 1. Collect

Run these in parallel:

```bash
gh api graphql -f owner=<owner> -f repo=<repo> -F number=<n> -f query='
query($owner:String!,$repo:String!,$number:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      headRefOid
      reviews(last:50){ nodes{ databaseId author{login} state submittedAt body } }
      reviewThreads(first:100){
        nodes{
          id isResolved isOutdated path line startLine diffSide
          comments(first:50){ nodes{ databaseId author{login} body createdAt } }
        }
      }
    }
  }
}'
gh api "repos/<owner>/<repo>/issues/<n>/comments" --paginate --jq '.[] | {id, user: .user.login, created_at, body}'
gh pr checks <n> --repo <owner>/<repo>
```

`gh pr checks` exits non-zero when a check fails or is pending; that is data. For each failing check that runs
on GitHub Actions, get the failure with `gh run view <run-id> --repo <owner>/<repo> --log-failed`, and keep only
the relevant lines (the first error and its location), not the whole log. A pending check is not an item.

Sources of items:

| Source | Becomes items when |
|---|---|
| Review thread, **unresolved** | always: one item per thread, from the whole conversation, not only the first comment |
| Review thread, resolved | never, except when the last comment is a reviewer saying it is still open (a `pr-ready` reply such as "still open from the previous round") posted after the author's last action |
| Review body | it lists actionable points without a thread (for example "findings with no line in the diff", "still open") from a review that is the latest of its author |
| PR conversation comment | a reviewer or bot asks for a concrete change and nobody answered it afterwards |
| Failing check | it fails at the current head: one item per distinct failure |

Classify authors from the data: a login ending in `[bot]`, or `Copilot`, `coderabbitai`, `sonarcloud`, `codecov`
and similar, is a bot; everyone else is human. `<me>`'s own comments are context, never items.

Read the thread to its end. A later reply can narrow, change or withdraw the request; the author may already have
answered with a reason. The item is what is being asked **now**.

## 2. Verify against the code at head

For each item, read the code it is about at the PR head (it may have moved: follow the symbol, not the old line
number) and its immediate collaborators, then decide whether the claim holds. Use `quality-gate.md`'s method:
try to disprove it, and write down for yourself the concrete input or state and the wrong outcome. A GitHub
`suggestion` block is a proposal, not proof: check it compiles in context, handles the same cases, and matches the
conventions before applying it.

## 3. Classify

| Class | When | What happens |
|---|---|---|
| `FIX` | the claim holds, the change belongs in this PR, and there is one clearly right way to do it under the project's conventions | fixed in Step 4 |
| `ALREADY_DONE` | the code at head already does what is asked (fixed in a later commit, or the comment misread the code) | a reply with the evidence, no edit |
| `ASK` | it needs a person (subtypes below) | asked in Step 3, or `PENDING` with a proposal |
| `IGNORE` | no action requested (praise, an FYI, a question already answered), a bot finding a human already called wrong, a duplicate of another item, or out of `--only` | nothing, not even a reply |

`ASK` subtypes:

- **decision**: tagged `[DECISION]`, or a real trade-off with more than one reasonable answer (behaviour, UX,
  naming of a public API, performance against simplicity).
- **pushback**: you are confident the comment is wrong or does not apply. Propose the reply that explains why,
  with evidence. Never silently skip a comment because you disagree.
- **conflict**: the request contradicts a documented project rule, or another reviewer's comment.
- **scope**: valid, but the fix belongs elsewhere: a large refactor, another module's ownership, a change of
  public contract, schema or dependency. Propose a follow-up issue or a separate PR.
- **unclear**: you cannot tell what is being asked. Propose your best reading as one of the options.

When in doubt between `FIX` and `ASK`, choose `ASK`. A wrong question costs one answer; a wrong fix costs a
review round.

## 4. Priority and order

- A tag in the comment (`[BLOQUEANTE]`/`[BLOCKER]`, `[SUGERENCIA]`/`[SUGGESTION]`, `[DECISION]`, or the
  repository's own tags from its `pr-conventions`) gives the kind. Without one, assign `P0`–`P3` with
  `quality-gate.md` and map it to a kind.
- A failing check is a blocker.
- `--only` keeps the kinds listed: `blocker`, `suggestion`, `decision` (all `ASK` items), `comment` (items from
  PR comments and review bodies), `ci` (failing checks). Items outside it are `IGNORE` with the reason "out of
  --only".
- Order the `FIX` items: CI failures first (they may hide other problems), then blockers P0 → P2, then
  suggestions. Items touching the same lines or the same function form one group and get one commit.

## 5. Triage table

Print it before asking or editing anything, in the review language:

```
## Triage

| # | Source | Author | file:line | Kind | Priority | Class | Why / evidence |
```

`Source` is `thread`, `review`, `comment` or `ci`. Then the counts per class. The same table, with an
`Outcome` column added, is the core of the preview and of the report.
