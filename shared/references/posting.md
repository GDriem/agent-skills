# Posting to GitHub

Shared by `pr-review` and `pr-ready`. Read this only when you are about to write to GitHub. With `--dry-run`,
nothing in this file runs: build the same payload, show it, put it in the report, and stop.

## One review, one call

Post all inline comments as one review in one API call, never as N separate comments: the author gets one
notification and one coherent review.

Write the payload to a **uniquely named temporary file** and pass that file with `--input`. Never embed the JSON
in the command line: quoting breaks on the first backtick, quote or newline in a comment.

- Get the unique name from the system: `mktemp` in a POSIX shell, `[System.IO.Path]::GetTempFileName()` in
  PowerShell.
- Write the content with the harness's write-file capability, as UTF-8. Only if there is none, use a quoted
  heredoc (`<<'EOF'`) in a POSIX shell so nothing inside is expanded.
- Delete the file after the call (`rm <payload-file>`).

```bash
gh api "repos/<owner>/<repo>/pulls/<n>/reviews" --method POST --input "<payload-file>"
```

```json
{
  "commit_id": "<full head SHA that was reviewed>",
  "body": "<review body in markdown>",
  "event": "REQUEST_CHANGES",
  "comments": [
    { "path": "src/orders/service.ts", "line": 142, "side": "RIGHT", "body": "..." },
    { "path": "src/orders/service.ts", "start_line": 88, "line": 94, "side": "RIGHT", "body": "..." }
  ]
}
```

`commit_id` pins the comments to the head you actually read. Right before posting, read the PR's current head
SHA again; if it moved, the PR changed under you: refresh the diff and the affected findings first, and use the
new SHA.

The response's `html_url` is the `review_url` of the result contract.

## Event

- `REQUEST_CHANGES` if at least one blocker remains, otherwise `COMMENT`.
- If the PR author is the current user, always `COMMENT` (GitHub rejects `REQUEST_CHANGES` and `APPROVE` on your
  own PR) and say so in the report.
- Never `APPROVE`, in any skill, in any mode.

## Line anchoring (a mistake here returns 422)

- `path` exactly as GitHub reports it: repository-relative, forward slashes, on every OS.
- `line` must be a line present in the PR diff. Parse the `@@ -a,b +c,d @@` hunk headers of `gh pr diff` to
  know which right-side line numbers are valid.
- `side: "RIGHT"` for added and context lines; `"LEFT"` only to comment a deleted line.
- A range uses `start_line` + `line`, both inside the same hunk.
- A finding with no line in the diff (a missing file, a whole-file concern, a missing test) goes in the review
  body under the "findings with no line in the diff" section, never on a guessed line number.
- If the call still returns 422, do not retry blindly: move the offending comment to that body section, post
  again once, and record what moved in the report.

## Replying in an existing thread (`pr-ready`)

When the item is an earlier thread that was not addressed, reply in that thread instead of opening a new one,
so the history stays in one place:

```bash
gh api "repos/<owner>/<repo>/pulls/<n>/comments/<comment-id>/replies" --method POST --input "<reply-file>"
```

with `{"body":"..."}` in a temporary file, as above. `<comment-id>` is the numeric REST id of the first comment
of the thread (`databaseId` in GraphQL).

## Body and comment text

- Plain and direct, in the review language. Short sentences. No emojis. No hedging.
- Never sign, never mention an AI, an agent, an assistant, a model or any tool by name. No `Co-Authored-By`. The
  text reads as the team's review.
- Say what to do, not only what is wrong.
- Templates: `comment-templates.md`.
