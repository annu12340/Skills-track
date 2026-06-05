#!/usr/bin/env bash
# Run evals for git-bisect-ai.
# Requires: ANTHROPIC_API_KEY in env, jq, curl.
# Usage: bash evals/git-bisect-ai/run.sh [case-id]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILL_MD="$ROOT/skills/git-bisect-ai/SKILL.md"
CASES_DIR="$SCRIPT_DIR/cases"
MODEL="${EVAL_MODEL:-claude-sonnet-4-6}"
FILTER="${1:-}"

pass_count=0; fail_count=0

run_case() {
  local case_file="$1"
  local id description

  id="$(jq -r '.id' "$case_file")"
  [ -n "$FILTER" ] && [[ "$id" != "$FILTER" ]] && return

  description="$(jq -r '.description' "$case_file")"
  scenario="$(jq -r '.input.scenario' "$case_file")"
  range="$(jq -r '.input.commit_range // ""' "$case_file")"
  state="$(jq -r '.input.repo_state // ""' "$case_file")"

  printf '[eval %s] %s\n' "$id" "$description"

  local prompt
  prompt="$(cat "$SKILL_MD")

---
## Eval input

Scenario: $scenario
Commit range: $range
Repo state: $state

Describe how you would handle this bisect scenario. What commands would you run, in what order, and why? This is an automated eval — be concise but include your reasoning."

  local response
  response="$(curl -s https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(jq -n \
      --arg model "$MODEL" \
      --arg prompt "$prompt" \
      '{model: $model, max_tokens: 1024, messages: [{role: "user", content: $prompt}]}')" \
  | jq -r '.content[0].text // ""')"

  local ok=1
  mapfile -t must_contain    < <(jq -r '.expected.must_contain[]'    "$case_file" 2>/dev/null || true)
  mapfile -t must_not_contain < <(jq -r '.expected.must_not_contain[]' "$case_file" 2>/dev/null || true)
  mapfile -t checkpoints      < <(jq -r '.expected.reasoning_checkpoints[]' "$case_file" 2>/dev/null || true)

  for term in "${must_contain[@]}"; do
    grep -qi "$term" <<<"$response" || { printf '  FAIL must_contain: "%s"\n' "$term"; ok=0; }
  done
  for term in "${must_not_contain[@]}"; do
    ! grep -qi "$term" <<<"$response" || { printf '  FAIL must_not_contain: "%s"\n' "$term"; ok=0; }
  done

  checkpoint_hit=0
  for term in "${checkpoints[@]}"; do
    grep -qi "$term" <<<"$response" && checkpoint_hit=1 && break
  done
  if [ "${#checkpoints[@]}" -gt 0 ] && [ "$checkpoint_hit" -eq 0 ]; then
    printf '  FAIL reasoning: none of [%s] found\n' "${checkpoints[*]}"; ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    printf '  PASS\n'; pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf '  Response excerpt: %s\n' "$(head -c 200 <<<"$response")"
  fi
}

[ -n "${ANTHROPIC_API_KEY:-}" ] || { echo "ANTHROPIC_API_KEY not set" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

for f in "$CASES_DIR"/*.json; do run_case "$f"; done

echo ""
printf 'git-bisect-ai: %d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
