#!/bin/sh
# Regenerate .cursor/rules/wheres-my-prd.mdc from skills/wheres-my-prd/SKILL.md
# so the Cursor rule never drifts from the skill.
#
# Usage: sh scripts/build-cursor-rule.sh          # write the rule
#        sh scripts/build-cursor-rule.sh --check  # exit 1 if the rule is stale

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
skill="$root/skills/wheres-my-prd/SKILL.md"
out="$root/.cursor/rules/wheres-my-prd.mdc"

render() {
  description=$(awk 'NR > 1 && /^---/ { exit } /^description:/ { sub(/^description:[[:space:]]*/, ""); print }' "$skill")
  body=$(awk 'NR == 1 && /^---/ { fm = 1; next } fm && /^---/ { fm = 0; next } !fm' "$skill")
  printf -- '---\ndescription: %s\nglobs:\nalwaysApply: false\n---\n\n' "$description"
  printf '<!-- Generated from skills/wheres-my-prd/SKILL.md by scripts/build-cursor-rule.sh. Edit the skill, not this file. -->\n\n'
  cat <<'EOF'
> Paths like `references/...` and `scripts/...` are relative to the wheres-my-prd skill folder (`.cursor/skills/wheres-my-prd/`, `.agents/skills/wheres-my-prd/`, or `~/.cursor/skills/wheres-my-prd/`). If the folder is not installed, read them from https://github.com/Rupam-Shil/where-is-my-prd/tree/main/skills/wheres-my-prd
EOF
  printf '%s\n' "$body"
}

if [ "${1:-}" = "--check" ]; then
  if render | cmp -s - "$out"; then
    echo "cursor rule is up to date"
  else
    echo "cursor rule is stale: run sh scripts/build-cursor-rule.sh" >&2
    exit 1
  fi
else
  mkdir -p "$(dirname "$out")"
  render > "$out"
  echo "wrote ${out#"$root"/}"
fi
