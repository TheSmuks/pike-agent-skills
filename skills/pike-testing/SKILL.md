---
name: pike-testing
description: >
  Write and run Pike tests with the stock Tools.Testsuite framework — testsuite.in files,
  the mktestsuite/m4 expansion step, pike -x test_pike, and two m4-free alternatives.
  Use when adding tests to a Pike project, running an existing Pike test suite, wiring
  Pike tests into CI, or when a Pike test run reports zero tests or passes suspiciously.
  Triggers on: testsuite, testsuite.in, test_pike, mktestsuite, Tools.Testsuite, Pike
  tests, pike test runner, red green, zero tests, Pike CI.
---

# Pike Testing

## When to Use

- Adding tests to a Pike project
- Running or debugging an existing Pike test suite
- Wiring Pike tests into CI
- A Pike test run reported `Total tests: 0`, or passed when it should not have

Stock Pike only — no third-party test framework required.

## Read This First: The Silent Pass

`testsuite.in` is **m4 source**. `pike -x test_pike` does not expand it. Pointed at an
unexpanded `.in` file it does not error — it runs nothing, reports success, and exits `0`.

```bash
pike -x test_pike testsuite.in
# Total tests: 0 (0 tests skipped)     ← exit 0. Nothing ran.
```

**Always confirm the reported test count is greater than zero.** An agent looping on
"tests pass" against a `.in` file will loop forever on a suite that never executes.

## Where Tests Go

Beside the code they test. Pike's own standard library does exactly this:

```
lib/modules/Stdio.pmod/testsuite.in
lib/modules/Crypto.pmod/testsuite.in
lib/modules/Protocols.pmod/testsuite.in
```

Do not centralize Pike tests in one `tests/` directory unless the project already does.

## Path 1 — Canonical (needs m4)

```bash
# expand, then run
/usr/local/pike/8.0.1116/include/pike/mktestsuite testsuite.in > testsuite
pike -x test_pike testsuite
```

`mktestsuite` ships inside the Pike installation at `<prefix>/include/pike/mktestsuite`.
Locate it portably:

```bash
MKTS="$(dirname "$(readlink -f "$(which pike)")")/../include/pike/mktestsuite"
```

Note this is **not** the path `pike --show-paths` reports as "Include path" (that is
`lib/include`, for `#include` files). `mktestsuite` lives under `include/pike/`.

Writing `testsuite.in`:

```
test_eq(1+1, 2)
test_eq(upper_case("pike"), "PIKE")
test_true(arrayp(({1,2})))
test_false(stringp(5))
test_any([[ int x = 3; return x*2; ]], 6)
```

Verified run:

```
Doing tests in testsuite (4 tests)
Total tests: 4 (0 tests skipped)
```

Exit code is `1` on failure — safe for CI.

## Path 2 — No m4

The expanded format is plain text. Write `testsuite` directly and skip m4 entirely:

```
mymodule:1: test 1, expected result: EQ
mixed a() { return 1+1; }
mixed b() { return 2; }
....
mymodule:2: test 2, expected result: TRUE
mixed a() { return stringp("x"); }
....
```

Structure: a header line, one or two `mixed` functions, and a `....` terminator.
For `EQ`, `a()` and `b()` must be equal. For `TRUE`/`FALSE`, only `a()` is needed.

`pike -x test_pike testsuite` runs this identically to a generated file and exits `1` on
failure. This is the best path when generating tests programmatically — no m4 dependency
and no expansion step to forget.

## Path 3 — No m4, programmatic

When setup logic makes the macro form awkward, write a normal Pike program:

```pike
int main() {
  int ok = 0, fail = 0;

  void check(string name, int cond) {
    if (cond) ok++;
    else { fail++; Tools.Testsuite.log_msg("FAIL: %s\n", name); }
  };

  check("addition", 1+1 == 2);
  check("upper_case", upper_case("pike") == "PIKE");

  Tools.Testsuite.report_result(ok, fail);
  return fail ? 1 : 0;      // ← REQUIRED
}
```

Output: `WD succeeded 2 failed 0 skipped 0`

> **`report_result()` does not set the exit code.** Without the explicit
> `return fail ? 1 : 0;`, this script exits `0` even with failures, and CI goes green on a
> red suite. This is the single most important line in the file.

## Choosing a Path

| Situation | Path |
|-----------|------|
| Contributing to Pike itself, or matching stdlib convention | 1 |
| Generating tests programmatically; m4 unavailable | 2 |
| Tests need real setup/teardown or fixtures | 3 |
| CI on a minimal container | 2 or 3 (no m4 needed) |

## CI

```yaml
- name: Test
  run: |
    MKTS="$(dirname "$(readlink -f "$(which pike)")")/../include/pike/mktestsuite"
    "$MKTS" testsuite.in > testsuite
    pike -x test_pike testsuite | tee out.txt
    grep -q "Total tests: 0" out.txt && { echo "No tests ran"; exit 1; } || true
```

The `grep` guard turns the silent pass into a hard failure. Include it — the exit code
alone will not catch an empty run.

## Checklist

- [ ] Expanded `.in` → `testsuite` before running, or wrote `testsuite` directly
- [ ] Confirmed the reported test count is non-zero
- [ ] Confirmed a deliberately failing test actually fails
- [ ] Path 3 only: explicit `return fail ? 1 : 0;`

## Reference

- `references/testsuite-format.md` — full macro and expanded-format reference
