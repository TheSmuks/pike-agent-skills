# pike-agent-skills

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Pike 8.0](https://img.shields.io/badge/pike-8.0.1116-informational.svg)](https://pike.lysator.liu.se/)
[![Verified](https://img.shields.io/badge/checks-72%2F72_passing-brightgreen.svg)](verify.sh)
[![Agents](https://img.shields.io/badge/agents-Copilot_%7C_Codex_%7C_Claude-8957e5.svg)](#install)

Agent skills for developing in [Pike](https://pike.lysator.liu.se/) — module layout,
testing, runtime discovery, and builds. Tool-agnostic: GitHub Copilot, Codex, Claude, and
anything that reads `AGENTS.md` or `SKILL.md`.

**Stock Pike only.** Nothing here needs a third-party package, formatter, or test
framework. Every command was executed against Pike 8.0.1116 before being written down,
and `./verify.sh` re-runs all of them.

## Install

**Working with an agent?** Point it at [`INSTALL.md`](INSTALL.md) — *"read INSTALL.md and
install these skills"*. It detects the host, picks the right method, and verifies
discovery afterwards, which matters because installing and being discovered are not the
same thing.

Doing it yourself:

```bash
./install.sh --help          # targets and options
./install.sh --dry-run       # see what would happen
./install.sh claude          # or: codex, copilot, agents-user, ...
./install.sh --list          # where is it installed, and from which commit
./install.sh --uninstall     # remove it again
```

The installer verifies after copying — it fails loudly if the bundled tools did not
arrive, rather than leaving skills that reference files you do not have — and records
provenance, so `--list` reports which commit an install came from.

Verified end to end — after installing, all three agents on hand list every skill and the
bundled tools run from where they land:

| Agent | Verified |
|-------|----------|
| Claude Code 2.1.220 | lists all 4 skills |
| Codex 0.143.0 | lists all 4 skills |
| GitHub Copilot CLI 1.0.75 | lists all 4 skills |

### Copilot CLI

`copilot skill add` takes a directory, a file, or a URL — **and the difference matters
here**, because these skills bundle tools next to their `SKILL.md`:

```bash
copilot skill add /path/to/pike-agent-skills/skills     # registers the directory
```

| Source | Bundled tools |
|--------|---------------|
| `copilot skill add <directory>` | **included** — the directory is registered in place |
| `copilot skill add <url>` | **lost** — only `SKILL.md` is materialised |

Verified: a URL install produced `~/.copilot/skills/pike-module-layout/SKILL.md` and
nothing else — the `references/` material is dropped. No skill ships an executable, so a
URL install is degraded rather than broken. Use the directory form, or `install.sh`.

If your `gh` is recent enough to have the `skill` command, that is GitHub's own installer
and handles target directories, version pinning and provenance for you:

```bash
gh skill install TheSmuks/pike-agent-skills --pin v1.2.0
```

> `gh skill` is newer than gh 2.46.0, which does not have it. Check with
> `gh skill --help`; if it is missing, use `install.sh` — that is the path verified here.

The tools ship **inside** the skills that document them, so they arrive with the install
and need no separate step:

```
```

### install.sh

```bash
git clone https://github.com/TheSmuks/pike-agent-skills
cd your-project
../pike-agent-skills/install.sh          # auto-detects what you use
```

| Command | Installs to | For |
|---------|-------------|-----|
| `install.sh copilot` | `./.github/skills/` + `./.github/instructions/` | GitHub Copilot, this project |
| `install.sh copilot-user` | `~/.copilot/skills/` | Copilot, all projects |
| `install.sh claude` | `~/.claude/skills/` | Claude, all projects |
| `install.sh claude-project` | `./.claude/skills/` + `AGENTS.md` | Claude, this project |
| `install.sh codex` | `./.agents/skills/` + `AGENTS.md` | Codex |
| `install.sh agents-user` | `~/.agents/skills/` | any agent, all projects |
| `install.sh agents` | `AGENTS.md` only | Cursor, Zed, Amp, anything AGENTS.md-aware |
| `install.sh /path/to/dir` | that directory | anything else |

Re-running is safe — `AGENTS.md` is appended to once and skipped thereafter.

Tested on this machine: `claude-project`, `codex`, `copilot` and `agents` all install
cleanly, and the tools execute from their installed location. The Copilot layout follows
GitHub's documented convention but was not exercised locally — no Copilot CLI installed
here to confirm it with.

### What each piece is for

| File | Role |
|------|------|
| `skills/*/SKILL.md` | On-demand skills. Portable — Claude, Copilot, and Codex all use `SKILL.md` in a named directory |
| `AGENTS.md` | Always-on rules digest in the cross-tool `AGENTS.md` convention |
| `.github/instructions/pike.instructions.md` | The same rules with Copilot `applyTo` globs, so they auto-apply to `.pike`/`.pmod`/`.cmod`/`testsuite` files |

`AGENTS.md` and the Copilot instructions body are the same text; `verify.sh` fails if they
ever drift apart.

For Claude specifically, `npx skills add TheSmuks/pike-agent-skills` also works.

## Skills

| Skill | Covers |
|-------|--------|
| [`pike-module-layout`](skills/pike-module-layout/) | `.pike` vs `.pmod`, dirnode resolution, dotted namespaces, module path, `inherit` vs `import` |
| [`pike-testing`](skills/pike-testing/) | `Tools.Testsuite`, `testsuite.in` and m4, `pike -x test_pike`, two m4-free paths, exit codes |
| [`pike-runtime-discovery`](skills/pike-runtime-discovery/) | `pike -e` probes, `hilfe`, `indices`/`_typeof`/`resolv`/`Program.defined`, `describe_backtrace` |
| [`pike-build-and-docs`](skills/pike-build-and-docs/) | `pike -x module`, `precompile` for `.cmod`, the autodoc pipeline |

These cover **workflow**. For Pike syntax, types, and standard-library semantics, pair
them with a language reference skill — that ground is deliberately not repeated here.

## Does this code compile?

```bash
pike -e 'compile_file("Consumer.pike");'      # exit 0 clean, non-zero on error
pike -M . -e 'compile_file("Consumer.pike");' # add -M for the project's own modules
```

`compile_file()` reports `file:line:` on stderr and sets a usable exit code, so it drops
straight into CI. Two lookalikes do **not** check anything, and both were reached for by
real agents asked to check a file: `pike -c file.pike` (`-c` is not a Pike flag — it
prints `Unknown option -c.` and exits 1 having compiled nothing) and `pike file.pike`
(which *runs* the file and fails with `has no main()`).

Sweeping a tree needs one detail — **`-type f`**:

```bash
for f in $(find . -type f \( -name '*.pike' -o -name '*.pmod' \) | sort); do
  pike -M . -e "compile_file(\"$f\");" >/dev/null 2>&1 || echo "FAIL $f"
done
```

`.pmod` names both files and directories, and a directory handed to `compile_file()`
throws `Bad argument 1 to cpp()`. Omit `-type f` and a tree with one real error reports
four.

**Roxen is handled honestly.** Roxen's runtime is *bootstrapped*, not importable:
`roxenloader` installs ~145 constants and swaps in `roxen_master.pike` before `Roxen.pmod`
or `RXML.pmod` will compile. Stock Pike cannot resolve `Roxen.*` on its own, so a Roxen
module reporting `Undefined identifier MODULE_LOCATION` is not broken — it is unverified.
Use the installation's own `./start --program` to check it, and report anything else as
unverified rather than failing.

## Resolving a name to its source

The skill teaches one-liners rather than shipping a resolver. Agents reach for
`pike -e` over invoking a script, and a script that assumes too much is worse than none.

```bash
pike -e 'write("%O\n", Program.defined(Stdio.File));'
# "/usr/local/pike/8.0.1116/lib/modules/Stdio.pmod/module.pmod:181"
```

A filesystem walk stops at the enclosing module, so it cannot tell `Stdio.File` from
`Stdio.Buffer`, and reports every C-implemented symbol as missing. `Program.defined()`
gives `file:line` for the class itself.

The trap worth knowing: a name that arrived through an `import` does not resolve bare.

```pike
import A;
int f() { return B()->x(); }        // B is A.B
```

```bash
pike -M . -e 'write("%O\n", undefinedp(master()->resolv("B")));'    # 1 — undefined
pike -M . -e 'write("%O\n", Program.defined(master()->resolv("A.B")));'
```

Resolve the bare name and you conclude the module is missing while the code compiles
fine. Read the file's `import`/`inherit` lines and retry qualified. `verify.sh` checks
every one of these commands against the real Pike.

## Three things Pike tooling usually gets wrong

**A `.pmod` directory is a module because of its extension.** `module.pmod` is optional —
it adds the module's own symbols. Tools that treat it as a required marker miss most of
the Pike standard library, `Protocols.pmod` included.

```bash
mkdir -p /tmp/t/NoMarker.pmod
echo 'string hi() { return "resolved"; }' > /tmp/t/NoMarker.pmod/Greeter.pike
pike -M /tmp/t -e 'write("%s\n", NoMarker.Greeter()->hi());'   # → resolved
```

**`pike -x test_pike testsuite.in` silently passes.** `testsuite.in` is m4 source and the
runner does not expand it. Pointed at the raw file it prints `Total tests: 0` and exits
`0` — a green run that executed nothing. Expand with `mktestsuite` first, or write the
expanded `testsuite` file directly and skip m4 entirely.

**Pike ships a package manager** — `pike -x monger`. What it lacks is a per-project
manifest or lockfile. Those are different claims, and conflating them leads to wrong
dependency handling.

## Verify

```bash
./verify.sh
```

Runs every documented command against your local Pike and exits non-zero if any
behaviour no longer holds.

```
passed: 67   failed: 0
```

Run it after a Pike upgrade — it is the fastest way to find out whether these skills are
still telling the truth.

## Does it actually help?

[`EVAL.md`](EVAL.md) is a 7-probe hand-run check of whether an agent's *behaviour* changes
with the skills installed. Each probe targets a misconception where the no-skill answer is
wrong and, in several cases, silently green. `verify.sh` proves the commands; `EVAL.md`
probes the behaviour.

## Related

- [roxen-agent-skills](https://github.com/TheSmuks/roxen-agent-skills) — Roxen WebServer skills, verified against real Roxen source. Roxen modules are Pike programs, so both are useful together
- [spec-kit-brownfield-pike](https://github.com/TheSmuks/spec-kit-brownfield-pike) — Spec Kit brownfield extension with a Pike profile built on the same verified findings

## License

MIT
