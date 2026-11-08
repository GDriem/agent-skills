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
  the old command is removed (documented, and **probado**: with both present, `claude -p "/pr-review …"` ran the
  skill and emitted the contract line). `install.sh --harness claude-code --retire-conflicts` moves the old
  command to the backup afterwards.
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
  shell commands, so the per-PR re-check is left to the agent's Step 0. Pass the units of Step 6 through `args`
  (one per `normal` or `small` PR, one per group of `trivial` PRs), each with its prompt and its model:

  ```js
  export const meta = { name: 'pr-batch', description: 'One fresh agent per PR or per group of trivial PRs', phases: [{ title: 'PRs' }] }
  const { units, parallel } = args   // units: [{ prs: [<n>, …], prompt: "<prompt from batch.md>", model: "<m>" | null }]
  const queue = [...units], lines = {}
  async function worker() {
    while (queue.length) {
      const u = queue.shift()
      const out = await agent(u.prompt, { label: u.prs.map(n => `#${n}`).join(' '), phase: 'PRs', ...(u.model ? { model: u.model } : {}) })
      const tail = out ? String(out).trim().split('\n').filter(l => l.trim()).slice(-u.prs.length) : []
      u.prs.forEach((n, i) => { lines[n] = tail[i] ?? null })
    }
  }
  await Promise.all(Array.from({ length: parallel }, worker))
  return units.flatMap(u => u.prs).map(n => ({ pr: n, line: lines[n] }))
  ```

  The orchestrator then checks all the lines at once (Step 7 of `batch.md`); escalations go in a second run of
  the same script with one `normal` unit per escalated PR.
- **Budget tier** (`trivial` and `small` PRs of `pr-review-all`): `model: 'haiku'`, or `--small-model` when given,
  in `agent()`, in `Agent`, or as `claude --model` in `bin/pr-batch`. `normal` PRs take `--model` or nothing.
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

## `orchestrate`

- **Tiers.** `small` → `model: 'haiku'`, `default` → no model (the session's), `large` → `model: 'opus'`.
  `effort` (`low`/`medium`/`high`) goes as is to `agent()`, to `Agent`, or to `claude --effort`. `--model`
  of `bin/agent-batch` overrides the tier.
- **`Workflow`** (when the installation has it): pass the graph through `args` as a real JSON object, not a string,
  and the script below **as is**. It does Steps 5–7 of `run.md`: reads in a pool of `parallel`, writes one at a
  time, a separate small agent per commit (a script cannot run shell commands), and one agent for the checks.
  The schema replaces the final JSON line: the agent returns the object. Invoking the skill is the opt-in that
  `Workflow` requires.

  ```json
  { "tasks": [ ...graph.json tasks... ], "runDir": "<run-dir>", "root": "<root>", "readOnly": false,
    "commit": false, "parallel": 3, "verify": [ { "label": "build", "cmd": "<the repo's build command>" } ] }
  ```

  ```js
  export const meta = {
    name: 'orchestrate',
    description: 'Run a task graph: one fresh agent per task, reads in parallel, writes in series, then checks',
    phases: [{ title: 'Tasks' }, { title: 'Checks' }],
  }

  const TASKS = args?.tasks ?? []
  const RUN_DIR = args?.runDir ?? '.'
  const ROOT = args?.root ?? '.'
  const READ_ONLY = args?.readOnly === true
  const COMMIT = args?.commit === true && !READ_ONLY
  const PARALLEL = Math.max(1, args?.parallel ?? 3)
  const VERIFY = args?.verify ?? []
  const TIER_MODEL = { small: 'haiku', large: 'opus' }

  const LINE_SCHEMA = {
    type: 'object',
    properties: {
      status: { type: 'string', enum: ['ok', 'failed'] },
      summary: { type: 'string', description: 'what was done, 60 words max' },
      files_changed: { type: 'array', items: { type: 'string' }, description: 'repo-relative paths, 15 max' },
      artifacts: { type: 'array', items: { type: 'string' }, description: 'absolute paths under the run dir' },
      follow_ups: { type: 'array', items: { type: 'string' } },
      error: { type: ['string', 'null'] },
    },
    required: ['status', 'summary'],
  }
  const COMMIT_SCHEMA = {
    type: 'object',
    properties: { committed: { type: 'boolean' }, sha: { type: ['string', 'null'] }, error: { type: ['string', 'null'] } },
    required: ['committed'],
  }

  const ids = new Set(TASKS.map(t => t.id))
  const depsOf = t => (t.deps ?? []).filter(d => ids.has(d))
  const kindOf = t => (READ_ONLY ? 'read' : t.kind ?? 'write')
  const lines = new Map()
  const line = (t, status, error, summary, extra = {}) => ({
    skill: 'orchestrate', task: t.id, kind: kindOf(t), status, summary: summary ?? '',
    files_changed: [], artifacts: [], follow_ups: [], error: error ?? null, ...extra,
  })

  // The task prompt of skills/orchestrate/references/contract.md.
  const promptOf = t => {
    const fence = (t.files ?? []).length ? t.files.join(', ') : 'the scope described above'
    const ctx = depsOf(t).map(d => {
      const r = lines.get(d)
      const arts = (r.artifacts ?? []).length ? ` · artifacts: ${r.artifacts.join(', ')}` : ''
      return `- [${d}] ${r.summary}${arts}`
    })
    const mode = kindOf(t) === 'read'
      ? `READ-ONLY: you must not create, edit or delete any file in the repository. Report only. Writing your report under ${RUN_DIR} is allowed.`
      : `You may edit files, but ONLY within: ${fence}. Do not touch anything else. Do not commit and do not push.`
    return [
      t.prompt, '', '--- Execution rules ---',
      'You have no access to any earlier conversation, and no other agent is working on your files.',
      mode, `Scope: ${fence}`, `Done when: ${t.done ?? 'the task above is complete and self-consistent.'}`,
      ...(ctx.length ? ['Conclusions of the tasks you depend on (read their artifact files yourself if you need detail):', ...ctx] : []),
      `If you produce anything longer than a short summary (a report, a plan, an inventory), write it to ${RUN_DIR}/orchestrate-${t.id}.md and list that path in artifacts.`,
      'Nobody can answer questions in this session. If you cannot finish, set status to "failed" and say why in error instead of guessing or half-doing it.',
      'Return: summary at most 60 words, files_changed at most 15 repository-relative paths. Never put file contents, diffs or command output in any field.',
    ].join('\n')
  }

  const runTask = async t => {
    if (budget.total && budget.remaining() < 30_000) return line(t, 'skipped', 'turn budget exhausted', 'Not run.')
    const opts = { label: `${t.id} · ${t.title}`, phase: 'Tasks', schema: LINE_SCHEMA }
    if (TIER_MODEL[t.tier]) opts.model = TIER_MODEL[t.tier]
    if (t.effort) opts.effort = t.effort
    try {
      const r = await agent(promptOf(t), opts)
      if (!r) return line(t, 'failed', 'no result line', 'The agent returned nothing.')
      const status = r.status === 'ok' ? 'ok' : 'failed'
      return line(t, status, status === 'ok' ? null : r.error ?? 'the agent gave no reason', r.summary, {
        files_changed: (r.files_changed ?? []).slice(0, 15), artifacts: r.artifacts ?? [], follow_ups: r.follow_ups ?? [],
      })
    } catch (e) {
      return line(t, 'failed', String(e), 'The agent failed.')
    }
  }

  // A separate small agent, not the one that wrote the code: it stages the fence, not its own file list.
  const commitTask = async t => {
    if (!t.commit) return { committed: false, sha: null, error: 'the task has no commit message' }
    if (!(t.files ?? []).length) return { committed: false, sha: null, error: 'the task has no files to stage' }
    const fence = t.files.map(f => `'${f}'`).join(' ')
    try {
      const c = await agent(
        `Stage exactly this task's paths and make ONE commit, one command per step:\n` +
          `1. git -C ${ROOT} add -A -- ${fence}\n` +
          `2. git -C ${ROOT} diff --cached --quiet (exit code 0 means nothing is staged: stop, committed false, error "nothing to commit")\n` +
          `3. git -C ${ROOT} commit -m ${JSON.stringify(t.commit)}\n` +
          `4. git -C ${ROOT} rev-parse --short HEAD -> sha\n` +
          `Do not push, amend, rebase, reset or check out. Do not edit any file. Stage nothing outside those paths.`,
        { label: `commit · ${t.id}`, phase: 'Tasks', model: 'haiku', effort: 'low', schema: COMMIT_SCHEMA }
      )
      return c ?? { committed: false, sha: null, error: 'the commit agent returned nothing' }
    } catch (e) {
      return { committed: false, sha: null, error: String(e) }
    }
  }

  const pool = async (items, fn) => {
    const queue = [...items]
    const worker = async () => { while (queue.length) await fn(queue.shift()) }
    await Promise.all(Array.from({ length: Math.min(PARALLEL, items.length) }, worker))
  }

  phase('Tasks')
  const remaining = new Map(TASKS.map(t => [t.id, t]))
  while (remaining.size) {
    const ready = [...remaining.values()].filter(t => depsOf(t).every(d => lines.has(d)))
    if (!ready.length) {
      for (const t of remaining.values()) lines.set(t.id, line(t, 'blocked', 'dependency cycle', 'Not run.'))
      break
    }
    for (const t of ready) remaining.delete(t.id)
    const runnable = []
    for (const t of ready) {
      const bad = depsOf(t).filter(d => lines.get(d).status !== 'ok')
      if (bad.length) lines.set(t.id, line(t, 'blocked', `dependency not ok: ${bad.join(', ')}`, 'Not run.'))
      else runnable.push(t)
    }
    await pool(runnable.filter(t => kindOf(t) === 'read'), async t => {
      lines.set(t.id, await runTask(t))
      log(`[${t.id}] ${lines.get(t.id).status}`)
    })
    for (const t of runnable.filter(t => kindOf(t) === 'write')) {
      const r = await runTask(t)
      if (COMMIT && r.status === 'ok') r.commit = await commitTask(t)
      lines.set(t.id, r)
      log(`[${t.id}] ${r.status}${r.commit ? ` · commit ${r.commit.sha ?? `no (${r.commit.error})`}` : ''}`)
    }
  }

  let verify = null
  const touched = [...lines.values()].some(r => r.status === 'ok' && r.files_changed.length)
  if (VERIFY.length && touched) {
    phase('Checks')
    verify = await agent(
      `From ${ROOT}, run each command in order, one per call, and report each outcome:\n` +
        VERIFY.map(v => `- ${v.label}: ${v.cmd}`).join('\n') +
        `\nDo not fix anything and do not edit any file. For a failure, error is the single most relevant line, ` +
        `200 characters max. Never paste full output.`,
      {
        label: 'checks', phase: 'Checks',
        schema: {
          type: 'object',
          properties: {
            all_passed: { type: 'boolean' },
            checks: { type: 'array', items: { type: 'object', properties: {
              label: { type: 'string' }, cmd: { type: 'string' }, passed: { type: 'boolean' }, error: { type: ['string', 'null'] },
            }, required: ['label', 'passed'] } },
          },
          required: ['all_passed', 'checks'],
        },
      }
    )
  }

  return { tasks: TASKS.map(t => lines.get(t.id) ?? line(t, 'skipped', 'never launched', 'Not run.')), verify }
  ```

  The orchestrator writes `summary.json` from the returned object as is, then does Steps 8–10. A failed run can
  also be resumed with `resumeFromRunId` (finished tasks come from the cache); the neutral path is `--only`.
- **`Agent`** (no `Workflow`): read tasks of a wave as up to `--parallel` `Agent` calls in one message
  (`general-purpose`, `model`/`effort` from the tier), write tasks one call per turn; the orchestrator commits and
  runs the checks itself with `Bash`. Only the final message comes back, so keep its last line.
- **Headless** (`claude -p "/orchestrate … --yes"`): allow `Agent` (and `Workflow` if used), `Write`, `Read`,
  `Glob`, `Grep`, `Bash(git *)`, `Bash(jq *)`, `Bash(mkdir *)`, `Bash(date *)`, `Bash(printenv *)`,
  `Bash(realpath *)`, `Bash(mktemp *)`, `Bash(rm *)`, plus `Edit` for write tasks, and `--add-dir` both the runs
  directory and `"$TMPDIR"` (without the latter the line check's temporary file cannot be deleted). **Probado**
  with a 3-task graph (two reads, one write that depends on a read) in a scratch repository: with `Agent` and
  `Workflow` both allowed, the orchestrator chose three `Agent` calls, ran the write after its dependency, and
  wrote `graph.json`, `summary.json` and `summary.md`; `--dry-run` launched nothing. With
  `~/.claude/commands/orchestrate.md` still present, `/orchestrate` ran the skill.
- **`Workflow` path, probado** (same graph, `Workflow` allowed and `Agent` not, the prompt asking for a
  workflow): one `Workflow` call ran four agents (one per task, one for the checks), the `small` tier went to
  `haiku`, and the returned object became `summary.json` as `contract.md` defines it. The workflow runs in the
  background, so `-p` ends its first turn and resumes on the task notification: the stream has two `result`
  events, and the second one carries the session totals. Workflow agents inherit `--allowedTools`; their compound
  `Bash` commands were denied and they retried with simple ones.
- **`--only`, probado**: `/orchestrate --only t3 --run-dir=<that run> --yes` relaunched only t3 (one `Agent`),
  took t1 from the earlier `summary.json`, left the t1 and t2 lines untouched and rewrote `summary.md`.

## `pr-fix` and `pr-fix-all`

- **`pr-fix` interactive, probado** (2026-11-07, a real PR with two review threads, one of them a decision):
  `pr-review` → `pr-fix` → `pr-ready`. It applied the project's `CLAUDE.md` and backend skill, asked the decision
  with `AskUserQuestion`, made one commit per item with no AI attribution and the thread link in the body, ran
  lint, typecheck and the touched tests in the worktree, pushed fast-forward, replied in both threads without
  resolving them and removed the worktree. `pr-ready` then returned `READY` with both threads `ATENDIDO`.
  Not tested yet: `--dry-run`, `--no-push`, headless and `pr-fix-all`.
- Edits go through `Edit`/`MultiEdit` inside the worktree; the first edit outside the session's directory asks for
  permission in an interactive session. `AskUserQuestion` covers the decision questions of Step 3.
- Headless (`bin/pr-batch --skill pr-fix`): the runner adds `Edit,MultiEdit`, `--permission-mode acceptEdits`,
  and `--add-dir` for the worktrees directory. The repository's check commands are not pre-approved: pass one
  `--allow-tool` per tool the checks need (`"Bash(npm *)"`, `"Bash(dotnet *)"`, …); a denied check is recorded
  as not run, never bypassed.
- `pr-fix-all` with `Agent` or `Workflow`: the PR agents need the same tools; their worktrees are separate, so up
  to `--parallel` can run at once.
- Interactive sessions and the `-all` skills under `Agent` or `Workflow` do not go through `bin/pr-batch`, so they
  only get the guard rails you configure. The same list as `permissions.deny` in `~/.claude/settings.json`:

  ```json
  { "permissions": { "deny": [
    "Bash(git *push*--force*)", "Bash(git *push* -f*)", "Bash(git *push* +*)", "Bash(git *push*--mirror*)",
    "Bash(git *push*--delete*)", "Bash(git *push* -d *)", "Bash(git *push* :**)",
    "Bash(git *push*:refs/heads/main)", "Bash(git *push*:refs/heads/master)", "Bash(git *--no-verify*)",
    "Bash(gh pr merge*)", "Bash(gh pr close*)", "Bash(gh pr review*--approve*)", "Bash(gh pr review* -a*)",
    "Bash(gh api*resolveReviewThread*)", "Bash(gh api*/merge*)"
  ] } }
  ```

  It applies to everything you do in Claude Code, not only to these skills: drop the entries you use yourself.

## Headless (for `bin/pr-batch` and `bin/agent-batch`)

Both runners start sessions through `headless_run` in `bin/lib/batch.sh`; `agent-batch` adds `Edit`,
`MultiEdit` and `--permission-mode acceptEdits` for write tasks, `--effort` from the task, and `--model` from the
tier (`haiku`/`opus`) unless `--model` was given.

```bash
AGENT_SKILLS_RUNS="$RUNS" claude -p "/pr-review owner/repo#401 --auto --run-dir=$RUN_DIR" \
  --output-format json --add-dir "$TMPDIR" \
  --allowedTools "Bash(gh *),Bash(git *),Bash(jq *),Bash(mkdir *),Bash(date *),Bash(printenv *),Bash(mktemp *),Bash(rm $TMPDIR/*),Read,Write,Glob,Grep" \
  --disallowedTools "$GUARD_DENY" \
  < /dev/null > "$WORK/pr-401.claude.json" 2> "$WORK/pr-401.claude.err"
jq -r '.result' "$WORK/pr-401.claude.json" | tail -n 1     # the contract line
```

- **Guard rails.** Every session also gets `--disallowedTools` with `GUARD_DENY` from `bin/lib/batch.sh`: force,
  `+refspec`, `--mirror` and delete pushes, pushes to `main`/`master`, `--no-verify`, `gh pr merge`/`close`,
  `gh pr review --approve` and resolving threads through `gh api`. A deny wins over any allow, including
  `--allow-tool`. `rm` is allowed only under `$TMPDIR` (the skills' payload files), and `agent-batch` also denies
  every `git push`. **Probado** (claude 2.1.311, real sessions on a throwaway repository): every denied form was
  refused, and a plain push to a branch named `my-fix`, a local `commit --amend` and `rm` of a `mktemp` file
  went through. A trailing `:*` in a pattern is the old prefix syntax and is matched literally, so the
  `git push <remote> :<branch>` rule is written ` :**`.
- `/pr-review` inside the `-p` prompt expands the skill (**probado**).
- `bin/pr-batch --harness claude --dry-run <n>` on a real PR after the move to `bin/lib/batch.sh`
  (**probado**): contract line parsed, `posted:false`, `summary.json`/`summary.md` written, exit 0.
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
