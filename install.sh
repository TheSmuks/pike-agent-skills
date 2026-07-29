#!/bin/sh
# Install the Pike agent skills for any coding agent.
#
# Everything here is plain markdown plus two Pike scripts — copying by hand works
# just as well. This exists to put them in the right place for your agent, to
# check they actually arrived, and to say so if they did not.

set -u

SRC=$(cd "$(dirname "$0")" && pwd)
SKILLS="$SRC/skills"
DRY=0
QUIET=0
LINK=0
ACTION=install
TARGET=""

# No skill ships a tool any more: both were replaced by the one-liners they
# wrapped, after measurement showed agents reach for a probe over a script.
# Kept as an empty list so re-introducing a tool only means naming it here.
BUNDLED=""

usage() {
  cat <<'EOF'
Usage: install.sh [options] [target]

Targets
  (none)            auto-detect from the current project and your home directory
  claude            ~/.claude/skills            Claude Code, all projects
  claude-project    ./.claude/skills            Claude Code, this project
  copilot           ./.github/skills            GitHub Copilot, this project
  copilot-user      ~/.copilot/skills           GitHub Copilot, all projects
  codex             ./.agents/skills            Codex, this project
  agents-user       ~/.agents/skills            any agent, all projects
  agents            AGENTS.md only              Cursor, Zed, Amp, anything AGENTS.md-aware
  <directory>       that directory

Options
  -n, --dry-run     show what would happen, change nothing
  -u, --uninstall   remove previously installed skills from the target
  -l, --list        list install locations, and flag any that have gone stale
  -L, --link        symlink the skills instead of copying them, so edits to this
                    checkout take effect immediately and no install can go stale.
                    Verified discovered on Claude Code, Codex and Copilot, at both
                    project and user scope. Do not use if this checkout may move
                    or be deleted — a copy is self-contained, a symlink is not.
  -q, --quiet       only report problems
  -h, --help        this text

Notes
  If the Copilot CLI is present, `copilot skill add <dir>` is a better route than
  copying: it registers this directory in place, so the bundled tools stay
  reachable and updates need no reinstall. This script will tell you when that
  applies. Never install these skills from a raw SKILL.md URL — that copies only
  the markdown and silently drops the tools.
EOF
}

# Content fingerprint of the skills tree. Deliberately not the git commit: the
# stale install that motivated this was produced by *uncommitted* edits, so a
# commit comparison reports "current" while the copy is already wrong.
skills_hash() {
  ( cd "$SKILLS" 2>/dev/null && find . -type f | LC_ALL=C sort |
    xargs cat 2>/dev/null | cksum | cut -d' ' -f1 ) 2>/dev/null || echo unknown
}

say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
run()  { if [ "$DRY" -eq 1 ]; then printf '  would: %s\n' "$*"; else "$@"; fi; }
die()  { printf 'install.sh: %s\n' "$*" >&2; exit 1; }

SKILL_NAMES=$(cd "$SKILLS" && ls -d */ 2>/dev/null | tr -d /)

# --------------------------------------------------------------------- copying
copy_skills() {
  dest=$1
  existing=0
  for s in $SKILL_NAMES; do [ -d "$dest/$s" ] && existing=1; done
  run mkdir -p "$dest"
  if [ "$LINK" -eq 1 ]; then
    # One symlink per skill directory rather than one for the whole tree, so a
    # dest shared with other skills keeps them.
    for s in $SKILL_NAMES; do
      run rm -rf "$dest/$s"
      run ln -s "$SKILLS/$s" "$dest/$s"
    done
  else
    # Clear each skill directory first. A plain merge-copy leaves behind files
    # that no longer exist in the source — upgrading across the removal of a
    # bundled tool left the old executable sitting next to the new SKILL.md.
    for s in $SKILL_NAMES; do run rm -rf "$dest/$s"; done
    run cp -r "$SKILLS/." "$dest/"
  fi
  # A provenance stamp, so a later reader can tell where these came from and
  # whether they are stale. gh skill records this in frontmatter; we cannot
  # rewrite the skills, so it goes beside them.
  if [ "$DRY" -eq 0 ]; then
    { printf 'source: %s\n' "$SRC"
      printf 'origin: https://github.com/TheSmuks/pike-agent-skills\n'
      printf 'commit: %s\n' "$(cd "$SRC" && git rev-parse --short HEAD 2>/dev/null || echo unknown)"
      printf 'mode: %s\n' "$([ "$LINK" -eq 1 ] && echo symlink || echo copy)"
      printf 'hash: %s\n' "$(skills_hash)"
      printf 'installed: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$dest/.pike-agent-skills"
  fi
  if [ "$DRY" -eq 1 ]; then
    say "  would $([ "$existing" -eq 1 ] && echo update || echo install) -> $dest"
  else
    say "  $([ "$existing" -eq 1 ] && echo updated || echo installed) -> $dest"
  fi
}

copy_agents_md() {
  dest=$1
  if [ -f "$dest/AGENTS.md" ] && grep -q "Pike Working Rules" "$dest/AGENTS.md" 2>/dev/null; then
    say "  rules     -> $dest/AGENTS.md (already present)"
  elif [ -f "$dest/AGENTS.md" ]; then
    run sh -c "printf '\n' >> '$dest/AGENTS.md'; cat '$SRC/AGENTS.md' >> '$dest/AGENTS.md'"
    say "  rules     -> $dest/AGENTS.md (appended)"
  else
    run cp "$SRC/AGENTS.md" "$dest/AGENTS.md"
    say "  rules     -> $dest/AGENTS.md"
  fi
}

# Claude Code reads CLAUDE.md and ignores AGENTS.md — verified by planting a
# marker in each and asking: only the CLAUDE.md marker came back, with both
# files present. Writing AGENTS.md for a Claude target is dead weight.
copy_claude_md() {
  dest=$1
  if [ -f "$dest/CLAUDE.md" ] && grep -q "Pike Working Rules" "$dest/CLAUDE.md" 2>/dev/null; then
    say "  rules     -> $dest/CLAUDE.md (already present)"
  elif [ -f "$dest/CLAUDE.md" ]; then
    run sh -c "printf '\n' >> '$dest/CLAUDE.md'; cat '$SRC/AGENTS.md' >> '$dest/CLAUDE.md'"
    say "  rules     -> $dest/CLAUDE.md (appended)"
  else
    run cp "$SRC/AGENTS.md" "$dest/CLAUDE.md"
    say "  rules     -> $dest/CLAUDE.md"
  fi
}

copy_copilot_instructions() {
  run mkdir -p "$1/.github/instructions"
  run cp "$SRC/.github/instructions/pike.instructions.md" "$1/.github/instructions/"
  say "  auto-rules -> $1/.github/instructions/pike.instructions.md"
}

# ------------------------------------------------------------------ verifying
# Copying is not the same as being usable. Check the tools came too, and tell the
# host's own lister to confirm discovery where we can.
verify() {
  dest=$1
  [ "$DRY" -eq 1 ] && return 0
  missing=""
  for t in $BUNDLED; do
    [ -f "$dest/$t" ] || missing="$missing $t"
  done
  if [ -n "$missing" ]; then
    printf '\n  WARNING: bundled tools did not arrive:%s\n' "$missing" >&2
    printf '  The skills will reference files that are not there.\n' >&2
    return 1
  fi
  say "  verified  -> $(printf '%s' "$SKILL_NAMES" | wc -w) skills, tools present"
  return 0
}

report_discovery() {
  [ "$DRY" -eq 1 ] && return 0
  if command -v copilot >/dev/null 2>&1 && copilot skill --help >/dev/null 2>&1; then
    n=$(copilot skill list 2>/dev/null | grep -c 'pike-' || true)
    [ "${n:-0}" -gt 0 ] && say "  copilot sees $n pike-* skill(s)"
  fi
}

suggest_native() {
  if command -v copilot >/dev/null 2>&1 && copilot skill --help >/dev/null 2>&1; then
    say ""
    say "  tip: the Copilot CLI is installed. Registering this directory keeps the"
    say "       tools reachable and picks up updates without reinstalling:"
    say "         copilot skill add $SKILLS"
  fi
}

do_uninstall() {
  dest=$1
  removed=0
  for s in $SKILL_NAMES; do
    if [ -d "$dest/$s" ]; then run rm -rf "$dest/$s"; removed=$((removed + 1)); fi
  done
  [ -f "$dest/.pike-agent-skills" ] && run rm -f "$dest/.pike-agent-skills"
  say "  removed $removed skill(s) from $dest"
}

do_list() {
  found=0
  cur=$(cd "$SRC" && git rev-parse --short HEAD 2>/dev/null || echo unknown)
  curh=$(skills_hash)
  for d in "$HOME/.claude/skills" "$HOME/.copilot/skills" "$HOME/.agents/skills" \
           "./.claude/skills" "./.github/skills" "./.agents/skills"; do
    [ -f "$d/.pike-agent-skills" ] || continue
    found=1
    printf '%s\n' "$d"
    sed 's/^/    /' "$d/.pike-agent-skills"
    # A copied install silently rots the moment this checkout moves on, and a
    # stale copy is worse than none: the agent reports fixed behaviour as broken.
    was=$(sed -n 's/^commit: //p' "$d/.pike-agent-skills")
    wash=$(sed -n 's/^hash: //p' "$d/.pike-agent-skills")
    mode=$(sed -n 's/^mode: //p' "$d/.pike-agent-skills")
    if [ "$mode" = symlink ]; then
      printf '    status: live (symlink — tracks this checkout)\n'
    elif [ -z "$wash" ]; then
      printf '    status: unknown — installed before drift tracking; re-run install.sh\n'
    elif [ "$wash" != "$curh" ]; then
      printf '    status: STALE — content differs from this checkout\n'
      printf '            installed %s, source now %s\n' "${was:-?}" "$cur"
      printf '            re-run install.sh (add --link to stop this recurring)\n'
    else
      printf '    status: current\n'
    fi
  done
  [ "$found" -eq 0 ] && echo "these skills are not installed anywhere this script looks"
  return 0
}

# ------------------------------------------------------------------ arguments
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)      usage; exit 0 ;;
    -n|--dry-run)   DRY=1 ;;
    -L|--link)      LINK=1 ;;
    -q|--quiet)     QUIET=1 ;;
    -u|--uninstall) ACTION=uninstall ;;
    -l|--list)      ACTION=list ;;
    -*)             die "unknown option: $1 (try --help)" ;;
    *)              [ -n "$TARGET" ] && die "more than one target given"; TARGET=$1 ;;
  esac
  shift
done

[ -d "$SKILLS" ] || die "no skills/ directory beside this script"
[ "$ACTION" = list ] && { do_list; exit 0; }
[ "$DRY" -eq 1 ] && say "(dry run — nothing will be written)"

resolve_dest() {
  case "$1" in
    claude)         echo "$HOME/.claude/skills" ;;
    claude-project) echo "./.claude/skills" ;;
    copilot)        echo "./.github/skills" ;;
    copilot-user)   echo "$HOME/.copilot/skills" ;;
    codex)          echo "./.agents/skills" ;;
    agents-user)    echo "$HOME/.agents/skills" ;;
    /*|./*|../*)    echo "$1" ;;
    *)              echo "" ;;
  esac
}

if [ "$ACTION" = uninstall ]; then
  if [ -z "$TARGET" ]; then
    for d in "$HOME/.claude/skills" "$HOME/.copilot/skills" "$HOME/.agents/skills" \
             "./.claude/skills" "./.github/skills" "./.agents/skills"; do
      [ -d "$d" ] && do_uninstall "$d"
    done
  else
    dest=$(resolve_dest "$TARGET")
    [ -n "$dest" ] || die "unknown target: $TARGET (try --help)"
    do_uninstall "$dest"
  fi
  exit 0
fi

rc=0
case "${TARGET:-auto}" in
  agents)
    copy_agents_md "."
    ;;
  auto)
    say "Auto-detecting agent locations"
    found=0
    wrote_rules=0
    for pair in ".claude:./.claude/skills" ".copilot:./.copilot/skills" \
                ".agents:./.agents/skills"; do
      d=${pair%%:*}; dest=${pair#*:}
      [ -d "./$d" ] || continue
      copy_skills "$dest"; verify "$dest" || rc=1; found=1
      case "$d" in
        .claude) copy_claude_md "."; wrote_rules=1 ;;
        .agents) copy_agents_md "."; wrote_rules=1 ;;
      esac
    done
    if [ -d "./.github" ]; then
      copy_skills "./.github/skills"; verify "./.github/skills" || rc=1
      copy_copilot_instructions "."; found=1; wrote_rules=1
    fi
    for pair in "$HOME/.claude:$HOME/.claude/skills" "$HOME/.copilot:$HOME/.copilot/skills" \
                "$HOME/.agents:$HOME/.agents/skills"; do
      d=${pair%%:*}; dest=${pair#*:}
      [ -d "$d" ] && { copy_skills "$dest"; verify "$dest" || rc=1; found=1; }
    done
    # Only if nothing platform-specific was written, so the same body is never
    # loaded twice: Copilot reads AGENTS.md *and* its own instructions file.
    [ "$wrote_rules" -eq 0 ] && copy_agents_md "."
    [ "$found" -eq 0 ] && say "  (no agent directories found — installed AGENTS.md only)"
    ;;
  *)
    dest=$(resolve_dest "$TARGET")
    [ -n "$dest" ] || die "unknown target: $TARGET (try --help)"
    copy_skills "$dest"
    verify "$dest" || rc=1
    case "$TARGET" in
      claude-project) copy_claude_md "." ;;
      codex)          copy_agents_md "." ;;
      copilot)        copy_copilot_instructions "." ;;
    esac
    ;;
esac

report_discovery
suggest_native

if [ "$rc" -ne 0 ]; then
  printf '\ninstall.sh: finished with warnings — see above\n' >&2
  exit 1
fi
say ""
say "Done. Check the documented commands against your Pike with: $SRC/verify.sh"
exit 0
