#!/bin/sh
# Test suite for the Where's My PRD repository. Zero dependencies beyond POSIX tools.
# Runs the validator under every POSIX-ish shell it finds (sh, dash, bash, ksh).
#
# Usage: sh tests/run.sh

set -u

root=$(cd "$(dirname "$0")/.." && pwd)
skill_dir="$root/skills/wheres-my-prd"
validator="$skill_dir/scripts/validate-prd.sh"
fixture="$root/tests/fixtures/sample-feature-prd.md"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/wmp-tests.XXXXXX")
trap 'rm -rf "${tmp:?}"' EXIT

shells=''
for s in sh dash bash ksh; do
  command -v "$s" >/dev/null 2>&1 && shells="$shells $s"
done

total=0
bad=0
case_no=0

pass() { total=$((total + 1)); printf 'ok   %s\n' "$1"; }
fail() {
  total=$((total + 1))
  bad=$((bad + 1))
  printf 'FAIL %s\n' "$1"
  printf '%s\n' "$2" | sed 's/^/     | /'
}

# expect NAME WANT_EXIT WANT_TEXT TRANSFORM_FN
# Applies TRANSFORM_FN (stdin -> stdout) to the fixture, then runs the validator under every shell.
expect() {
  case_no=$((case_no + 1))
  dir="$tmp/case-$case_no"
  mkdir -p "$dir"
  f="$dir/sample-feature-prd.md"
  "$4" < "$fixture" > "$f"
  problems=''
  for shell in $shells; do
    out=$($shell "$validator" "$f" 2>&1)
    code=$?
    if [ "$code" -ne "$2" ]; then
      problems="${problems}[$shell] expected exit $2, got $code: $out
"
    else
      case $out in
        *"$3"*) ;;
        *) problems="${problems}[$shell] output lacks '$3': $out
" ;;
      esac
    fi
  done
  if [ -z "$problems" ]; then pass "$1"; else fail "$1" "$problems"; fi
}

# Fixture transforms
t_identity() { cat; }
t_crlf() { awk '{ printf "%s\r\n", $0 }'; }
t_p0() { sed 's/^p0_blockers_remaining: 0/p0_blockers_remaining: 2/'; }
t_low_score() { sed 's/^spec_readiness_score: 90/spec_readiness_score: 70/'; }
t_emergency_low() { sed -e 's/^spec_readiness_score: 90/spec_readiness_score: 52/' -e 's/^interrogation_mode: full_grill/interrogation_mode: emergency_default_lock/'; }
t_score_high() { sed 's/^spec_readiness_score: 90/spec_readiness_score: 120/'; }
t_score_text() { sed 's/^spec_readiness_score: 90/spec_readiness_score: high/'; }
t_mode() { sed 's/^interrogation_mode: full_grill/interrogation_mode: yolo/'; }
t_date() { sed 's/^approved_at: .*/approved_at: 2026-10-27 09:30/'; }
t_quoted() { sed 's/^approved_at: \(.*\)/approved_at: "\1"/'; }
t_comment() { sed 's/^p0_blockers_remaining: 0/p0_blockers_remaining: 0  # all resolved/'; }
t_slug() { sed 's/^feature_slug: sample-feature/feature_slug: Sample_Feature/'; }
t_slug_mismatch() { sed 's/^feature_slug: sample-feature/feature_slug: other-feature/'; }
t_no_field() { sed '/^approved_at:/d'; }
t_no_frontmatter() { sed '1d'; }
t_no_section() { sed '/^## 5\. Telemetry/d'; }
t_no_state() { sed '/^| Rate-Limited/d'; }
t_uncovered_ac() { sed 's/^- \[ \] T3: Rate limit on the endpoint (AC-3)/- [ ] T3: Rate limit on the endpoint/'; }
t_no_tasks() { sed '/^- \[ \] T/d'; }
t_no_acs() { sed '/^- \*\*AC-/d'; }
t_placeholder() { sed 's/^- PDF export\./- {{non-goal}}/'; }
t_done_tasks() { sed 's/^- \[ \] T1:/- [x] T1:/'; }

echo "Validator (shells:$shells)"
expect "valid PRD passes" 0 "PASS" t_identity
expect "CRLF line endings pass" 0 "PASS" t_crlf
expect "quoted frontmatter values pass" 0 "PASS" t_quoted
expect "inline YAML comments are ignored" 0 "PASS" t_comment
expect "checked-off tasks still count" 0 "PASS" t_done_tasks
expect "heading inside a code fence is ignored" 0 "PASS" t_identity
expect "open P0 blockers fail" 1 "p0_blockers_remaining is 2" t_p0
expect "score below 85 fails" 1 "needs >= 85" t_low_score
expect "low score passes with a warning in emergency mode" 0 "never confirmed" t_emergency_low
expect "score above 100 fails" 1 "must be 0-100" t_score_high
expect "non-integer score fails" 1 "must be an integer" t_score_text
expect "unknown interrogation_mode fails" 1 "interrogation_mode must be" t_mode
expect "non-UTC timestamp fails" 1 "approved_at must be" t_date
expect "non-kebab-case slug fails" 1 "kebab-case" t_slug
expect "slug/filename mismatch warns" 0 "filename should be other-feature-prd.md" t_slug_mismatch
expect "missing frontmatter field fails" 1 "missing frontmatter field: approved_at" t_no_field
expect "missing frontmatter fails" 1 "missing YAML frontmatter" t_no_frontmatter
expect "missing section fails" 1 "missing section: Telemetry & Event Logging" t_no_section
expect "missing state fails" 1 "missing the Rate-Limited state" t_no_state
expect "acceptance criterion with no task fails" 1 "AC-3 is not covered" t_uncovered_ac
expect "task citing no criterion warns" 1 "cite no acceptance criterion" t_uncovered_ac
expect "empty IMPLEMENTATION_TASKS fails" 1 "no checklist items" t_no_tasks
expect "no acceptance criteria fails" 1 "no acceptance criteria found" t_no_acs
expect "unfilled template placeholder fails" 1 "unfilled template placeholder" t_placeholder

echo
echo "Validator CLI"

mkdir -p "$tmp/dir/nested" "$tmp/empty"
cp "$fixture" "$tmp/dir/sample-feature-prd.md"
t_p0 < "$fixture" > "$tmp/dir/nested/sample-feature-prd.md"
out=$(sh "$validator" "$tmp/dir" 2>&1)
code=$?
if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q '2 checked, 1 failed'; then
  pass "directory mode recurses and summarizes"
else
  fail "directory mode recurses and summarizes" "exit $code: $out"
fi

out=$(sh "$validator" -q "$fixture" 2>&1)
code=$?
if [ "$code" -eq 0 ] && [ -z "$out" ]; then pass "--quiet prints nothing on success"; else fail "--quiet prints nothing on success" "exit $code: $out"; fi

sh "$validator" "$tmp/empty" >/dev/null 2>&1
code=$?
if [ "$code" -eq 2 ]; then pass "empty directory exits 2"; else fail "empty directory exits 2" "exit $code"; fi

sh "$validator" "$tmp/does-not-exist" >/dev/null 2>&1
code=$?
if [ "$code" -eq 2 ]; then pass "missing path exits 2"; else fail "missing path exits 2" "exit $code"; fi

sh "$validator" --bogus >/dev/null 2>&1
code=$?
if [ "$code" -eq 2 ]; then pass "unknown option exits 2"; else fail "unknown option exits 2" "exit $code"; fi

(cd "$tmp/dir" && mkdir -p docs/prd && cp "$fixture" docs/prd/ && sh "$validator" >/dev/null 2>&1)
code=$?
if [ "$code" -eq 0 ]; then pass "defaults to docs/prd"; else fail "defaults to docs/prd" "exit $code"; fi

echo
echo "Repository"

out=$(sh "$validator" "$root/examples/prd" 2>&1)
code=$?
if [ "$code" -eq 0 ]; then pass "example PRDs pass the validator"; else fail "example PRDs pass the validator" "$out"; fi

name=$(awk 'NR > 1 && /^---/ { exit } /^name:/ { print $2 }' "$skill_dir/SKILL.md")
if [ "$name" = "wheres-my-prd" ]; then pass "SKILL.md name matches its folder"; else fail "SKILL.md name matches its folder" "name: '$name'"; fi

desc_len=$(awk 'NR > 1 && /^---/ { exit } /^description:/ { sub(/^description:[[:space:]]*/, ""); print length($0) }' "$skill_dir/SKILL.md")
if [ "${desc_len:-0}" -gt 0 ] && [ "$desc_len" -le 1024 ]; then
  pass "SKILL.md description is 1-1024 chars ($desc_len)"
else
  fail "SKILL.md description is 1-1024 chars" "length: ${desc_len:-0}"
fi

# Token budget: the PRD caps SKILL.md at 1,800 tokens. At ~3.85 chars/token, that is ~6,900 characters.
chars=$(wc -c < "$skill_dir/SKILL.md" | tr -d ' ')
if [ "$chars" -le 6900 ]; then
  pass "SKILL.md within the ~1,800-token budget ($chars chars)"
else
  fail "SKILL.md within the ~1,800-token budget" "$chars chars > 6900"
fi

for ref in references/interrogation-rubric.md references/domain-packs.md references/prd-template.md scripts/validate-prd.sh; do
  if [ -f "$skill_dir/$ref" ]; then pass "skill ships $ref"; else fail "skill ships $ref" "missing"; fi
done

out=$(sh "$root/scripts/build-cursor-rule.sh" --check 2>&1)
code=$?
if [ "$code" -eq 0 ]; then pass "Cursor rule is in sync with SKILL.md"; else fail "Cursor rule is in sync with SKILL.md" "$out"; fi

v_plugin=$(sed -n 's/^  "version": "\(.*\)",*$/\1/p' "$root/.claude-plugin/plugin.json")
v_market=$(sed -n 's/^      "version": "\(.*\)",*$/\1/p' "$root/.claude-plugin/marketplace.json")
v_script=$(sh "$validator" --version | awk '{ print $2 }')
if [ -n "$v_plugin" ] && [ "$v_plugin" = "$v_market" ] && [ "$v_plugin" = "$v_script" ]; then
  pass "versions agree ($v_plugin)"
else
  fail "versions agree" "plugin.json=$v_plugin marketplace.json=$v_market validate-prd.sh=$v_script"
fi

if command -v python3 >/dev/null 2>&1; then
  for j in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
    if python3 -m json.tool "$root/$j" >/dev/null 2>&1; then pass "$j is valid JSON"; else fail "$j is valid JSON" "parse error"; fi
  done
fi

echo
echo "$total tests, $bad failed"
[ "$bad" -eq 0 ]
