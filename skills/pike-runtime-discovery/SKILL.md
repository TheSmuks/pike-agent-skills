---
name: pike-runtime-discovery
description: >
  Inspect a live Pike runtime to find APIs, check signatures, and locate where a symbol is
  defined, using only stock Pike. Covers pike -e one-liners, hilfe as a scriptable probe,
  indices/values/_typeof, master()->resolv, Program.defined, and describe_backtrace for
  error triage. Use when you need to know whether a module or function exists, what
  arguments it takes, where it comes from, or why Pike code is failing at run time.
  Triggers on: what modules, does this function exist, function signature, Pike API,
  hilfe, indices, _typeof, describe_backtrace, Pike REPL, symbol lookup, resolv.
---

# Pike Runtime Discovery

## When to Use

- Checking whether a module or function exists before writing code against it
- Finding a function's real signature instead of guessing arguments
- Locating the file and line where a program is defined
- Triaging a run-time error or unexpected value

Stock Pike only. The runtime is authoritative — check it rather than recalling an API.

## The One-Liner

`pike -e '<expr>'` is the fastest way to ask the runtime a question:

```bash
pike -e 'write("%O\n", _typeof(({1,2})));'
# array(int | zero)
```

Use this before writing code against any API you are not certain of. It costs one
command and removes a whole class of confident-but-wrong output.

## Core Probes

All verified against Pike 8.0.1116.

### Does it exist? What is in it?

```bash
pike -e 'write("%O\n", sizeof(indices(Protocols.HTTP)));'
# 79

pike -e 'write("%O\n", indices(Standards.JSON));'
```

`indices()` lists a module's symbols; `values()` gives the corresponding values.

### Resolve a dotted name from a string

```bash
pike -e 'write("%O\n", master()->resolv("Standards.JSON"));'
# Standards.JSON
```

Useful when the name is computed, or to test resolution without a compile error.

A missing name **does not throw** — it returns `UNDEFINED`, which makes this a clean
existence check:

```bash
pike -e 'write("%O\n", undefinedp(master()->resolv("No.Such.Module")));'
# 1        ← does not exist

pike -e 'write("%O\n", undefinedp(master()->resolv("Standards.JSON")));'
# 0        ← exists
```

Use `undefinedp()` rather than a truth test: `UNDEFINED` prints as `0`, so a bare
`if (!m)` cannot distinguish "missing" from a legitimately zero value.

### What is the signature?

```bash
pike -e 'write("%O\n", _typeof(Stdio.File()->read));'
# function(void | int, void | int(1bit) : string(8bit))
```

This is the real type, including optional arguments and the return type. Prefer it over
documentation when they disagree — this is what the runtime will enforce.

### Where does this come from?

```bash
pike -e 'write("%O\n", Program.defined(Stdio.File));'
# "/usr/local/pike/8.0.1116/lib/modules/Stdio.pmod/module.pmod:181"
```

Returns `file:line`. This is the fastest way to answer "which implementation am I
actually getting?" — especially when a local module shadows a stdlib one.

### Where is Pike looking?

```bash
pike --show-paths
pike -e 'write("%O\n", master()->pike_module_path);'
```

The first thing to check for any `module not found`.

## hilfe as a Scriptable Probe

`pike -x hilfe` is the REPL. It also accepts piped input, which makes it usable
non-interactively for multi-statement exploration:

```bash
echo 'write("%O\n", indices(Stdio)[..4]);' | pike -x hilfe
```

Expect REPL noise (`(1) Result: …`, a closing message) around your output — filter it
with `tail`/`grep` when scripting. For a single expression, `pike -e` is cleaner; use
hilfe when you need several statements sharing state.

## Error Triage

`describe_backtrace()` turns a caught error into a readable trace:

```pike
int main() {
  mixed err = catch { ((array)0)[5]; };
  if (err) write("%s", describe_backtrace(err));
  return 0;
}
```

```
Cannot cast int to array.
bt.pike:2: /main()->main()
```

The first line is the message, subsequent lines are frames with `file:line`. When
diagnosing a failure, capture this rather than only the message — the frame list usually
identifies the real caller.

Type-check a suspicious value at the point of failure:

```pike
werror("value=%O type=%O\n", v, _typeof(v));
```

`%O` renders any Pike value structurally, including nested arrays and mappings.

## Compile vs Run Time

Pike compiles on load, so many errors surface before `main()` runs. To check that a file
compiles without executing it:

```bash
pike -e 'compile_file("MyProgram.pike"); write("compiles\n");'
# prints "compiles", or throws with the compile errors and exits non-zero
```

This distinguishes "my syntax or types are wrong" from "my logic is wrong" — worth doing
before debugging behavior. On failure it emits a backtrace through the compiler frames;
the useful part is the reported error line in your file, not the master.pike frames.

## Workflow

1. **Before writing** — confirm the module and signature with `pike -e`.
2. **On failure** — `describe_backtrace()` for the trace, `_typeof()` for the value.
3. **On surprise** — `Program.defined()` to confirm which file you actually loaded.
4. **On "not found"** — `pike --show-paths` and check the module path.

## Checklist

- [ ] Verified the API exists and its signature, rather than recalling it
- [ ] Confirmed which file a symbol resolves to when behavior is surprising
- [ ] Captured full backtraces, not just messages

## Reference

- `references/probes.md` — copy-paste probe catalogue with verified output
