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

### Prefer a directory over a URL

`copilot skill add <url>` materialises **only `SKILL.md`**, dropping each skill's
`references/`. No skill ships an executable any more — every command is a one-liner in the
skill text — so a URL install is degraded rather than broken. Use a directory or
`install.sh` and get the reference material too.

## 2a. Preferred: install as a plugin

Claude Code and Codex both read `.claude-plugin/`, so the manifests in this repo serve
both. This is the vendors' own mechanism: versioned, with `update` and `uninstall`, and it
never goes stale the way a copied directory does.

```sh
# Claude Code
claude plugin marketplace add TheSmuks/pike-agent-skills
claude plugin install pike-agent-skills@smuks-pike

# Codex — same manifests
codex plugin marketplace add https://github.com/TheSmuks/pike-agent-skills
codex plugin add pike-agent-skills@smuks-pike
```

GitHub Copilot has no plugin format; register the directory in place instead, which is
equally immune to drift:

```sh
copilot skill add <repo>/skills            # personal
copilot skill add --project <repo>/skills  # this project only
```

> **Do not run a plugin install and a directory install at the same time.** Both are
> discovered, so every skill loads twice and you pay for it on every request. Verified:
> with the plugin installed alongside `~/.claude/skills`, each skill appeared twice;
> removing one source returned it to once. Uninstall the directory copy first:
>
> ```sh
> <repo>/install.sh --uninstall claude
> ```

`claude plugin details pike-agent-skills@smuks-pike` reports the projected token cost per
skill, which is the honest way to decide what to keep enabled.

## 2b. Upgrading an existing install

Check what is already there before installing anything. `--list` reports each location
and whether its contents still match this checkout:

```sh
<repo>/install.sh --list
```

- `status: current` — nothing to do.
- `status: live (symlink ...)` — nothing to do, ever; it tracks the checkout.
- `status: STALE` — re-run `install.sh <target>`. It clears each skill directory before
  copying, so files that no longer exist upstream are removed rather than left behind.
- `status: unknown` — installed before drift tracking; re-install to get a fingerprint.

**A stale install is worse than a missing one.** The skill text is instructions; if it has
drifted from the tools and commands it describes, the agent follows the old text
confidently. One observed failure: a copy installed before a fix reported the fixed
behaviour as broken, and said so with full conviction.

Use `--link` on a checkout you intend to edit, and the problem cannot recur:

```sh
<repo>/install.sh --link claude
```

### Upgrading across 2.0.0

Releases before 2.0.0 shipped two executables inside the skills,
`pike-module-layout/pike-resolve.pike` and `pike-build-and-docs/pike-check.pike`. Both are
gone: measurement across 24 agent runs on three platforms showed agents reached for an
inline `pike -e` one-liner instead, and the skills now teach those commands directly.

If you are carrying instructions that call either script, discard them — the replacements
are in the skill text under *Resolving a Name to Its Source* and *Checking That Code
Compiles*. After upgrading, no `.pike` file should remain under any installed skill:

```sh
find <dest> -name '*.pike'      # expect no output
```

Any left over means the install predates 2.0.0 and was merged rather than replaced.
Re-run `install.sh`, or `--uninstall` first.

## 3. Verify — do not skip this

Installing is not the same as being discovered. Check that the host actually sees them:

```sh
copilot skill list | grep pike-      # Copilot CLI
claude -p "list your pike-* skills"  # Claude Code
```

You should see four: `pike-module-layout`, `pike-testing`, `pike-runtime-discovery`,
`pike-build-and-docs`.

Then confirm the reference material survived, since a URL install silently drops it:

```sh
find . "$HOME" -path "*pike-module-layout/references/*" 2>/dev/null | head -1
```

If that finds nothing, the skills are installed but degraded. Say so rather than
reporting success.

## 4. Report honestly

State which method you used, which skills the host now lists, and whether the tools came
with them. If discovery returned nothing, say the install did not take effect rather than
assuming it will work later.

## Related

`TheSmuks/roxen-agent-skills` installs the same way and is worth adding when the project
is a Roxen codebase. Roxen modules are Pike programs, so both apply together.
