#!/usr/bin/env bash
# tests/run.sh: tests for bin/pr-batch, bin/agent-batch, install.sh and the repo checks, with fake gh and
# claude on PATH (tests/fakes/), so nothing reaches GitHub or a model. Needs only bash 3.2, jq and git.
#   tests/run.sh            all tests
#   tests/run.sh <pattern>  only the tests whose name contains <pattern>

set -uo pipefail

ROOT=$(cd -P "$(dirname "$0")/.." && pwd -P)
FILTER=${1:-}
passed=0 failed=0 failures=""

# ---------------------------------------------------------------------------------------------------
# Helpers

# Fresh sandbox per test: fake binaries first on PATH, a private HOME, TMPDIR and run root.
setup() {
  T=$(mktemp -d "${ORIG_TMPDIR%/}/agent-skills-test.XXXXXX")
  export FAKE_DIR="$T/fake" HOME="$T/home" TMPDIR="$T/tmp" AGENT_SKILLS_RUNS="$T/runs"
  mkdir -p "$FAKE_DIR" "$HOME" "$TMPDIR" "$T/bin"
  cp "$ROOT/tests/fakes/gh" "$ROOT/tests/fakes/claude" "$T/bin/"
  export PATH="$T/bin:$ORIG_PATH"
}

teardown() { rm -rf "$T"; }

# pr <n> <additions> <files> [path] [state] [draft]
pr() {
  local path=${4:-src/file.txt}
  jq -n --argjson n "$1" --argjson add "$2" --argjson files "$3" --arg path "$path" \
    --arg state "${5:-OPEN}" --argjson draft "${6:-false}" \
    '{number:$n, state:$state, isDraft:$draft, additions:$add, deletions:0, changedFiles:$files,
      files:[{path:$path}], author:{login:"me"}, reviewDecision:null, reviews:[], statusCheckRollup:[]}' \
    > "$FAKE_DIR/pr-$1.json"
}

run() { # <cmd...>: runs it, keeps stdout+stderr in $OUT and the exit code in $CODE
  OUT=$("$@" < /dev/null 2>&1)
  CODE=$?
}

# Each test runs in a subshell, so exit stops just that test (set -e would not: the test runs inside an if).
fail() { echo "    $1"; exit 1; }
assert_code() { [ "$CODE" = "$1" ] || fail "expected exit $1, got $CODE; output:
$OUT"; }
assert_out() { case "$OUT" in *"$1"*) ;; *) fail "output lacks '$1':
$OUT" ;; esac; }
assert_jq() { # <file> <jq expression that must be true>
  jq -e "$2" "$1" >/dev/null 2>&1 || fail "$1 does not satisfy: $2
$(cat "$1" 2>/dev/null)"
}
summary() { find "$AGENT_SKILLS_RUNS" -mindepth 1 -maxdepth 1 -type d | head -n 1; }
calls() { find "$FAKE_DIR/calls" -name '*.prompt' 2>/dev/null | wc -l | tr -d ' '; }

t() { # <name> <function>
  case "$1" in *"$FILTER"*) ;; *) return 0 ;; esac
  setup
  if ("$2"); then
    passed=$((passed + 1)); echo "ok    $1"
  else
    failed=$((failed + 1)); failures="$failures
  - $1"; echo "FAIL  $1"
  fi
  teardown
}

ORIG_PATH=$PATH ORIG_TMPDIR=${TMPDIR:-/tmp}
PRB="$ROOT/bin/pr-batch"
AB="$ROOT/bin/agent-batch"

# ---------------------------------------------------------------------------------------------------
# Repo checks

test_lint_skills() { run "$ROOT/scripts/lint-skills.sh"; assert_code 0; }
test_references_in_sync() { run "$ROOT/scripts/sync-references.sh" --check; assert_code 0; }

# ---------------------------------------------------------------------------------------------------
# bin/pr-batch: arguments

test_prb_help() { run "$PRB" --help; assert_code 0; assert_out "Usage:"; }
test_prb_needs_harness() { run "$PRB" 1; assert_code 2; assert_out "--harness is required"; }
test_prb_unimplemented_harness() { run "$PRB" --harness gemini 1; assert_code 2; assert_out "not implemented"; }
test_prb_bad_range() { run "$PRB" --harness claude 10-5; assert_code 2; assert_out "invalid PR range"; }
test_prb_bad_number() { run "$PRB" --harness claude abc; assert_code 2; assert_out "invalid PR number"; }
test_prb_fix_flags_need_pr_fix() { run "$PRB" --harness claude --no-push 1; assert_code 2; assert_out "only apply to --skill pr-fix"; }
test_prb_numbers_and_all() { pr 1 5 1; run "$PRB" --harness claude --dry-run 1 all; assert_code 2; assert_out "not both"; }

test_prb_posting_needs_yes() {
  pr 1 5 1
  run "$PRB" --harness claude 1
  assert_code 2; assert_out "needs --yes"
  [ "$(calls)" = 0 ] || fail "a session was launched"
}

# ---------------------------------------------------------------------------------------------------
# bin/pr-batch: runs

test_prb_tiers_and_grouping() {
  pr 1 5 1; pr 2 10 2               # trivial, trivial: one grouped budget session
  pr 3 50 5                         # small
  pr 4 5 1 src/auth/login.ts        # trivial by size, but a sensitive path: normal
  pr 5 500 20                       # normal
  run "$PRB" --harness claude --dry-run 1,2,3,4,5
  assert_code 0
  assert_out "#1:trivial #2:trivial #3:small #4:normal #5:normal"
  local s; s=$(summary)/summary.json
  assert_jq "$s" 'length == 5 and all(.[]; .verdict == "COMMENT")'
  assert_jq "$s" '[.[] | .tier] == ["trivial","trivial","small","normal","normal"]'
  [ "$(calls)" = 4 ] || fail "expected 4 sessions (1 group + 3), got $(calls)"
  grep -l 'owner/repo#1' "$FAKE_DIR"/calls/*.prompt | xargs grep -q 'owner/repo#2' || fail "1 and 2 not grouped"
  grep -h 'haiku' "$FAKE_DIR"/calls/*.flags | grep -c . | grep -qx 2 || fail "budget model not used twice"
  grep -l 'owner/repo#5' "$FAKE_DIR"/calls/*.prompt | xargs grep -q -- '--light' && fail "normal PR ran --light"
  return 0
}

test_prb_guard_rails() {
  pr 1 500 20
  run "$PRB" --harness claude --dry-run 1
  assert_code 0
  local flags; flags=$(cat "$FAKE_DIR"/calls/*.flags)
  case "$flags" in *"--disallowedTools Bash(git *push*--force*)"*"Bash(gh pr merge*)"*) ;; *) fail "no guard deny list: $flags" ;; esac
  case "$flags" in *"Bash(rm $TMPDIR/*)"*) ;; *) fail "rm not limited to TMPDIR: $flags" ;; esac
  case "$flags" in *"Bash(rm *)"*) fail "unrestricted rm: $flags" ;; esac
  return 0
}

test_prb_no_tiering() {
  pr 1 5 1; pr 2 5 1
  run "$PRB" --harness claude --dry-run --no-tiering 1,2
  assert_code 0
  [ "$(calls)" = 2 ] || fail "expected one session per PR"
  grep -q -- '--light' "$FAKE_DIR"/calls/*.prompt && fail "--light with --no-tiering"
  return 0
}

test_prb_skips_closed_and_draft() {
  pr 1 5 1 src/a OPEN; pr 2 5 1 src/a MERGED; pr 3 5 1 src/a OPEN true
  run "$PRB" --harness claude --dry-run --no-tiering 1,2,3
  assert_code 0
  local s; s=$(summary)/summary.json
  assert_jq "$s" '[.[] | .verdict] == ["COMMENT","SKIPPED","SKIPPED"]'
  assert_jq "$s" '[.[] | .error] == [null,"merged","draft"]'
}

test_prb_range_lists_open_prs() {
  pr 7 5 1; pr 8 5 1 src/a CLOSED; pr 9 5 1; pr 20 5 1
  run "$PRB" --harness claude --dry-run --no-tiering 7-10
  assert_code 0
  assert_jq "$(summary)/summary.json" '[.[] | .pr] == [7,9]'
}

test_prb_missing_line_is_error_and_retry() {
  pr 1 500 20; pr 2 500 20
  touch "$FAKE_DIR/noresult-2"
  run "$PRB" --harness claude --dry-run 1,2
  assert_code 1
  local dir; dir=$(summary)
  assert_jq "$dir/summary.json" '[.[] | .verdict] == ["COMMENT","ERROR"]'
  grep -q -- '--retry-failed' "$dir/summary.md" || fail "summary.md has no retry command"

  rm "$FAKE_DIR/noresult-2"
  local before; before=$(calls)
  run "$PRB" --harness claude --dry-run --retry-failed "$dir"
  assert_code 0
  [ "$(calls)" = $((before + 1)) ] || fail "the retry should run only PR 2"
  assert_jq "$dir/summary.json" 'length == 2 and all(.[]; .verdict == "COMMENT")'
}

test_prb_escalation() {
  pr 1 50 5
  touch "$FAKE_DIR/escalate-1"
  run "$PRB" --harness claude --dry-run 1
  assert_code 0
  assert_out "escalating to a full review: 1"
  [ "$(calls)" = 2 ] || fail "expected a light and a full session"
  assert_jq "$(summary)/summary.json" '.[0].tier == "small" and .[0].escalated and .[0].escalate_reason == "possible blocker"'
}

test_prb_final_line() {
  pr 1 500 20
  run "$PRB" --harness claude --dry-run 1
  assert_code 0
  printf '%s\n' "$OUT" | tail -n 1 | jq -e '.skill == "pr-review-all" and .total == 1 and .counts.COMMENT == 1 and .dry_run' >/dev/null ||
    fail "bad final line: $(printf '%s\n' "$OUT" | tail -n 1)"
}

# ---------------------------------------------------------------------------------------------------
# bin/agent-batch

repo() { # a git repo to run agent-batch in
  git init -q "$T/repo"
  git -C "$T/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  cd "$T/repo" || exit 1
}

test_ab_needs_tasks() { repo; run "$AB" --harness claude; assert_code 2; assert_out "no tasks"; }
test_ab_bad_verify() { repo; run "$AB" --harness claude --task a --verify nolabel; assert_code 2; assert_out "label=command"; }

test_ab_dry_run_waves() {
  repo
  run "$AB" --harness claude --dry-run --task "audit a" --task "audit b" --wave --task "merge both"
  assert_code 0
  assert_out "Wave 1:"; assert_out "Wave 2:"
  assert_jq "$(summary)/graph.json" '.tasks[2].deps == ["t1","t2"]'
  [ "$(calls)" = 0 ] || fail "a dry run launched a session"
}

test_ab_writes_need_yes() { repo; run "$AB" --harness claude --task a; assert_code 2; assert_out "needs --yes"; }

test_ab_read_only_run() {
  repo
  run "$AB" --harness claude --read-only --task "audit a" --task "audit b" --wave --task "merge"
  assert_code 0
  assert_jq "$(summary)/summary.json" '[.tasks[] | .status] == ["ok","ok","ok"] and all(.tasks[]; .kind == "read")'
  grep -l 'merge' "$FAKE_DIR"/calls/*.prompt | xargs grep -q '\[t1\] done' || fail "t3 did not get t1's summary"
}

test_ab_task_agents_cannot_push() {
  repo
  run "$AB" --harness claude --read-only --task a
  assert_code 0
  grep -q -- '--no-verify\*),.*Bash(git \*push\*)' "$FAKE_DIR"/calls/*.flags || fail "push not denied: $(cat "$FAKE_DIR"/calls/*.flags)"
}

test_ab_failure_blocks_dependents() {
  repo
  touch "$FAKE_DIR/fail-t1"
  run "$AB" --harness claude --read-only --task a --wave --task b
  assert_code 1
  assert_jq "$(summary)/summary.json" '[.tasks[] | .status] == ["failed","blocked"]'
  [ "$(calls)" = 1 ] || fail "the blocked task was launched"
}

test_ab_cycle_is_blocked() {
  repo
  printf '%s' '[{"id":"a","prompt":"x","kind":"read","deps":["b"]},{"id":"b","prompt":"y","kind":"read","deps":["a"]}]' > "$T/g.json"
  run "$AB" --harness claude --tasks "$T/g.json"
  assert_code 1
  assert_jq "$(summary)/summary.json" 'all(.tasks[]; .status == "blocked" and .error == "dependency cycle")'
}

test_ab_verify_only_when_files_changed() {
  repo
  run "$AB" --harness claude --yes --task a --verify "ok=true"
  assert_code 0; assert_out "Checks skipped"
  echo src/a.txt > "$FAKE_DIR/files-t1"
  run "$AB" --harness claude --yes --task a --verify "ok=true" --verify "bad=false"
  assert_code 0   # documented: the exit code follows the tasks; a failed check shows in verify
  assert_out "check ok: pass"; assert_out "check bad: FAIL"
  printf '%s\n' "$OUT" | tail -n 1 | jq -e '.verify.all_passed == false' >/dev/null || fail "verify not reported"
}

test_ab_task_file_without_value() { repo; run "$AB" --harness claude --task-file; assert_code 2; assert_out "no such task file"; }

# ---------------------------------------------------------------------------------------------------
# install.sh, on a copy of the checkout: generated files live inside it

copy_checkout() {
  mkdir -p "$T/src"
  (cd "$ROOT" && git ls-files -z | xargs -0 tar cf -) | (cd "$T/src" && tar xf -)
}

test_install_check_uninstall() {
  copy_checkout
  printf '#!/bin/sh\nexit 0\n' > "$T/bin/codex"; chmod +x "$T/bin/codex"
  mkdir -p "$HOME/.agents/skills/pr-review"; echo old > "$HOME/.agents/skills/pr-review/SKILL.md"
  run "$T/src/install.sh" --harness claude-code,codex --yes
  assert_code 0
  [ -L "$HOME/.claude/skills/pr-review" ] && [ -L "$HOME/.agents/skills/pr-review" ] || fail "links missing"
  # shellcheck disable=SC2016 # a literal $pr-review
  grep -qx '  default_prompt: "Use $pr-review on the pull request."' "$T/src/skills/pr-review/agents/openai.yaml" ||
    fail "bad openai.yaml: $(cat "$T/src/skills/pr-review/agents/openai.yaml")"
  run "$T/src/install.sh" --harness claude-code,codex --check
  assert_code 0; assert_out "0 problem(s)"
  run "$T/src/install.sh" --harness claude-code,codex --uninstall --yes
  assert_code 0
  [ ! -e "$HOME/.claude/skills/pr-review" ] || fail "claude link left behind"
  [ "$(cat "$HOME/.agents/skills/pr-review/SKILL.md" 2>/dev/null)" = old ] || fail "backup not restored"
}

# ---------------------------------------------------------------------------------------------------

for name in $(compgen -A function | grep '^test_'); do t "${name#test_}" "$name"; done

echo
echo "$passed passed, $failed failed"
[ "$failed" = 0 ] || { echo "Failed:$failures"; exit 1; }
