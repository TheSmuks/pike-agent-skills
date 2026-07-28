# Probe Catalogue

Copy-paste probes, each verified against Pike 8.0.1116. Output shown is real.

## Existence

```bash
pike -e 'write("%O\n", undefinedp(master()->resolv("Standards.JSON")));'
# 0   → exists

pike -e 'write("%O\n", undefinedp(master()->resolv("No.Such.Module")));'
# 1   → does not exist
```

`resolv()` returns `UNDEFINED` (not an error) for missing names. `UNDEFINED` prints as
`0`, so always test with `undefinedp()` rather than truthiness.

## Contents

```bash
pike -e 'write("%O\n", sizeof(indices(Protocols.HTTP)));'
# 79

pike -e 'write("%O\n", indices(Standards.JSON));'
```

`indices()` → symbol names, `values()` → the values themselves.

Filter for what you want:

```bash
pike -e 'write("%O\n", filter(indices(Stdio), lambda(string s){ return has_prefix(s,"F"); }));'
```

## Signatures

```bash
pike -e 'write("%O\n", _typeof(Stdio.File()->read));'
# function(void | int, void | int(1bit) : string(8bit))
```

Reads as: two optional arguments, returns an 8-bit string. `_typeof` on a value gives its
runtime type:

```bash
pike -e 'write("%O\n", _typeof(({1,2})));'
# array(int | zero)
```

## Provenance

```bash
pike -e 'write("%O\n", Program.defined(Stdio.File));'
# "/usr/local/pike/8.0.1116/lib/modules/Stdio.pmod/module.pmod:181"
```

`file:line` of the definition. The fastest answer to "which implementation am I getting?"
and the way to confirm a shadowing problem.

## Paths

```bash
pike --show-paths
# master.pike...: /usr/local/pike/8.0.1116/lib/master.pike
# Module path...: /usr/local/pike/8.0.1116/lib/modules
# Include path..: /usr/local/pike/8.0.1116/lib/include
# Program path..:

pike -e 'write("%O\n", master()->pike_module_path);'
```

Note "Include path" is for `#include` files (`lib/include`) — it is not where the bundled
helper scripts live (`include/pike/`).

## Available `-x` tools

```bash
ls $(pike -e 'write("%s\n", master()->pike_module_path[0]);')/Tools.pmod/Standalone.pmod/
```

On a stock 8.0 install: `assemble_autodoc autodoc_to_html autodoc_to_split_html benchmark
cflags cgrep check_http dump extract_autodoc extract_locale features forkd
git_export_autodoc hilfe httpserver join_autodoc make_wxs module monger pike_to_html
pmar_install precompile process_files pv rsif rsqld test_pike`

Each has a one-line purpose:

```bash
pike -e 'write("%s\n", Tools.Standalone["test_pike"]->description);'
# Executes tests according to testsuite files.
```

## Errors

```pike
mixed err = catch { ((array)0)[5]; };
if (err) write("%s", describe_backtrace(err));
```

```
Cannot cast int to array.
bt.pike:2: /main()->main()
```

First line is the message; the rest are frames with `file:line`.

## Compilation

```bash
pike -e 'compile_file("MyProgram.pike"); write("compiles\n");'
```

Prints `compiles`, or throws with the compile errors. Separates syntax/type problems from
logic problems before you start debugging behavior.

## hilfe (multi-statement)

```bash
echo 'write("%O\n", indices(Stdio)[..4]);' | pike -x hilfe
```

Accepts piped input for non-interactive use. Emits REPL framing (`(1) Result: …`, a
closing message) around your output — filter when scripting. Prefer `pike -e` for a single
expression.

## Inspecting a value mid-run

```pike
werror("value=%O type=%O\n", v, _typeof(v));
```

`%O` renders any Pike value structurally, including nested arrays and mappings. `werror`
writes to stderr, so it does not pollute program output.
