# Adapter: claude-code

How the neutral skills in `skills/` run in the Anthropic CLI (`claude`). Verified with 2.1.309 on 2026-11-02;
what was tested in this repo is marked **probado**, the rest comes from the docs cited in
[docs/harness-matrix.md](../docs/harness-matrix.md).

## Install

| Scope | Path |
|---|---|
| User | `~/.claude/skills/<name>` → symlink to `skills/<name>` |
| Project | `<repo>/.claude/skills/<name>` |

- `~/.agents/skills` is **not** read (**probado**: a skill there answered "not installed"; the same skill under
  `.claude/skills` ran). This harness needs its own destination.
- A skill wins over a command with the same name in `~/.claude/commands`, so the skill can be installed before
  the old command is removed (documented).
- No extra metadata: the neutral frontmatter (`name`, `description`) is enough.

## Invocation and arguments

- `/pr-review 401 --dry-run`, or implicitly when the request matches the description.
- `$ARGUMENTS` in the body is replaced with the text after the skill name (**probado**: `hola --dos` arrived
  verbatim). Without a placeholder the harness appends `ARGUMENTS: <text>`; the neutral body has one, so the
  "text after the skill name" sentence is just a fallback here.

## Capabilities

| Capability in the skill | How it is met here |
|---|---|
| Run shell commands | `Bash` |
| Read files / search files by name | `Read`, `Glob`, `Grep` |
| Write a file (temporary payload, report) | `Write` (or a heredoc in `Bash`). The report lives outside the reviewed repo, so an interactive session asks for permission the first time |
| Ask the user and wait | `AskUserQuestion`, or a plain question in the reply and wait for the next turn. Not available under `claude -p`: the skill then follows "No one to ask" |
| Launch a fresh agent with its own context (the `-all` skills) | `Workflow` if the installation has it (one `agent()` per PR, results by schema), otherwise `Agent` (one per PR, up to `--parallel` at a time; subagents return only their final message) |

## Batch skills (`pr-review-all`, `pr-ready-all`)

- **Sibling path.** The skill expansion starts with the skill's base directory; `realpath` of
  `<base>/../pr-review/SKILL.md` gives the absolute path. A subagent reads it with `Read` whether the path is the
  symlink under `.claude/skills` or the real file in this repo, also under `claude -p` with only `Read` allowed
  (**probado**). Invoking the skill by name stays as the fallback in the prompt, but was not needed.
- **`Workflow`** (when the installation has it): one script, a pool of `--parallel` workers. There is no
  concurrency option per call (the tool caps a workflow at ~10 agents), so the pool limits it. Scripts cannot run
  shell commands, so the per-PR re-check is left to the agent's Step 0. Pass the data through `args`:

  ```js
  export const meta = { name: 'pr-batch', description: 'One fresh agent per PR', phases: [{ title: 'PRs' }] }
  const { prs, prompts, parallel, model } = args      // prompts: { "<n>": "<prompt from batch.md>" }
  const queue = [...prs], lines = {}
  async function worker() {
    while (queue.length) {
      const n = queue.shift()
      const out = await agent(prompts[n], { label: `#${n}`, phase: 'PRs', ...(model ? { model } : {}) })
      lines[n] = out ? String(out).trim().split('\n').pop() : null
    }
  }
  await Promise.all(Array.from({ length: parallel }, worker))
  return prs.map(n => ({ pr: n, line: lines[n] }))
  ```

  The orchestrator then checks all the lines at once (Step 7 of `batch.md`).
- **`Agent`** (no `Workflow`): up to `--parallel` `Agent` calls in one message, each with the prompt from
  `batch.md`; only the subagent's final message comes back, so the orchestrator keeps just its last line. Re-check
  each PR with `gh pr view` before its wave.
- Headless (`claude -p "/pr-review-all …"`) needs `Agent` (and `Workflow` if used) in `--allowedTools`, plus
  `Bash(realpath *)` and, for `pr-ready-all`, `Bash(sed *)`; subagents inherit the allowed tools, and the runs
  directory goes in `--add-dir`. **Probado** with `--dry-run` on two PRs: with both `Agent` and `Workflow`
  allowed, the orchestrator chose two background `Agent` calls (`general-purpose`), re-checked each PR with
  `gh pr view`, read no diff, and wrote `summary.json`/`summary.md` and the batch line. Nothing was posted.
- Token split: `--output-format stream-json --verbose` tags subagent messages with `parent_tool_use_id`; group by
  `message.id` (each content block repeats the message). `modelUsage`/`total_cost_usd` in the final event cover
  parent and children together.

## Headless (for `bin/pr-batch`)

```bash
AGENT_SKILLS_RUNS="$RUNS" claude -p "/pr-review owner/repo#401 --auto --run-dir=$RUN_DIR" \
  --output-format json --add-dir "$TMPDIR" \
  --allowedTools "Bash(gh *),Bash(git *),Bash(jq *),Bash(mkdir *),Bash(date *),Bash(printenv *),Bash(mktemp *),Bash(rm *),Read,Write,Glob,Grep" \
  < /dev/null > "$WORK/pr-401.claude.json" 2> "$WORK/pr-401.claude.err"
jq -r '.result' "$WORK/pr-401.claude.json" | tail -n 1     # the contract line
```

- `/pr-review` inside the `-p` prompt expands the skill (**probado**).
- The final message is `.result` of `--output-format json`; there is no flag to write it to a file, so redirect
  stdout.
- Since 2.1.302, `-p` starts in manual permission mode and denies anything not pre-approved. The space before
  `*` in `Bash(gh *)` matters.
- **Compound commands are denied** even when every part starts with an allowed prefix (**probado**: `;`,
  `for`, `cd … &&` and heredocs were all refused). The skills ask for one simple command per call for this
  reason.
- **Paths outside the working directory are denied** for allowed commands too (**probado**: `jq -c . <file>`
  and `rm <file>` on a `mktemp` file under `$TMPDIR` were refused). Run from a directory that contains the run
  directory, set `AGENT_SKILLS_RUNS` under it, and pass `--add-dir "$TMPDIR"` so the temporary payload and the
  JSON check work.
- Redirect stdin (`< /dev/null`): otherwise `-p` waits 3 s for piped input and prints a warning to stderr.
  Keep stderr out of the JSON file.
- `--model <m>` sets the model per PR.

## Notes

- `--bare` skips skills and `CLAUDE.md`: never use it with these skills.
- `resumeFromRunId` exists only for `Workflow`; the neutral retry path is re-running the failed PR numbers.
