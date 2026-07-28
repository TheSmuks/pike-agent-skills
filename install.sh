#!/bin/sh
# Install the Pike agent skills for any coding agent.
#
# Usage:
#   ./install.sh                  # auto-detect targets in the current project
#   ./install.sh claude           # ~/.claude/skills  (all projects)
#   ./install.sh claude-project   # ./.claude/skills
#   ./install.sh copilot          # ./.github/skills + ./.github/instructions
#   ./install.sh codex            # ./.agents/skills + ./AGENTS.md
#   ./install.sh agents           # ./AGENTS.md only (any AGENTS.md-aware agent)
#   ./install.sh /some/dir        # copy skills/ into an arbitrary directory
#
# Everything is plain markdown — copying by hand works just as well.

set -eu

SRC=$(cd "$(dirname "$0")" && pwd)
TARGET=${1:-auto}

copy_skills() {
  mkdir -p "$1"
  cp -r "$SRC/skills/." "$1/"
  echo "  skills      -> $1"
}

copy_agents_md() {
  if [ -f "$1/AGENTS.md" ] && ! grep -q "Pike Working Rules" "$1/AGENTS.md" 2>/dev/null; then
    printf '\n' >> "$1/AGENTS.md"
    cat "$SRC/AGENTS.md" >> "$1/AGENTS.md"
    echo "  rules       -> $1/AGENTS.md (appended)"
  elif [ ! -f "$1/AGENTS.md" ]; then
    cp "$SRC/AGENTS.md" "$1/AGENTS.md"
    echo "  rules       -> $1/AGENTS.md"
  else
    echo "  rules       -> $1/AGENTS.md (already present, skipped)"
  fi
}

copy_copilot_instructions() {
  mkdir -p "$1/.github/instructions"
  cp "$SRC/.github/instructions/pike.instructions.md" "$1/.github/instructions/"
  echo "  auto-rules  -> $1/.github/instructions/pike.instructions.md"
}

case "$TARGET" in
  claude)
    copy_skills "$HOME/.claude/skills"
    ;;
  claude-project)
    copy_skills "./.claude/skills"
    copy_agents_md "."
    ;;
  copilot)
    copy_skills "./.github/skills"
    copy_copilot_instructions "."
    ;;
  codex)
    copy_skills "./.agents/skills"
    copy_agents_md "."
    ;;
  agents)
    copy_agents_md "."
    ;;
  auto)
    echo "Auto-detecting agent directories in $(pwd)"
    found=0
    [ -d "./.claude" ]  && { copy_skills "./.claude/skills";  found=1; }
    [ -d "./.github" ]  && { copy_skills "./.github/skills";  copy_copilot_instructions "."; found=1; }
    [ -d "./.agents" ]  && { copy_skills "./.agents/skills";  found=1; }
    copy_agents_md "."
    [ "$found" -eq 0 ] && echo "  (no agent directories found — installed AGENTS.md only)"
    ;;
  /*|./*|../*)
    copy_skills "$TARGET"
    ;;
  *)
    echo "Unknown target: $TARGET" >&2
    sed -n '3,16p' "$0" >&2
    exit 1
    ;;
esac

echo
echo "Done. Verify the documented commands against your Pike with: $SRC/verify.sh"
