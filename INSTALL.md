# Installing these skills (instructions for an agent)

You are an AI coding agent and someone asked you to install these skills. Work out which
method fits the host you are running in, run it, then verify. Do not guess — the detection
commands below are cheap.

## 1. Detect what you have

```sh
command -v copilot && copilot skill --help >/dev/null 2>&1 && echo "copilot-cli"
gh skill --help >/dev/null 2>&1 && echo "gh-skill"
[ -d "$HOME/.claude" ]   && echo "claude"
[ -d "$HOME/.copilot" ]  && echo "copilot-dirs"
[ -d "$HOME/.agents" ]   && echo "agents-dirs"
ls .github/skills .claude/skills .agents/skills 2>/dev/null
```

## 2. Pick a method

Take the first that applies.

| If | Use | Why |
|----|-----|-----|
| `copilot skill` exists | `copilot skill add <repo>/skills` | registers the directory, so bundled tools stay reachable |
| `gh skill` exists | `gh skill install TheSmuks/pike-agent-skills` | copies the whole skill folder, tools included |
| neither | `<repo>/install.sh <target>` | plain copy; targets listed in `--help` |

`install.sh` targets: `claude`, `claude-project`, `copilot`, `copilot-user`, `codex`,
`agents`, `agents-user`, or a directory path. `install.sh` with no argument auto-detects.

### Where each platform actually looks

Measured, not assumed — a canary skill holding an unguessable token was installed at each
location and each agent was asked for the token. A negative control confirmed no agent can
produce it without the skill. All twelve combinations were discovered:

| Platform | Project scope | User scope | Symlink OK |
|---|---|---|---|
| Claude Code | `.claude/skills` | `~/.claude/skills` | yes |
| Codex | `.agents/skills` | `~/.agents/skills` | yes |
| GitHub Copilot | `.github/skills` | `~/.copilot/skills` | yes |

### Prefer `--link` when installing from a checkout you edit

A copy is a snapshot. Edit the source afterwards and every copy is silently wrong — and a
stale skill is worse than no skill, because the agent will confidently report fixed
behaviour as broken. `--link` symlinks each skill directory instead, so installs track the
checkout and cannot rot:

```bash
./install.sh --link claude
./install.sh --list          # flags any install whose content has drifted
```

Use a plain copy instead when the checkout may move or be deleted — a copy is
self-contained, a symlink is not. `--list` compares a content fingerprint rather than the
git commit, so it catches drift from uncommitted edits too.

### Do not install from a URL

`copilot skill add <url>` materialises **only `SKILL.md`**. One of these skills ships a
tool next to its `SKILL.md`:

```
skills/pike-build-and-docs/pike-check.pike
```

A URL install leaves those behind, and the skill then tells you to run a file that is not
there. Verified: it produces a directory containing `SKILL.md` and nothing else. Use a
directory or `install.sh`.

## 3. Verify — do not skip this

Installing is not the same as being discovered. Check that the host actually sees them:

```sh
copilot skill list | grep pike-      # Copilot CLI
claude -p "list your pike-* skills"  # Claude Code
```

You should see four: `pike-module-layout`, `pike-testing`, `pike-runtime-discovery`,
`pike-build-and-docs`.

Then confirm a bundled tool survived the install, since that is the part most likely to be
missing:

```sh
find . "$HOME" -path "*pike-build-and-docs/pike-check.pike" 2>/dev/null | head -1
```

If that finds nothing, the skills are installed but degraded — the instructions will
reference a tool the user does not have. Say so rather than reporting success.

## 4. Report honestly

State which method you used, which skills the host now lists, and whether the tools came
with them. If discovery returned nothing, say the install did not take effect rather than
assuming it will work later.

## Related

`TheSmuks/roxen-agent-skills` installs the same way and is worth adding when the project
is a Roxen codebase. Roxen modules are Pike programs, so both apply together.
