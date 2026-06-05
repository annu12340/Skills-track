#!/usr/bin/env bash
#
# install.sh — zero-config installer for Repo Rescue Rangers skills.
#
# Detects your agent tool automatically and copies the three skills into the
# right directory. Works from a local clone or when piped from a URL.
#
# Usage (local):
#   bash scripts/install.sh [TARGET_DIR]
#
# Usage (remote — pipe from URL):
#   curl -fsSL <raw-url>/scripts/install.sh | bash -s -- /path/to/your/project
#
# Override:
#   SKILL_ROOT=/path/to/repo bash scripts/install.sh /path/to/project
#   AGENT=codex bash scripts/install.sh /path/to/project
#
# Supported agents (auto-detected, first match wins):
#   Claude Code  →  TARGET/.claude/skills/
#   Cursor       →  TARGET/.cursor/skills/
#   Codex        →  TARGET/.codex/skills/

set -euo pipefail

SKILLS=(git-bisect-ai semantic-commit-guard dependency-upgrade-loop)

_info()  { printf '\033[0;34m[info]\033[0m  %s\n' "$*"; }
_ok()    { printf '\033[0;32m[ ok ]\033[0m  %s\n' "$*"; }
_warn()  { printf '\033[0;33m[warn]\033[0m  %s\n' "$*"; }
_die()   { printf '\033[0;31m[err ]\033[0m  %s\n' "$*" >&2; exit 1; }

# Resolve the skills/ source directory.
# Priority: SKILL_ROOT env var > script's parent dir > walk up from PWD.
find_skills_src() {
  if [ -n "${SKILL_ROOT:-}" ] && [ -d "${SKILL_ROOT}/skills" ]; then
    printf '%s/skills' "$SKILL_ROOT"; return
  fi
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || script_dir="$PWD"
  local repo_root
  repo_root="$(dirname "$script_dir")"
  if [ -d "$repo_root/skills" ]; then
    printf '%s/skills' "$repo_root"; return
  fi
  # Walk up from PWD for users who `cd` into the repo before running
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    [ -d "$dir/skills" ] && { printf '%s/skills' "$dir"; return; }
    dir="$(dirname "$dir")"
  done
  printf ''
}

# Detect the destination skills directory for the given project root.
# Priority: AGENT env var > first agent dir found > default to Claude Code.
detect_dest() {
  local target="$1"
  if [ -n "${AGENT:-}" ]; then
    case "$AGENT" in
      claude|claude-code) printf '%s/.claude/skills' "$target"; return;;
      cursor)             printf '%s/.cursor/skills' "$target"; return;;
      codex)              printf '%s/.codex/skills'  "$target"; return;;
      *) _warn "Unknown AGENT='$AGENT'; falling back to auto-detect";;
    esac
  fi
  for dir in .claude .cursor .codex; do
    if [ -d "$target/$dir" ]; then
      printf '%s/%s/skills' "$target" "$dir"; return
    fi
  done
  # Nothing found — default to Claude Code.
  printf '%s/.claude/skills' "$target"
}

TARGET="${1:-$PWD}"
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || _die "Target directory not found: ${1:-$PWD}"

SKILLS_SRC="$(find_skills_src)"
[ -n "$SKILLS_SRC" ] || _die "Cannot locate the skills/ directory.
Clone the repo first and run from inside it, or set SKILL_ROOT:
  git clone <repo-url>
  SKILL_ROOT=\$PWD/repo-rescue-rangers bash repo-rescue-rangers/scripts/install.sh /your/project"

DEST="$(detect_dest "$TARGET")"
AGENT_LABEL="${DEST#$TARGET/}"   # e.g. ".claude/skills"
AGENT_LABEL="${AGENT_LABEL%%/*}" # e.g. ".claude"

echo ""
_info "Repo Rescue Rangers — installer"
_info "Skills source : $SKILLS_SRC"
_info "Target project: $TARGET"
_info "Agent dir     : $AGENT_LABEL  (override with AGENT=cursor|claude|codex)"
echo ""

mkdir -p "$DEST"
installed=0

for skill in "${SKILLS[@]}"; do
  src="$SKILLS_SRC/$skill"
  [ -d "$src" ] || { _warn "Skill not found, skipping: $skill"; continue; }
  if [ -d "$DEST/$skill" ]; then
    rm -rf "$DEST/$skill"
  fi
  cp -r "$src" "$DEST/"
  _ok "$skill"
  installed=$((installed + 1))
done

echo ""
if [ "$installed" -eq 0 ]; then
  _die "No skills were installed — check SKILLS_SRC: $SKILLS_SRC"
fi

_ok "$installed skill(s) installed into $DEST"
echo ""
_info "Restart your agent session if skills are not picked up immediately."
_info ""
_info "Run a demo to verify:"
_info "  bash demo-repos/bisect-demo/setup.sh"
_info "  bash demo-repos/commit-guard-demo/setup.sh"
_info "  bash demo-repos/dependency-upgrade-loop-demo/setup.sh"
echo ""
