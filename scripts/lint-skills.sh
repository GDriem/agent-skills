#!/usr/bin/env bash
# lint-skills.sh: check every skills/<name>/SKILL.md against the Agent Skills format and this repo's rules:
# frontmatter with a name equal to the folder (lowercase, digits and hyphens, at most 64 characters) and a
# description of at most 1024 characters, and every references/<file>.md it mentions present in the folder.
# Works with the bash 3.2 that ships with macOS.

set -euo pipefail

ROOT=$(cd -P "$(dirname "$0")/.." && pwd -P)
problems=0

fail() { echo "FAIL  $1"; problems=$((problems + 1)); }

for skill_md in "$ROOT"/skills/*/SKILL.md; do
  dir=$(dirname "$skill_md")
  folder=$(basename "$dir")
  rel="skills/$folder/SKILL.md"

  [ "$(head -n 1 "$skill_md")" = "---" ] || { fail "$rel: no frontmatter on the first line"; continue; }
  front=$(awk 'NR == 1 { next } /^---$/ { exit } { print }' "$skill_md")
  name=$(printf '%s\n' "$front" | sed -n 's/^name: *//p')
  desc=$(printf '%s\n' "$front" | sed -n 's/^description: *//p')

  [ "$name" = "$folder" ] || fail "$rel: name '$name' does not match the folder '$folder'"
  case "$name" in *[!a-z0-9-]*|-*|*-) fail "$rel: name '$name' must be lowercase letters, digits and inner hyphens" ;; esac
  [ ${#name} -le 64 ] || fail "$rel: name longer than 64 characters"
  [ -n "$desc" ] || fail "$rel: empty or missing description"
  [ ${#desc} -le 1024 ] || fail "$rel: description has ${#desc} characters (at most 1024)"

  while IFS= read -r ref; do
    [ -f "$dir/$ref" ] || fail "$rel: mentions $ref, which does not exist"
  done < <(grep -o 'references/[A-Za-z0-9_.-]*\.md' "$skill_md" | sort -u)
done

if [ "$problems" -gt 0 ]; then
  echo "$problems problem(s)"
  exit 1
fi
echo "skills OK"
