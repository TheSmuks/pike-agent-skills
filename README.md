# pike-agent-skills

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Pike 8.0](https://img.shields.io/badge/pike-8.0.1116-informational.svg)](https://pike.lysator.liu.se/)
[![Verified](https://img.shields.io/badge/checks-67%2F67_passing-brightgreen.svg)](verify.sh)
[![Agents](https://img.shields.io/badge/agents-Copilot_%7C_Codex_%7C_Claude-8957e5.svg)](#install)

Agent skills for developing in [Pike](https://pike.lysator.liu.se/) — module layout,
testing, runtime discovery, and builds. Tool-agnostic: GitHub Copilot, Codex, Claude, and
anything that reads `AGENTS.md` or `SKILL.md`.

**Stock Pike only.** Nothing here needs a third-party package, formatter, or test
framework. Every command was executed against Pike 8.0.1116 before being written down,
and `./verify.sh` re-runs all of them.

## Install

```bash
./install.sh claude        # or: codex, copilot, agents-user, ...
```

Verified end to end: after installing, **Claude Code 2.1.220** and **Codex 0.143.0** both
list all four skills, and the bundled tools run from where they land.

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
skills/pike-module-layout/pike-resolve.pike     trace inherit/import/include chains
skills/pike-build-and-docs/pike-check.pike      compile-check a file or a whole tree
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

## Tool: does this code compile?

```bash
pike tools/pike-check.pike src/            # whole tree, recursively
pike tools/pike-check.pike --roxen=/opt/roxen mymodule.pike
```

[`tools/pike-check.pike`](tools/pike-check.pike) compiles Pike code — resolving inherits,
imports and includes — and reports every error with `file:line`. Point it at a directory
and it walks the tree.

**Roxen is handled honestly.** Roxen's runtime is *bootstrapped*, not importable:
`roxenloader` installs ~145 constants and swaps in `roxen_master.pike` before `Roxen.pmod`
or `RXML.pmod` will compile. Stock Pike cannot resolve `Roxen.*` on its own.

On the first run over Roxen code it looks for an install (common locations, `ROXEN_DIR`,
`--roxen`), and if it finds none it asks once — on a terminal only — then remembers the
answer in `$XDG_CONFIG_HOME/pike-agent-skills/roxen-path`. Declining is remembered too, so
it never nags. In CI, where stdin is not a terminal, it never prompts.

With `--roxen=<dir>` pointing at a real install, compilation is delegated to its own
`./start --program`, which supplies Roxen's Pike, module path and include path — nothing
is stubbed. That resolves `#include <module.h>` and locates `Roxen.pmod`.

It does **not** boot the Roxen runtime: `--program` replaces `roxenloader.pike` rather
than running after it, so the master swap and the constants it installs never happen.
Code calling `Roxen.*` therefore still reports as unverified — `Roxen.pmod` itself needs
that runtime. Measured both ways in a container with a real Roxen 6.3 and Pike 8.0.1116: with
roxenloader running `Roxen.pmod` compiles, under `--program` it does not. See
[roxen-agent-skills/lab](https://github.com/TheSmuks/roxen-agent-skills/tree/main/lab).

Roxen references that cannot be checked are reported as **unverified warnings** and never
silently accepted:

```
!! handler.pike: 1 Roxen reference could NOT be verified: Roxen
     handler.pike:3: Undefined identifier Roxen.
   No Roxen install found. Pass --roxen=<dir>, or set ROXEN_DIR.
   These are NOT confirmed correct — this check was incomplete.

INCOMPLETE: your code compiled, but 1 Roxen reference went unverified.
```

**Root causes first.** An undefined type in a signature cascades: Pike loses the return
type too, so one bad identifier yields "Illegal program identifier", "Must return a value
for a non-void function", "Expected: mixed", and so on. Verified in the lab — a single
undefined `Gz` at `Roxen.pmod:1064` produced dozens of these. Only the root is shown by
default, with the rest behind a count (`--all` shows everything):

```
handler.pike:1:1: error: Undefined identifier UnknownType.
  +5 follow-on errors hidden — fix the undefined identifier above first (--all to show)
```

Diagnostics are absolute `file:line:col: message`, which editors and terminals turn into
clickable links, and are coloured when writing to a terminal (`--color`/`--no-color`,
honours `NO_COLOR`).

**Validated against real source.** Run over Pike 8.0.1116's own standard library — its
matching compiler — **535 of 545 modules compile clean**. Of the 10 that do not, 7 need
GTK bindings that are not built here and 3 are `.pmod` submodules whose sibling references
resolve only through their parent module, a documented limitation of checking a submodule
standalone.

Exit status distinguishes the three outcomes: `0` clean, `1` real errors in your code,
`2` compiled but Roxen went unchecked. A pass is never claimed for code that wasn't
actually checked.

## Tool: trace a chain to its sources

```bash
pike -M . tools/pike-resolve.pike Leaf.pike
```

```
# runtime inherit chain (authoritative)
Leaf.pike
    Middle.pike
      Base.pike
      Lib.pmod/Mixin.pike

# static inherit chain (as written in source)
Leaf.pike
  inherit "Middle" -> Middle.pike
      inherit "Base" -> Base.pike
      inherit Lib.Mixin -> Lib.pmod/Mixin.pike
```

Given any `inherit` or `import`, [`tools/pike-resolve.pike`](tools/pike-resolve.pike)
traces it deterministically to the files it comes from, using Pike's own resolver.

It runs two passes because they see different things: the **runtime** pass compiles the
target and walks `Program.inherit_tree()` — authoritative, but blind to `import`, which
leaves no runtime trace. The **static** pass tokenises with `Parser.Pike.split()` and
resolves each name as written, so it sees imports *and* still works on code that does not
compile.

It traces `#include` too, and `--roxen=<dir>` resolves `Roxen.*`, `RXML.*` and
`<module.h>` against a Roxen tree — resolution is a file lookup, so that works without
booting the runtime.

Installed modules are marked and not descended into (one stdlib import otherwise pulls in
the whole runtime's tree). Unresolved references exit non-zero — usually a missing `-M`
root. `--json` for machine-readable output.

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
