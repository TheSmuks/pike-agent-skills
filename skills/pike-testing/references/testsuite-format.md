# Testsuite Format Reference

Verified against Pike 8.0.1116.

## Macro forms (`testsuite.in`)

All five verified to expand and run:

```
test_eq(1+1, 2)                          a == b
test_equal(({1,2}), ({1,2}))             deep/structural equality
test_true(arrayp(({1,2})))               a is true
test_false(stringp(5))                   a is false
test_any([[ int x = 3; return x*2; ]], 6)  run a statement block, compare result
```

Use `test_equal` for arrays, mappings, and multisets — `test_eq` compares by identity for
reference types and will fail on structurally equal but distinct values.

`test_any` takes a full statement block in `[[ ]]` and requires an explicit `return`.
Use it when a test needs local variables or setup.

## Expanded format (`testsuite`)

What `mktestsuite` produces, and what you can write by hand to skip m4:

```
label:1: test 1, expected result: EQ
mixed a() { return 1+1; }
mixed b() { return 2; }
....
label:2: test 2, expected result: TRUE
mixed a() { return stringp("x"); }
....
```

Rules:

- Header line: `<label>:<srcline>: test <n>, expected result: <KIND>`
- `KIND` is `EQ`, `EQUAL`, `TRUE`, `FALSE`, `RUN`, or `PUSH_WARNING`
  (the full set handled by `test_pike`)
- `EQ`/`EQUAL` need both `a()` and `b()`; `TRUE`/`FALSE`/`RUN` need only `a()`
- Each test terminates with a line of exactly four dots: `....`
- The label and source line are for error messages only; any label works

## Running

```bash
pike -x test_pike testsuite
```

Output on success:

```
Doing tests in testsuite (5 tests)
Total tests: 5 (0 tests skipped)
```

Output on failure — the actual and expected values are printed:

```
o->a(): 2
o->b(): 3
Failed tests: 1.
Total tests: 1 (0 tests skipped)
```

Exit code: `0` on success, `1` on any failure.

## Useful flags

```bash
pike -x test_pike --help              # full list for your version
pike -x test_pike -v2 testsuite       # verbosity level 0-3; 3 prints every test
pike -x test_pike --no-watchdog ...   # disable the watchdog subprocess
pike -x test_pike --subproc-start=valgrind ...
```

`--no-watchdog` is worth knowing for containers and CI: by default `test_pike` forks a
watchdog process (`Forked watchdog pid …` in the output), which can be unwanted in
constrained or single-process environments.

`TEST_VERBOSITY` and `TEST_ON_TTY` environment variables also affect output — relevant
when logs look different in CI than locally.

## Tools.Testsuite API (path 3)

```pike
Tools.Testsuite.report_result(int succeeded, int failed, void|int skipped);
Tools.Testsuite.log_msg(string fmt, mixed ... args);      // always shown
Tools.Testsuite.log_status(string fmt, mixed ... args);   // transient status line
```

`report_result` prints `WD succeeded N failed N skipped N`. **It does not set the process
exit code** — return it yourself:

```pike
return fail ? 1 : 0;
```

## The zero-test trap

```bash
pike -x test_pike testsuite.in
# Total tests: 0 (0 tests skipped)   ← exit 0
```

`testsuite.in` is m4 source. The runner reads it as an expanded file, finds no test
blocks, and reports success. Guard against it:

```bash
pike -x test_pike testsuite | tee out.txt
grep -q "Total tests: 0" out.txt && exit 1
```
