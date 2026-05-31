#!/usr/bin/env bash
#
# install-hook.sh — install the Semantic Commit Guard pre-commit hook.
#
# The installed hook runs a FAST, DETERMINISTIC gate on staged content:
#   - leaked secrets / credentials (key-like assignments, private keys)
#   - accidentally staged secret files (.env, *.pem, id_rsa, *.key)
#   - oversized blobs that probably shouldn't be committed
# On a hit it exits nonzero, which aborts the commit. It does NOT attempt the
# semantic architecture/docs review — that's the agent's on-demand job. The
# hook just prints a reminder to run it.
#
# Re-running is safe: an existing pre-commit hook is backed up to
# pre-commit.backup, or the next numbered backup, before replacement.
# Bypass a commit with --no-verify.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "install-hook: not inside a git repository" >&2
  exit 1
}

HOOKS_DIR="$(git rev-parse --git-path hooks)"
mkdir -p "$HOOKS_DIR"
TARGET="$HOOKS_DIR/pre-commit"

if [ -e "$TARGET" ] && ! grep -q "semantic-commit-guard" "$TARGET" 2>/dev/null; then
  backup="$TARGET.backup"
  n=1
  while [ -e "$backup" ]; do
    backup="$TARGET.backup.$n"
    n=$((n + 1))
  done
  cp "$TARGET" "$backup"
  echo "install-hook: backed up existing pre-commit hook -> $backup"
fi

cat > "$TARGET" <<'HOOK'
#!/usr/bin/env bash
# semantic-commit-guard pre-commit hook (deterministic fast gate).
set -u

fail=0
note() { echo "  $*" >&2; }

# Files staged for commit (added/copied/modified/renamed), NUL-safe.
staged=()
while IFS= read -r -d '' f; do
  staged+=("$f")
done < <(git diff --cached --name-only --diff-filter=ACMR -z)

# 1) Secret-ish files staged by accident.
for f in "${staged[@]}"; do
  case "$f" in
    *.pem|*.key|*id_rsa|*id_dsa|*id_ecdsa|*id_ed25519|.env|*/.env|.env.*|*/.env.*)
      note "BLOCK  $f  — looks like a secret/credential file."
      fail=1;;
  esac
done

# 2) Secret-like content in the staged diff (added lines only).
SECRET_RE='(api[_-]?key|secret|passwd|password|token|aws_secret|client_secret)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/_+.\-]{16,}'
KEY_HEADER='-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----'
current_file=""
new_line=0
while IFS= read -r line; do
  case "$line" in
    "+++ b/"*)
      current_file="${line#+++ b/}"
      ;;
    "@@ "*)
      parsed=$(printf '%s\n' "$line" | sed -n 's/^@@ [^+]*+\([0-9][0-9]*\).*/\1/p')
      [ -n "$parsed" ] && new_line="$parsed"
      ;;
    "+"*)
      [ "${line:0:3}" = "+++" ] && continue
      body="${line:1}"
      location="$current_file"
      [ "$new_line" -gt 0 ] && location="$current_file:$new_line"
      if printf '%s' "$body" | grep -Eiq -e "$KEY_HEADER"; then
        note "BLOCK  $location  — private key material in staged diff."
        fail=1
      elif printf '%s' "$body" | grep -Eiq -e "$SECRET_RE"; then
        note "BLOCK  $location  — possible hardcoded credential (value redacted)."
        fail=1
      fi
      [ "$new_line" -gt 0 ] && new_line=$((new_line + 1))
      ;;
    " "*)
      [ "$new_line" -gt 0 ] && new_line=$((new_line + 1))
      ;;
  esac
done < <(git diff --cached -U0 --diff-filter=ACMR)

# 3) Large staged blobs (>1MB) — usually a mistake.
for f in "${staged[@]}"; do
  sz=$(git cat-file -s ":$f" 2>/dev/null || echo 0)
  if [ "$sz" -gt 1048576 ]; then
    note "BLOCK  $f  — ${sz} bytes (>1MB) staged; commit a reference, not the blob."
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "semantic-commit-guard: commit blocked by the deterministic gate." >&2
  echo "Rotate any exposed secret (unstaging does NOT make it safe), then re-stage." >&2
  echo "Override after review with: git commit --no-verify" >&2
  exit 1
fi

echo "semantic-commit-guard: fast gate passed. For the full semantic review" >&2
echo "(architecture, design-pattern, docs-sync), ask your agent to review the staged diff." >&2
exit 0
HOOK

chmod +x "$TARGET"
echo "install-hook: installed pre-commit guard at $TARGET"
echo "install-hook: bypass any single commit with 'git commit --no-verify'."
echo "install-hook: uninstall by removing $TARGET, or restore a backup named pre-commit.backup* from the hooks directory."
