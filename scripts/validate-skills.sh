#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/skills-validate.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

expect_rc() {
  local expected="$1"; shift
  set +e
  "$@"
  local rc=$?
  set -e
  [ "$rc" -eq "$expected" ] || fail "expected exit $expected, got $rc: $*"
}

expect_rc_quiet() {
  local expected="$1"; shift
  set +e
  "$@" >/dev/null 2>&1
  local rc=$?
  set -e
  [ "$rc" -eq "$expected" ] || fail "expected exit $expected, got $rc: $*"
}

validate_skill_md() {
  local skill_dir="$1"
  python3 - "$skill_dir" <<'PY'
import re
import sys
from pathlib import Path

skill_dir = Path(sys.argv[1])
content = (skill_dir / "SKILL.md").read_text()
match = re.match(r"^---\n(.*?)\n---\n", content, re.S)
if not match:
    raise SystemExit(f"{skill_dir}: missing or invalid frontmatter")
frontmatter = match.group(1)
name_match = re.search(r"^name:\s*([a-z0-9-]+)\s*$", frontmatter, re.M)
if not name_match:
    raise SystemExit(f"{skill_dir}: missing hyphen-case name")
name = name_match.group(1)
if len(name) > 64 or name.startswith("-") or name.endswith("-") or "--" in name:
    raise SystemExit(f"{skill_dir}: invalid skill name {name!r}")
if not re.search(r"^description:\s*", frontmatter, re.M):
    raise SystemExit(f"{skill_dir}: missing description")
body_lines = content.splitlines()[content.splitlines().index("---", 1) + 1 :]
if len(body_lines) > 500:
    raise SystemExit(f"{skill_dir}: SKILL.md body is over 500 lines")
print(name)
PY
}

validate_openai_yaml() {
  local skill_dir="$1" skill_name="$2" yaml="$skill_dir/agents/openai.yaml"
  [ -f "$yaml" ] || fail "$skill_dir missing agents/openai.yaml"
  grep -q '^interface:$' "$yaml" || fail "$yaml missing interface section"
  grep -q '^  display_name: "' "$yaml" || fail "$yaml missing display_name"
  grep -q '^  short_description: "' "$yaml" || fail "$yaml missing short_description"
  grep -q '^  default_prompt: "' "$yaml" || fail "$yaml missing default_prompt"
  grep -Fq "\$$skill_name" "$yaml" || fail "$yaml default_prompt must mention \$$skill_name"
}

validate_skill_shape() {
  local skill_dir="$1" base
  while IFS= read -r -d '' path; do
    base="$(basename "$path")"
    case "$base" in
      SKILL.md|scripts|references|agents|assets) ;;
      *) fail "$skill_dir has unexpected top-level artifact: $base" ;;
    esac
  done < <(find "$skill_dir" -mindepth 1 -maxdepth 1 -print0)
}

validate_skills() {
  local skill_dir skill_name
  while IFS= read -r -d '' skill_dir; do
    skill_name="$(validate_skill_md "$skill_dir")"
    validate_openai_yaml "$skill_dir" "$skill_name"
    validate_skill_shape "$skill_dir"
    pass "validated metadata for ${skill_dir#$ROOT/}"
  done < <(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d -print0)
}

validate_shell_syntax() {
  local script
  while IFS= read -r -d '' script; do
    bash -n "$script"
    pass "shell syntax ${script#$ROOT/}"
  done < <(find "$ROOT/skills" "$ROOT/scripts" -type f -name '*.sh' -print0)
}

validate_demo_setup_syntax() {
  local setup
  while IFS= read -r -d '' setup; do
    bash -n "$setup"
    pass "demo setup syntax ${setup#$ROOT/}"
  done < <(find "$ROOT/demo-repos" -mindepth 2 -maxdepth 2 -type f -name setup.sh -print0)
}

skill_dir_by_name() {
  local wanted="$1" skill_dir
  while IFS= read -r -d '' skill_dir; do
    if grep -q "^name: $wanted$" "$skill_dir/SKILL.md"; then
      printf '%s\n' "$skill_dir"
      return 0
    fi
  done < <(find "$ROOT/skills" -mindepth 1 -maxdepth 1 -type d -print0)
  return 1
}

smoke_build_probe() {
  local dep_skill probe
  dep_skill="$(skill_dir_by_name dependency-upgrade-loop)" || fail "dependency-upgrade-loop skill not found"
  probe="$dep_skill/scripts/build-probe.sh"
  local out="$TMP_ROOT/build-probe.out"
  "$probe" --cmd true --quiet-pass --log "$TMP_ROOT/build-pass.log" >/dev/null
  expect_rc_quiet 1 "$probe" --cmd 'printf "compile error: nope\n"; exit 1' --log "$TMP_ROOT/build-fail.log"
  set +e
  "$probe" --cmd 'printf "SPECIALROOT\n"; exit 1' --grep SPECIALROOT --summary-lines 1 --log "$TMP_ROOT/build-grep.log" >"$out" 2>&1
  local rc=$?
  set -e
  [ "$rc" -eq 1 ] || fail "build-probe custom grep did not fail as expected"
  grep -q SPECIALROOT "$out" || fail "build-probe custom grep did not summarize matching line"
  pass "build-probe smoke tests"
}

smoke_bisect_runner() {
  local runner="$ROOT/skills/git-bisect-ai/scripts/bisect-run.sh"
  local repo="$TMP_ROOT/bisect-repo"
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  printf 'ok\n' > "$repo/file.txt"
  git -C "$repo" add file.txt
  git -C "$repo" commit -q -m init
  (
    cd "$repo"
    "$runner" --test true --log-dir "$TMP_ROOT/bisect-logs" >/dev/null
    test -f "$TMP_ROOT/bisect-logs/$(git rev-parse --short HEAD)-summary.json"
    expect_rc_quiet 1 "$runner" --test false
    expect_rc_quiet 1 "$runner" --test true --invert
    "$runner" --test false --invert >/dev/null
    expect_rc_quiet 125 "$runner" --setup false --test true
    expect_rc_quiet 1 "$runner" --setup false --test true --build-is-bug
    expect_rc_quiet 125 "$runner" --test 'exit 125' --allow-test-skip
  )
  pass "bisect-run smoke tests"
}

smoke_semantic_hook() {
  local installer="$ROOT/skills/semantic-commit-guard/scripts/install-hook.sh"
  local repo="$TMP_ROOT/hook-repo"
  git init -q "$repo"
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name Test
  mkdir -p "$repo/.git/hooks"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/.git/hooks/pre-commit"
  chmod +x "$repo/.git/hooks/pre-commit"
  (cd "$repo" && bash "$installer" >/dev/null)
  [ -f "$repo/.git/hooks/pre-commit.backup" ] || fail "existing hook was not backed up"

  printf 'const value = "hello";\n' > "$repo/app.js"
  git -C "$repo" add app.js
  (cd "$repo" && .git/hooks/pre-commit >/dev/null 2>&1)

  printf 'const token = "abcdefghijklmnopqrstuvwxyz";\n' > "$repo/app.js"
  git -C "$repo" add app.js
  set +e
  (cd "$repo" && .git/hooks/pre-commit >"$TMP_ROOT/hook-secret.out" 2>&1)
  local rc=$?
  set -e
  [ "$rc" -eq 1 ] || fail "semantic hook did not block token"
  grep -q 'value redacted' "$TMP_ROOT/hook-secret.out" || fail "semantic hook did not redact token output"
  ! grep -q 'abcdefghijklmnopqrstuvwxyz' "$TMP_ROOT/hook-secret.out" || fail "semantic hook leaked token value"

  printf 'API_KEY=abcdefghijklmnopqrstuvwxyz\n' > "$repo/.env"
  git -C "$repo" add .env
  expect_rc_quiet 1 bash -c "cd '$repo' && .git/hooks/pre-commit"
  pass "semantic hook smoke tests"
}

main() {
  cd "$ROOT"
  validate_skills
  validate_shell_syntax
  validate_demo_setup_syntax
  smoke_build_probe
  smoke_bisect_runner
  smoke_semantic_hook
  pass "all skill validations passed"
}

main "$@"
