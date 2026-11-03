# Adapter: codex

How the neutral skills in `skills/` run in the OpenAI CLI (`codex`). Verified with 0.166.0 on 2026-11-02; what
was tested in this repo is marked **probado**, the rest comes from the docs cited in
[docs/harness-matrix.md](../docs/harness-matrix.md).

## Install

| Scope | Path |
|---|---|
| User | `~/.agents/skills/<name>` → symlink to `skills/<name>` |
| Project | `<repo>/.agents/skills/<name>` (**probado**) |

- **`~/.codex/skills` is still read** (**probado**: with an old `pr-review` there and the new one under
  `.agents/skills`, the session loaded both `SKILL.md` files and mixed their instructions). The docs no longer
  list that path, but 0.166 honors it. Installing this repo means removing or renaming any same-name skill in
  `~/.codex/skills` first; `install.sh --check` must report it.
- `~/.codex/prompts` (custom prompts) are deprecated; do not install there.
- Optional metadata `agents/openai.yaml` (display name, implicit invocation policy) is generated at install
  time, never stored in `skills/`.

## Invocation and arguments

- `$pr-review 401 --dry-run`, `/skills`, or implicitly.
- `$ARGUMENTS` is **not** substituted: the model sees the literal placeholder. The model does receive the text
  after `$pr-review` and reads it as the arguments (**probado**: `hola --dos` arrived verbatim). The neutral
  sentence "the text that follows the skill name" is what makes it work here.

## Capabilities

| Capability in the skill | How it is met here |
|---|---|
| Run shell commands | the shell tool (`zsh -lc` / `bash -lc`) |
| Read files / search files by name | shell (`cat`, `rg --files`, `git ls-files`); there is no separate read tool |
| Write a file (temporary payload, report) | `apply_patch` or a shell heredoc. Inside `workspace-write`, only the workdir, `/tmp` and `$TMPDIR` are writable: set `AGENT_SKILLS_RUNS` under one of them, or add the runs directory with `--add-dir` |
| Ask the user and wait | a question in the reply, then wait for the next turn (interactive). Under `codex exec` nobody answers: the skill follows "No one to ask" |
| Launch a fresh agent with its own context (the `-all` skills) | `multi_agent` (stable, on by default in 0.166). Tools (**probado**): `spawn_agent`, `wait_agent`, `send_message`, `followup_task`, `interrupt_agent`. **Pass `fork_turns: "none"`**: the default `"all"` copies the parent's whole conversation into the child (**probado**: with `"all"` the child knew a word only said to the parent; with `"none"` it did not). `spawn_agent` also takes `model` and `reasoning_effort` |

`spawn_agent` fails under `codex exec --ephemeral` ("no rollout found for thread id"): the child loads the parent
thread from the session store, which `--ephemeral` does not write (**probado**). Do not combine the `-all`
skills with `--ephemeral`.

## Headless (for `bin/pr-batch`)

```bash
AGENT_SKILLS_RUNS="$RUNS" codex exec -C "$WORKDIR" \
  -s workspace-write -c approval_policy=never \
  -c sandbox_workspace_write.network_access=true \
  -o "$WORK/pr-401.codex.txt" \
  '$pr-review owner/repo#401 --auto --run-dir='"$RUN_DIR" < /dev/null
tail -n 1 "$WORK/pr-401.codex.txt"      # the contract line
```

- **Close stdin** (`< /dev/null`). Without it, `codex exec` started from a script waits forever on "Reading
  additional input from stdin…" (**probado**).
- `-o FILE` writes only the final message; `--json` gives JSONL events if the batch wants token counts.
- **Network.** In `workspace-write` the sandbox has no network. A `prefix_rule(pattern=[...], decision="allow")`
  in `~/.codex/rules/*.rules` runs the matching command outside the sandbox, with network (**probado**:
  `gh pr view` allowed by a rule worked, `gh api` with no rule failed with "error connecting to
  api.github.com"). The skills call many `gh` subcommands (`api`, `pr view`, `pr diff`, `pr checks`,
  `search`), so either allow the prefix `["gh"]` or pass `-c sandbox_workspace_write.network_access=true` for
  the run (**probado**, no config file touched). The second is what `bin/pr-batch` uses.
- `-m <model>` per PR; `-c` overrides any config key for one run.
- `CODEX_HOME=<dir>` isolates a run from the user's skills and memories. A directory with symlinks to
  `~/.codex/{auth.json,config.toml,rules}` and no `skills/` is how the smoke avoided the old port (**probado**).
