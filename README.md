# pike-agent-skills

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Pike 8.0](https://img.shields.io/badge/pike-8.0.1116-informational.svg)](https://pike.lysator.liu.se/)
[![Verified](https://img.shields.io/badge/checks-48%2F48_passing-brightgreen.svg)](verify.sh)
[![Agents](https://img.shields.io/badge/agents-Copilot_%7C_Codex_%7C_Claude-8957e5.svg)](#install)

Agent skills for developing in [Pike](https://pike.lysator.liu.se/) — module layout,
testing, runtime discovery, and builds. Tool-agnostic: GitHub Copilot, Codex, Claude, and
anything that reads `AGENTS.md` or `SKILL.md`.

**Stock Pike only.** Nothing here needs a third-party package, formatter, or test
framework. Every command was executed against Pike 8.0.1116 before being written down,
and `./verify.sh` re-runs all of them.

## Install

Everything here is plain markdown — no runtime, no build, no lock-in. The installer just
copies files where your agent looks for them.

```bash
git clone https://github.com/TheSmuks/pike-agent-skills
cd your-project
../pike-agent-skills/install.sh          # auto-detects what you use
```

Or pick a target explicitly:

| Command | Installs to | For |
|---------|-------------|-----|
| `install.sh claude` | `~/.claude/skills/` | Claude, all projects |
| `install.sh claude-project` | `./.claude/skills/` + `AGENTS.md` | Claude, this project |
| `install.sh copilot` | `./.github/skills/` + `./.github/instructions/` | GitHub Copilot |
| `install.sh codex` | `./.agents/skills/` + `AGENTS.md` | Codex |
| `install.sh agents` | `AGENTS.md` only | Cursor, Zed, Amp, Jules, anything AGENTS.md-aware |
| `install.sh /path/to/dir` | that directory | Anything else |

Re-running is safe — `AGENTS.md` is appended to once and skipped thereafter.

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

With `--roxen=<dir>` pointing at a real install, compilation happens **inside** it, via
Roxen's own `./start --program` — its modules, its bundled Pike, nothing stubbed. Without
one, Roxen references are reported as **unverified warnings** and never silently accepted:

```
!! handler.pike: 1 Roxen reference could NOT be verified: Roxen
     handler.pike:3: Undefined identifier Roxen.
   No Roxen install found. Pass --roxen=<dir>, or set ROXEN_DIR.
   These are NOT confirmed correct — this check was incomplete.

INCOMPLETE: your code compiled, but 1 Roxen reference went unverified.
```

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
passed: 48   failed: 0
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
