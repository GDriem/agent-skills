#!/usr/bin/env bash
# sync-references.sh: copy the shared references in shared/references/ into every skill that uses them.
# Each skill folder is installed on its own (a symlink per skill), so it must carry its own copy; the copy in
# shared/references/ is the one to edit. With --check, change nothing and exit 1 if a copy differs.
# Works with the bash 3.2 that ships with macOS.

set -euo pipefail

PROG=$(basename "$0")
ROOT=$(cd -P "$(dirname "$0")/.." && pwd -P)

# <shared file>|<copy, relative to skills/>
MAP='batch.md|pr-review-all/references/batch.md
batch.md|pr-ready-all/references/batch.md
batch.md|pr-fix-all/references/batch.md
quality-gate.md|pr-review/references/quality-gate.md
quality-gate.md|pr-ready/references/quality-gate.md
quality-gate.md|pr-fix/references/quality-gate.md
comment-templates.md|pr-review/references/comment-templates.md
comment-templates.md|pr-ready/references/comment-templates.md
posting.md|pr-review/references/posting.md
posting.md|pr-ready/references/posting.md
review-contract.md|pr-review/references/contract.md
review-contract.md|pr-ready/references/contract.md'

check=0
case "${1:-}" in
  --check) check=1 ;;
  "") ;;
  -h|--help) echo "Usage: $PROG [--check]"; exit 0 ;;
  *) echo "$PROG: unknown argument: $1" >&2; exit 2 ;;
esac

bad=0
while IFS='|' read -r src dst; do
  from="$ROOT/shared/references/$src" to="$ROOT/skills/$dst"
  [ -f "$from" ] || { echo "$PROG: missing $from" >&2; exit 2; }
  cmp -s "$from" "$to" && continue
  if [ "$check" = 1 ]; then
    echo "DIFFERS  skills/$dst (source: shared/references/$src)"
    bad=$((bad + 1))
  else
    cp "$from" "$to"
    echo "updated  skills/$dst"
  fi
done <<EOF
$MAP
EOF

if [ "$check" = 1 ]; then
  [ "$bad" = 0 ] || { echo "$bad copy(ies) out of sync; edit shared/references/ and run $PROG"; exit 1; }
  echo "shared references in sync"
fi
