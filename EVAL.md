# Eval

`verify.sh` proves the documented **commands** are correct. It does not prove the skills
change what an agent actually does. This file is that check.

Every probe below targets a specific misconception. The **"without"** column is what an
agent typically answers from general knowledge — each one was produced by a real model
before these skills existed, and each is wrong. If an agent with the skills installed still
gives the "without" answer, the skill is not being picked up or is not clear enough.

Run it by hand: paste the probe, compare against the two columns. Ten minutes.

## Probes

### 1. Module layout

> "In a Pike project, how do I know whether a directory is a module?"

| | Answer |
|---|---|
| ❌ Without | "A directory is a module if it contains a `module.pmod` file." |
| ✅ With | "A directory is a module if its name ends in `.pmod`. `module.pmod` is optional — it adds the module's own symbols. `Protocols.pmod/` in the stdlib has none and is still a module." |

**Why it matters:** the wrong rule misses most of the Pike standard library.

### 2. Testing

> "I have a `testsuite.in` in my Pike module. Run the tests."

| | Answer |
|---|---|
| ❌ Without | `pike -x test_pike testsuite.in` — reports `Total tests: 0`, exits `0`, looks like a pass |
| ✅ With | Expands with `mktestsuite` first, then runs the generated `testsuite`, **and** checks the reported count is non-zero |

**Why it matters:** the wrong answer is a green build that ran nothing. An agent looping on
"tests pass" never terminates usefully.

### 3. Test exit codes

> "Write a Pike test script using `Tools.Testsuite` and wire it into CI."

| | Answer |
|---|---|
| ❌ Without | Calls `report_result(ok, fail)` and returns `0` |
| ✅ With | Adds `return fail ? 1 : 0;`, noting `report_result()` does not set the exit code |

**Why it matters:** CI goes green on a red suite.

### 4. Dependencies

> "How does dependency management work in Pike?"

| | Answer |
|---|---|
| ❌ Without | "Pike has no package manager." |
| ✅ With | "`pike -x monger` is stock. What Pike lacks is a per-project manifest or lockfile — dependencies resolve at run time through the module path." |

**Why it matters:** they are different claims, and the distinction changes what you write
into a constitution or CI setup.

### 5. API verification

> "Does `Stdio.File()->read` take arguments? What does it return?"

| | Answer |
|---|---|
| ❌ Without | Answers from memory, often confidently and wrongly |
| ✅ With | Runs `pike -e 'write("%O\n", _typeof(Stdio.File()->read));'` and reports the real signature |

**Why it matters:** the habit of asking the runtime instead of recalling is the highest-value
behaviour change in the whole set.

### 6. C modules

> "How do I build this Pike project? It has a `.cmod` file."

| | Answer |
|---|---|
| ❌ Without | "Run `make`" or "it's autotools" |
| ✅ With | `pike -x precompile` produces `.c` (stock Pike), then a **C compiler + make + autotools** produce the `.so` — and says that second half is not Pike tooling |

### 7. Naming

> "Review this Pike codebase's naming consistency." (functions `snake_case`, programs `CamelCase`, files `UpperCamel.pike`)

| | Answer |
|---|---|
| ❌ Without | "Naming is inconsistent — standardise on one convention." |
| ✅ With | Reports per dimension and says this mix is idiomatic Pike |

**Why it matters:** the wrong answer generates a large, harmful refactor.

## Scoring

| Score | Meaning |
|-------|---------|
| 7/7 | Skills are working |
| 5–6 | Mostly working; check which skill covers the miss and whether its `description` triggers |
| ≤4 | Skills are not being loaded — check install location and frontmatter |

## Known limits

- Small sample, hand-run, no statistics. It detects gross regressions, not subtle quality.
- The probes are written by the same author as the skills, so they test what the skills
  cover — not what they omit.
- A model that already knows Pike well may pass some probes without the skills. That is a
  good outcome, not a broken eval.
- Nothing here measures whether the *generated code* is better, only whether the stated
  reasoning is correct.
