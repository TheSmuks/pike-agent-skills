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

### Do not install from a URL

`copilot skill add <url>` materialises **only `SKILL.md`**. Two of these skills ship a tool
next to their `SKILL.md`:

```
skills/pike-module-layout/pike-resolve.pike
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
find . "$HOME" -path "*pike-module-layout/pike-resolve.pike" 2>/dev/null | head -1
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
