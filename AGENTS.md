# Pike Working Rules

High-frequency correctness rules for working in Pike, in a format any coding agent can
read. The full skills live in `skills/`.

Verified against Pike 8.0.1116; run `./verify.sh` to re-check them against your install.

## Module layout

- A `.pmod` **directory is a module because of its extension.** `module.pmod` is optional
  and only adds the module's own symbols. Do not treat it as a required marker — most of
  the Pike stdlib has none (`Protocols.pmod` does not, `Crypto.pmod` does).
- `Foo.pike` → instantiable program (`Foo()`). `Foo.pmod` (file or directory) → module
  namespace (`Foo.fn()`). Nested `.pmod` directories build dotted names.
- Module names resolve against module-path roots, not relative to the calling file. Use
  `pike -M <dir>` or `PIKE_MODULE_PATH`. Check with `pike --show-paths`.

## Testing

- Tests live **beside the module** they test, as `testsuite.in` — matching Pike's own
  stdlib layout.
- `testsuite.in` is **m4 source.** Expand it before running:
  ```sh
  # mktestsuite ships inside the Pike install, but distros disagree on where.
MKTS=$(ls "$(dirname "$(readlink -f "$(which pike)")")/../include/pike/mktestsuite" \
         /usr/include/pike*/pike/mktestsuite 2>/dev/null | head -1)
  "$MKTS" testsuite.in > testsuite && pike -x test_pike testsuite
  ```
- **Never run `pike -x test_pike testsuite.in` directly.** It does not expand the file, runs
  nothing, prints `Total tests: 0`, and exits `0`. Always confirm a non-zero test count.
- m4 unavailable? Write the expanded `testsuite` file directly — header line, `mixed a()`
  / `mixed b()`, then `....`
- Using `Tools.Testsuite.report_result()` in a plain script? It does **not** set the exit
  code. Add `return fail ? 1 : 0;`.

## Naming

Pike uses different casing per role. This is idiomatic — never normalise a Pike project to
one project-wide style.

| Role | Convention |
|------|-----------|
| Functions, variables | `snake_case` |
| Programs, modules | `CamelCase` |
| Program files | `UpperCamel.pike` |
| Module files | `lower-case.pmod` |
| Constants | `UPPER_CASE` |

## Verify, don't recall

Before writing code against an API, ask the runtime:

```sh
pike -e 'write("%O\n", undefinedp(master()->resolv("Standards.JSON")));'  # 0 = exists
pike -e 'write("%O\n", _typeof(Stdio.File()->read));'                    # real signature
pike -e 'write("%O\n", Program.defined(Stdio.File));'                    # file:line
```

## Documentation

`//!` autodoc directly above the declaration, with no blank line between. Tags:
`@param`, `@returns`, `@throws`, `@seealso`, `@example`, `@[Symbol]` for cross-references.

## Roxen codebases

- **Roxen sources are ISO-8859-1.** Plain `grep` in a UTF-8 locale treats them as binary
  and reports *no matches* while exiting `1` — 144 of Roxen's 170 module files are
  affected, undercounting searches by ~80%. Always use `grep -a`, `LC_ALL=C grep`, or
  `rg --text`. This silently produces confident, wrong conclusions.
- Identify a Roxen module by `constant module_type = MODULE_…;` (134/170 files), not by
  filename. The inherit form is `inherit "module";` — **not** `inherit "module.pike"`,
  which appears in 1 of 170 files.
- `.inc` and `.rjs` are **not** Roxen concepts (zero `.rjs` references in Roxen 6.3 or
  8.3.806). Their meaning is project-specific — find the module that claims the extension
  rather than assuming.

## Build

Pure Pike needs no build step — files compile on load. Only `.cmod` C sources require
one: `pike -x precompile` produces `.c`, then a **C compiler, `make`, and autotools**
produce the `.so`. That second half is not Pike tooling.
