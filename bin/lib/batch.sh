# shellcheck shell=bash
# batch.sh: shared by bin/pr-batch and bin/agent-batch. Source it; it defines functions only.
# bash 3.2 (macOS): no `wait -n`, no associative arrays, no mapfile. Arrays cannot be exported, so the
# per-session settings travel in BATCH_* environment variables to the `--one` child processes.

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-2}"; }

last_line() { awk 'NF { l = $0 } END { print l }'; }

last_lines() { # <n>: the last n non-empty lines, in order
  awk -v n="$1" 'NF { l[++c] = $0 } END { for (i = (c > n ? c - n + 1 : 1); i <= c; i++) print l[i] }'
}

# Harnesses with a headless runner implemented here.
check_harness() { # <harness>
  case "$1" in
    claude|codex) ;;
    copilot|gemini|cursor)
      die "harness '$1' is not implemented yet in $PROG; see adapters/ and docs/harness-matrix.md" ;;
    "") die "--harness is required (claude or codex)" ;;
    *) die "unknown harness: $1" ;;
  esac
}

check_parallel() { # <value>
  case "$1" in ''|*[!0-9]*|0) die "--parallel must be an integer >= 1" ;; esac
}

check_bins() { # <bin>...
  local bin
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || die "'$bin' is not on PATH"
  done
}

# Default run directory: $AGENT_SKILLS_RUNS or ~/.agent-skills/runs, plus the start time and a suffix.
# Creates it, and takes -2, -3… when another batch already claimed that minute (mkdir is atomic).
default_run_dir() { # [suffix]
  local runs=${AGENT_SKILLS_RUNS:-$HOME/.agent-skills/runs} base i=1 dir
  base="$runs/$(date +%Y-%m-%dT%H-%M)${1:+-$1}"
  mkdir -p "$runs" || return 1
  dir=$base
  until mkdir "$dir" 2>/dev/null; do i=$((i + 1)); dir="$base-$i"; done
  printf '%s\n' "$dir"
}

abs_dir() { # <dir>: create it and print its absolute path
  mkdir -p "$1" && (cd "$1" && pwd)
}

# Denied in every claude session, on top of what BATCH_TOOLS allows (a deny always wins over an allow, including
# --allow-tool): the skills' hard rules that would change shared history or decide for a person. Local
# rewrites (commit --amend, reset --hard) stay allowed: pr-fix uses them on its own unpushed commits, and a
# plain push of such a commit can only fast-forward. `*` matches any text, so `git *push*` also covers
# `git -C <worktree> push …`; flags are matched with a leading space so a branch named `my-fix` is not a `-f`.
# ` :**` (a `git push <remote> :<branch>` delete) ends in `**`, not `:*`: Claude Code reads a trailing `:*` as the
# old prefix syntax and would match it literally. Checked against claude 2.1 with real sessions.
GUARD_DENY='Bash(git *push*--force*),Bash(git *push* -f*),Bash(git *push* +*),Bash(git *push*--mirror*)'
GUARD_DENY="$GUARD_DENY,Bash(git *push*--delete*),Bash(git *push* -d *),Bash(git *push* :**)"
GUARD_DENY="$GUARD_DENY,Bash(git *push*:refs/heads/main),Bash(git *push*:refs/heads/master)"
GUARD_DENY="$GUARD_DENY,Bash(git *--no-verify*)"
GUARD_DENY="$GUARD_DENY,Bash(gh pr merge*),Bash(gh pr close*),Bash(gh pr review*--approve*),Bash(gh pr review* -a*)"
GUARD_DENY="$GUARD_DENY,Bash(gh api*resolveReviewThread*),Bash(gh api*/merge*)"

# One headless session; prints the last non-empty line of its final message (the last BATCH_LINES lines
# when that is set), or nothing.
#   headless_run <harness> <prompt> <raw file> <log file>
# Settings (all optional except BATCH_TOOLS for claude):
#   BATCH_MODEL       model for the session
#   BATCH_EFFORT      low|medium|high (claude --effort, codex model_reasoning_effort)
#   BATCH_TOOLS       claude --allowedTools value
#   BATCH_DENY        claude --disallowedTools, added to GUARD_DENY
#   BATCH_PERMISSION  claude --permission-mode value
#   BATCH_ADD_DIRS    directories the session may write to, separated by ":"
#   BATCH_WORKDIR     working directory of the session (default: the current one)
#   BATCH_LINES       how many trailing lines of the final message to print (default 1)
headless_run() {
  local harness=$1 prompt=$2 raw=$3 log=$4 dir old_ifs=$IFS
  local workdir=${BATCH_WORKDIR:-$PWD}
  local add_dirs=()
  IFS=:
  for dir in ${BATCH_ADD_DIRS:-}; do [ -n "$dir" ] && add_dirs+=("--add-dir" "$dir"); done
  IFS=$old_ifs

  case "$harness" in
    claude)
      local argv=(claude -p "$prompt" --output-format json --allowedTools "$BATCH_TOOLS"
        --disallowedTools "$GUARD_DENY${BATCH_DENY:+,$BATCH_DENY}")
      argv+=(${add_dirs[@]+"${add_dirs[@]}"})
      [ -n "${BATCH_PERMISSION:-}" ] && argv+=(--permission-mode "$BATCH_PERMISSION")
      [ -n "${BATCH_MODEL:-}" ] && argv+=(--model "$BATCH_MODEL")
      [ -n "${BATCH_EFFORT:-}" ] && argv+=(--effort "$BATCH_EFFORT")
      (cd "$workdir" && "${argv[@]}") < /dev/null > "$raw" 2> "$log" || true
      jq -r '.result // empty' "$raw" 2>/dev/null | last_lines "${BATCH_LINES:-1}" || true
      ;;
    codex)
      local argv=(codex exec -C "$workdir" --skip-git-repo-check -s workspace-write -c approval_policy=never
        -c sandbox_workspace_write.network_access=true -o "$raw")
      argv+=(${add_dirs[@]+"${add_dirs[@]}"})
      [ -n "${BATCH_MODEL:-}" ] && argv+=(-m "$BATCH_MODEL")
      [ -n "${BATCH_EFFORT:-}" ] && argv+=(-c "model_reasoning_effort=$BATCH_EFFORT")
      argv+=("$prompt")
      "${argv[@]}" < /dev/null > "$log" 2>&1 || true
      last_lines "${BATCH_LINES:-1}" < "$raw" 2>/dev/null || true
      ;;
  esac
}
