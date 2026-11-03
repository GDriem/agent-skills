# batch.sh: shared by bin/pr-batch and bin/agent-batch. Source it; it defines functions only.
# bash 3.2 (macOS): no `wait -n`, no associative arrays, no mapfile. Arrays cannot be exported, so the
# per-session settings travel in BATCH_* environment variables to the `--one` child processes.

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-2}"; }

last_line() { awk 'NF { l = $0 } END { print l }'; }

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
default_run_dir() { # [suffix]
  local runs=${AGENT_SKILLS_RUNS:-$HOME/.agent-skills/runs}
  printf '%s/%s%s\n' "$runs" "$(date +%Y-%m-%dT%H-%M)" "${1:+-$1}"
}

abs_dir() { # <dir>: create it and print its absolute path
  mkdir -p "$1" && (cd "$1" && pwd)
}

# One headless session; prints the last non-empty line of its final message, or nothing.
#   headless_run <harness> <prompt> <raw file> <log file>
# Settings (all optional except BATCH_TOOLS for claude):
#   BATCH_MODEL       model for the session
#   BATCH_EFFORT      low|medium|high (claude --effort, codex model_reasoning_effort)
#   BATCH_TOOLS       claude --allowedTools value
#   BATCH_PERMISSION  claude --permission-mode value
#   BATCH_ADD_DIRS    directories the session may write to, separated by ":"
#   BATCH_WORKDIR     working directory of the session (default: the current one)
headless_run() {
  local harness=$1 prompt=$2 raw=$3 log=$4 dir old_ifs=$IFS
  local workdir=${BATCH_WORKDIR:-$PWD}
  local dirs=()
  IFS=:
  for dir in ${BATCH_ADD_DIRS:-}; do [ -n "$dir" ] && dirs+=("--add-dir" "$dir"); done
  IFS=$old_ifs

  case "$harness" in
    claude)
      local cmd=(claude -p "$prompt" --output-format json --allowedTools "$BATCH_TOOLS")
      cmd+=(${dirs[@]+"${dirs[@]}"})
      [ -n "${BATCH_PERMISSION:-}" ] && cmd+=(--permission-mode "$BATCH_PERMISSION")
      [ -n "${BATCH_MODEL:-}" ] && cmd+=(--model "$BATCH_MODEL")
      [ -n "${BATCH_EFFORT:-}" ] && cmd+=(--effort "$BATCH_EFFORT")
      (cd "$workdir" && "${cmd[@]}") < /dev/null > "$raw" 2> "$log" || true
      jq -r '.result // empty' "$raw" 2>/dev/null | last_line || true
      ;;
    codex)
      local cmd=(codex exec -C "$workdir" --skip-git-repo-check -s workspace-write -c approval_policy=never
        -c sandbox_workspace_write.network_access=true -o "$raw")
      cmd+=(${dirs[@]+"${dirs[@]}"})
      [ -n "${BATCH_MODEL:-}" ] && cmd+=(-m "$BATCH_MODEL")
      [ -n "${BATCH_EFFORT:-}" ] && cmd+=(-c "model_reasoning_effort=$BATCH_EFFORT")
      cmd+=("$prompt")
      "${cmd[@]}" < /dev/null > "$log" 2>&1 || true
      last_line < "$raw" 2>/dev/null || true
      ;;
  esac
}
