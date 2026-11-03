---
name: orchestrate
description: Split a prompt that contains several tasks into a dependency graph and run it with one fresh agent per task, so no task shares context with another. Read tasks run in parallel, write tasks one after another on the current working tree, then the repository's own checks run. Collects one result line per task into a run summary. Supports --dry-run, --yes, --only, --read-only, --commit, --no-verify, --max and --parallel. Use when asked to orchestrate, fan out or split a multi-task prompt across agents.
---

# orchestrate

Turn one prompt with several tasks into a task graph and run it across a fleet of agents: one task, one agent,
one fresh context. This skill plans, launches and collects; the work itself is done by the task agents.

**Arguments.** The arguments are the text that follows the skill name in the message that invoked this skill.
Some harnesses substitute them here: `$ARGUMENTS`. If that still reads as a literal placeholder, use the text
after the skill name instead. Everything that is not a flag below is the prompt to split.

| Argument | Meaning |
|---|---|
| `<prompt>` | the work to split into tasks |
| `--dry-run` | build and show the graph, write `graph.json`, launch nothing |
| `--yes` | skip the confirmation before launching |
| `--only t3,t5` | re-run just these task ids of an earlier run; needs `--run-dir` of that run |
| `--run-dir=<path>` | where the graph, the task reports and the summary go (default: see `references/run.md`) |
| `--read-only` | every task is a read task: the fleet researches and reports, nobody edits a file |
| `--commit` | one commit per successful write task, never a push (preconditions in `references/run.md`) |
| `--no-verify` | skip the repository's build/lint/test checks at the end |
| `--max N` | keep at most N tasks; the rest are reported as deferred, never dropped silently |
| `--parallel N` | at most N task agents at a time; default 3; `1` runs everything in series |

This skill is repository-agnostic: the repository, its default branch and its check commands are resolved when
it runs, and nothing about a specific project is written here.

**Hard rules, in every mode:**

- **Context economy first.** Your own context holds the graph and one result line per task, never the files.
  Do not read source files to plan, and never read a task's diff or full output; results travel as short
  summaries and artifact paths.
- One task, one fresh agent (not a fork of this conversation). Never reuse an agent for a second task.
- Write tasks never run at the same time as each other. Read tasks never edit a file.
- Nothing is pushed, ever. Nothing is committed unless `--commit` was given and its preconditions hold.
- One task failing never stops the run: its dependents become `blocked`, everything else goes on.
- Report the `status` each agent reported. An agent returning is not a success.

## Capabilities this skill relies on

- **Run shell commands** (`git`, `jq`, `date`, `mkdir`, `printenv`, `realpath`, `mktemp`). Required.
- **Write a file** (the graph, the summary).
- **Launch a fresh agent with its own context**, with a model or effort setting when the harness has one, and
  wait for it. If the harness cannot, `bin/agent-batch` does it with one headless session per task (see
  "Launching one agent per task" in `references/run.md`).
- **Ask the user and wait.** If nobody can answer, see "No one to ask" in `references/run.md`.

Shell commands: one simple command per call, no `;`, `&&`, loops or heredocs chaining several commands; pipes
into `jq` are fine. Independent commands go in parallel calls.

## What to do

Follow `references/run.md` from Step 1 to the end. Every task agent follows the prompt and the result line
defined in `references/contract.md`; this skill never reads anything else of theirs.
