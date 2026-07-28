# pike-agent-skills

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Pike 8.0](https://img.shields.io/badge/pike-8.0.1116-informational.svg)](https://pike.lysator.liu.se/)
[![Verified](https://img.shields.io/badge/commands-26%2F26_verified-brightgreen.svg)](verify.sh)
[![Copilot](https://img.shields.io/badge/GitHub_Copilot-supported-8957e5.svg)](https://github.com/features/copilot)

Agent skills for developing in [Pike](https://pike.lysator.liu.se/) — module layout,
testing, runtime discovery, and builds. Works with GitHub Copilot and Claude.

**Stock Pike only.** Nothing here needs a third-party package, formatter, or test
framework. Every command was executed against Pike 8.0.1116 before being written down,
and `./verify.sh` re-runs all of them.

## Install

### GitHub Copilot

```bash
git clone https://github.com/TheSmuks/pike-agent-skills
cp -r pike-agent-skills/skills/* .github/skills/
cp pike-agent-skills/.github/instructions/pike.instructions.md .github/instructions/
```

The instructions file applies automatically when Copilot touches `.pike`, `.pmod`,
`.cmod`, or `testsuite` files — no invocation needed. The skills are available on demand.

### Claude

```bash
npx skills add TheSmuks/pike-agent-skills
```

Or manually, for all projects:

```bash
git clone https://github.com/TheSmuks/pike-agent-skills
cp -r pike-agent-skills/skills/* ~/.claude/skills/
```

## Skills

| Skill | Covers |
|-------|--------|
| [`pike-module-layout`](skills/pike-module-layout/) | `.pike` vs `.pmod`, dirnode resolution, dotted namespaces, module path, `inherit` vs `import` |
| [`pike-testing`](skills/pike-testing/) | `Tools.Testsuite`, `testsuite.in` and m4, `pike -x test_pike`, two m4-free paths, exit codes |
| [`pike-runtime-discovery`](skills/pike-runtime-discovery/) | `pike -e` probes, `hilfe`, `indices`/`_typeof`/`resolv`/`Program.defined`, `describe_backtrace` |
| [`pike-build-and-docs`](skills/pike-build-and-docs/) | `pike -x module`, `precompile` for `.cmod`, the autodoc pipeline |

These cover **workflow**. For Pike syntax, types, and standard-library semantics, pair
them with a language reference skill — that ground is deliberately not repeated here.

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
passed: 26   failed: 0
```

Run it after a Pike upgrade — it is the fastest way to find out whether these skills are
still telling the truth.

## Related

- [spec-kit-brownfield-pike](https://github.com/TheSmuks/spec-kit-brownfield-pike) — Spec Kit brownfield extension with a Pike profile built on the same verified findings

## License

MIT
