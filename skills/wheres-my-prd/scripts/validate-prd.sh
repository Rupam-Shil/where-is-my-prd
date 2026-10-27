#!/bin/sh
# validate-prd.sh: check that a Where's My PRD spec is locked and complete.
# Zero dependencies: POSIX sh, awk, grep, sed, find, sort.

set -u
set -f

VERSION=1.0.0
MIN_SCORE=85
NL='
'

quiet=0
checked=0
failed=0

usage() {
  cat <<'EOF'
Usage: sh validate-prd.sh [-q] [FILE_OR_DIR ...]

Validates Where's My PRD specs. With no arguments, checks every *-prd.md
under docs/prd/. Directories are searched recursively for *-prd.md files.

Options:
  -q, --quiet     print failures only
  -h, --help      show this help
  -V, --version   print version

Exit codes:
  0  every PRD passes the gate
  1  at least one PRD fails
  2  usage error, or no PRD files found
EOF
}

# Print the value of a key from the leading YAML frontmatter block.
fm_get() {
  awk -v key="$2" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    /^---[[:space:]]*$/ { exit }
    index($0, key ":") == 1 {
      v = substr($0, length(key) + 2)
      sub(/[[:space:]]+#.*$/, "", v)
      sub(/^[[:space:]]+/, "", v)
      sub(/[[:space:]]+$/, "", v)
      if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
      print v
      exit
    }' "$1"
}

# Print the body of every "## " section whose heading matches an ERE (case-insensitive).
section() {
  awk -v re="$2" '
    { sub(/\r$/, "") }
    /^```/ { fence = !fence }
    !fence && /^##[[:space:]]/ { insec = (tolower($0) ~ re); next }
    insec { print }' "$1"
}

has_heading() {
  grep -Eiq "^##[[:space:]].*($2)" "$1"
}

err() { errs="${errs}${NL}  - $*"; }
warn() { warns="${warns}${NL}  ! $*"; }

check_file() {
  file=$1
  errs=''
  warns=''
  checked=$((checked + 1))

  if [ ! -r "$file" ]; then
    err "file is not readable"
    report "$file" '' ''
    return
  fi

  if [ "$(sed -n '1{s/\r$//;p;q;}' "$file")" != '---' ]; then
    err "missing YAML frontmatter (the file must start with ---)"
  fi

  slug=$(fm_get "$file" feature_slug)
  score=$(fm_get "$file" spec_readiness_score)
  p0=$(fm_get "$file" p0_blockers_remaining)
  mode=$(fm_get "$file" interrogation_mode)
  approved=$(fm_get "$file" approved_at)

  # feature_slug
  if [ -z "$slug" ]; then
    err "missing frontmatter field: feature_slug"
  elif ! printf '%s\n' "$slug" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    err "feature_slug must be kebab-case (got '$slug')"
  elif [ "$(basename "$file")" != "${slug}-prd.md" ]; then
    warn "filename should be ${slug}-prd.md to match feature_slug"
  fi

  # interrogation_mode
  case $mode in
    full_grill | fast_pass | emergency_default_lock) ;;
    '') err "missing frontmatter field: interrogation_mode" ;;
    *) err "interrogation_mode must be full_grill, fast_pass, or emergency_default_lock (got '$mode')" ;;
  esac

  # p0_blockers_remaining
  case $p0 in
    '') err "missing frontmatter field: p0_blockers_remaining" ;;
    *[!0-9]*) err "p0_blockers_remaining must be an integer (got '$p0')" ;;
    *)
      if [ "$p0" -ne 0 ]; then
        err "p0_blockers_remaining is $p0 (must be 0 before any code is written)"
      fi
      ;;
  esac

  # spec_readiness_score
  case $score in
    '') err "missing frontmatter field: spec_readiness_score" ;;
    *[!0-9]*) err "spec_readiness_score must be an integer 0-100 (got '$score')" ;;
    *)
      if [ "$score" -gt 100 ]; then
        err "spec_readiness_score must be 0-100 (got $score)"
      elif [ "$score" -lt "$MIN_SCORE" ]; then
        if [ "$mode" = emergency_default_lock ]; then
          warn "score $score < $MIN_SCORE: emergency defaults were never confirmed by a human"
        else
          err "spec_readiness_score is $score (needs >= $MIN_SCORE to unlock coding)"
        fi
      fi
      ;;
  esac

  # approved_at
  if [ -z "$approved" ]; then
    err "missing frontmatter field: approved_at"
  elif ! printf '%s\n' "$approved" |
    grep -Eq '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]+)?Z$'; then
    err "approved_at must be a UTC ISO-8601 timestamp like 2026-01-31T14:05:00Z (got '$approved')"
  fi

  # Follow-up phases (phase 2, v2, ...) link to what came before and say what changes
  phase=$(fm_get "$file" phase)
  parent=$(fm_get "$file" parent_prd)
  case $phase in
    '' | 1) ;;
    *[!0-9]*) err "phase must be an integer (got '$phase')" ;;
    0) err "phase starts at 1" ;;
    *)
      if [ -z "$parent" ]; then
        err "phase $phase needs parent_prd: the previous phase's PRD, or none if it shipped without one"
      elif [ "$(basename "$parent")" = "$(basename "$file")" ]; then
        err "parent_prd points at this PRD itself"
      elif [ "$parent" != none ] && [ ! -f "$parent" ] && [ ! -f "$(dirname "$file")/$(basename "$parent")" ]; then
        err "parent_prd not found: $parent"
      fi
      grep -Eiq '^#{2,3}[[:space:]].*baseline' "$file" ||
        err "phase $phase needs a Baseline & Changes section (what exists today and what changes)"
      ;;
  esac

  # Required sections
  while IFS=';' read -r label re; do
    has_heading "$file" "$re" || err "missing section: $label"
  done <<'EOF'
Overview & Problem Statement;overview
User Flow & State Machine;state machine
Data Contracts & Schema Changes;data contract
Edge Cases, Abuse Vectors & Guardrails;edge case
Telemetry & Event Logging;telemetry
Rollout, Feature Flags & Rollback;rollout
Out of Scope (Non-Goals);out of scope|non-goal
Open Risks & Assumed Defaults;open risk|assum
Acceptance Criteria;acceptance criteria
IMPLEMENTATION_TASKS;implementation_tasks
EOF

  # Every state is named in the state machine (as a table row or bullet)
  sm=$(section "$file" 'state machine')
  for pair in Idle:idle Loading:loading Success:success Empty:empty Error:error Rate-Limited:'rate.?limit'; do
    name=${pair%%:*}
    re=${pair#*:}
    printf '%s\n' "$sm" | grep -Eiq "^[[:space:]]*([|]|[-*])[[:space:]]*[*_]*${re}" ||
      err "state machine is missing the $name state (write 'N/A — reason' if it cannot occur)"
  done

  # Acceptance criteria map 1-to-1 onto implementation tasks
  acs=$(section "$file" 'acceptance criteria' | grep -Eo 'AC-[0-9]+' | sort -u)
  tasks=$(section "$file" 'implementation_tasks')
  task_lines=$(printf '%s\n' "$tasks" | grep -E '^[[:space:]]*[-*] \[[ xX]\]')
  if [ -z "$acs" ]; then
    err "no acceptance criteria found (number them AC-1, AC-2, ...)"
  fi
  if [ -z "$task_lines" ]; then
    err "IMPLEMENTATION_TASKS has no checklist items (- [ ] T1: ...)"
  else
    for ac in $acs; do
      printf '%s\n' "$task_lines" | grep -Eq "${ac}([^0-9]|\$)" ||
        err "$ac is not covered by any IMPLEMENTATION_TASKS item"
    done
    uncited=$(printf '%s\n' "$task_lines" | grep -Evc 'AC-[0-9]+')
    if [ "$uncited" -gt 0 ]; then
      warn "$uncited IMPLEMENTATION_TASKS item(s) cite no acceptance criterion"
    fi
  fi

  # Unfilled template placeholders
  ph=$(grep -n '{{' "$file" | head -n 1 | cut -d: -f1)
  if [ -n "$ph" ]; then
    err "unfilled template placeholder '{{' at line $ph"
  fi

  report "$file" "$score" "$mode"
}

report() {
  if [ -n "$errs" ]; then
    failed=$((failed + 1))
    printf 'FAIL %s%s\n' "$1" "$errs"
  elif [ "$quiet" -eq 0 ]; then
    printf 'PASS %s (score %s/100, %s)\n' "$1" "$2" "$3"
  fi
  if [ -n "$warns" ] && [ "$quiet" -eq 0 ]; then
    printf '%s\n' "${warns#"$NL"}"
  fi
}

while [ $# -gt 0 ]; do
  case $1 in
    -q | --quiet) quiet=1; shift ;;
    -h | --help) usage; exit 0 ;;
    -V | --version) echo "validate-prd $VERSION"; exit 0 ;;
    --) shift; break ;;
    -*) printf 'validate-prd: unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
    *) break ;;
  esac
done

[ $# -eq 0 ] && set -- docs/prd

for target in "$@"; do
  if [ -d "$target" ]; then
    files=$(find "$target" -type f -name '*-prd.md' | sort)
    old_ifs=$IFS
    IFS=$NL
    for f in $files; do
      IFS=$old_ifs
      check_file "$f"
    done
    IFS=$old_ifs
  elif [ -e "$target" ]; then
    check_file "$target"
  else
    printf 'validate-prd: no such file or directory: %s\n' "$target" >&2
    exit 2
  fi
done

if [ "$checked" -eq 0 ]; then
  printf 'validate-prd: no *-prd.md files found in: %s\n' "$*" >&2
  exit 2
fi

if [ "$quiet" -eq 0 ] || [ "$failed" -gt 0 ]; then
  printf '\n%s checked, %s failed\n' "$checked" "$failed"
fi

[ "$failed" -eq 0 ]
