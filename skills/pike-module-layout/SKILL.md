---
name: pike-module-layout
description: >
  Structure and navigate Pike codebases — how .pike, .pmod files and .pmod directories
  become programs, modules, and dotted namespaces, and how the module path resolves them.
  Use when creating a new Pike module or program, deciding where a file belongs, fixing
  "module not found" or "index does not exist" errors, or mapping an unfamiliar Pike
  project. Triggers on: pmod, module.pmod, module path, PIKE_MODULE_PATH, -M flag,
  namespace, inherit, import, module not found, Pike project layout, where to put.
---

# Pike Module Layout

## When to Use

- Creating a new Pike module, program, or namespace
- Deciding whether something should be `.pike` or `.pmod`
- Debugging `module not found`, `index does not exist`, or unresolved dotted names
- Mapping the structure of an unfamiliar Pike codebase

For syntax and type rules, use `pike-language-reference` instead. This skill is about
where code lives and how Pike finds it.

## The Core Rule

**Resolution is by file extension, not by marker file.**

| On disk | Resolves as | Access |
|---------|-------------|--------|
| `Foo.pike` | Program (class) `Foo` | `Foo()` — instantiate it |
| `Foo.pmod` (file) | Module `Foo` | `Foo.fn()` |
| `Foo.pmod/` (directory) | Module `Foo` | `Foo.fn()` |
| `Foo.pmod/Bar.pike` | Program `Foo.Bar` | `Foo.Bar()` |
| `Foo.pmod/Bar.pmod/` | Module `Foo.Bar` | `Foo.Bar.fn()` |
| `Foo.pmod/module.pmod` | Symbols of `Foo` itself | `Foo.fn()` |

### `module.pmod` is optional

A `.pmod` **directory is already a module** because of its extension. `module.pmod` is an
optional file inside it that gives the module its own symbols, merged with the
directory's contents.

Pike's own standard library uses both forms:

```
lib/modules/Protocols.pmod/     no module.pmod  → still a module (Protocols.HTTP works)
lib/modules/Crypto.pmod/        has module.pmod → module with its own symbols
```

> **Common error.** Treating `module.pmod` as a required marker — "a directory is a module
> if it contains `module.pmod`". This is wrong and will make you miss most of the Pike
> stdlib and most real projects. Look for the `.pmod` **extension** on the directory.

Verify it yourself in ten seconds:

```bash
mkdir -p /tmp/t/NoMarker.pmod
echo 'string hi() { return "resolved without module.pmod"; }' > /tmp/t/NoMarker.pmod/Greeter.pike
pike -M /tmp/t -e 'write("%s\n", NoMarker.Greeter()->hi());'
# → resolved without module.pmod
```

## Choosing a File Kind

| You want | Use |
|----------|-----|
| Something you instantiate, with state | `Foo.pike` — a program |
| A namespace of functions, no state | `Foo.pmod` file |
| A namespace containing other units | `Foo.pmod/` directory |
| Both — a namespace with its own functions | `Foo.pmod/` + `module.pmod` inside |

Start with a `.pmod` **file**. Promote it to a directory only when you need to nest
things inside it; the dotted name does not change when you do, so callers are unaffected.

## The Module Path

```bash
pike --show-paths                    # where Pike looks right now
pike -M ./lib script.pike            # prepend a directory for this run
PIKE_MODULE_PATH=./lib pike script.pike
```

`pike --show-paths` on a stock 8.0 install prints:

```
master.pike...: /usr/local/pike/8.0.1116/lib/master.pike
Module path...: /usr/local/pike/8.0.1116/lib/modules
Include path..: /usr/local/pike/8.0.1116/lib/include
Program path..:
```

Inspect it at run time:

```bash
pike -e 'write("%O\n", master()->pike_module_path);'
```

**Debugging "module not found":** the name almost always resolves relative to a module
path root, not to the current file. `MyLib.Net` requires a `MyLib.pmod` reachable from a
path root — being in the same directory as the caller is not enough unless that
directory is on the path.

## Resolving a Name to Its Source

Ask the running Pike, never the filesystem alone. Every command below is a one-liner —
verified against Pike 8.0.1116, and each answers a question a file search gets wrong.

**Always check the search roots first.** It costs nothing and needs no compilation:

```bash
pike --show-paths          # Module path / Include path / Program path
```

### A class inside a module

`Program.defined()` reports `file:line` for the class itself. A filesystem walk cannot —
it stops at the enclosing module, so it cannot tell two classes in one module apart:

```bash
pike -e 'write("%O\n", Program.defined(Stdio.File));'
# "/usr/local/pike/8.0.1116/lib/modules/Stdio.pmod/module.pmod:181"

pike -e 'write("%O\n", Program.defined(Stdio.Buffer));'
# "Users/hww3/devel/pike/src/modules/_Stdio/buffer.cmod:79"
```

Both live in `Stdio`; only this tells them apart. It is also the only way to locate a
symbol implemented in C — those have no file on disk and any path search calls them
missing.

### A name that came from an `import` — the common trap

```pike
import A;
int f() { return B()->x(); }
```

`B` is `A.B`. It exists **only inside the imported scope**, so resolving the bare name
fails and the module looks missing when the code is fine:

```bash
pike -M . -e 'write("%O\n", undefinedp(master()->resolv("B")));'   # 1  — undefined!
pike -M . -e 'write("%O\n", Program.defined(master()->resolv("A.B")));'
# ".../A.pmod/B.pike"
```

**So when a bare name will not resolve, read the file's `import` and `inherit` lines
first and retry qualified.** List what a scope actually provides with `indices()`:

```bash
grep -nE '^[[:space:]]*(import|inherit)' User.pike
pike -M . -e 'write("%O\n", indices(master()->resolv("A")));'   # ({"Consts","C","B"})
```

The same applies to a bare name inside a module's own file: `Stdio.pmod/module.pmod`
says `inherit Fd;`, and `Fd` only resolves as `_Stdio.Fd` — because that file also does
`inherit _Stdio;`.

### Where `Program.defined()` lies

A **directory module** resolves to a dirnode object supplied by the master, so
`object_program()` is master's internal class:

```bash
pike -M . -e 'write("%O\n", Program.defined(object_program(master()->resolv("A"))));'
# "/usr/local/pike/8.0.1116/lib/master.pike:2364"   ← master.pike, not A.pmod
```

If the answer is `master.pike`, you asked about a directory module. Its source *is* the
directory — find it on the module path, and use `indices()` to see inside.

### `Scope::Name` is not a module path

`inherit YMD::cYear;` in `Calendar.pmod/Gregorian.pmod` refers to a **named inherit**
(`inherit Calendar.YMD:YMD;` earlier in the same file), not to a module called `YMD`.
`resolv("YMD::cYear")` will never work. Before hunting a missing `-M` root, check the
same file for a matching `inherit X:Name;` alias.

### Confirm what actually loaded

```bash
pike -M . -e 'write("%O\n", Program.all_inherits((program)"/abs/path/Leaf.pike"));'
```

Cast an **absolute** path: a relative cast resolves against the *casting file's*
directory, not the cwd.

### Two resolution rules the tool encodes

Both are easy to get wrong by hand:

- **String references resolve against the *including file's* directory**, not the current
  working directory. `inherit "Helper"` inside `sub/User.pike` finds `sub/Helper.pike`,
  even if a `Helper.pike` also sits at the root.
- **The same applies to casting a path to a program.** `(program)"Foo.pike"` inside a
  script resolves relative to *that script's* directory. Cast an absolute path
  (`combine_path(getcwd(), path)`) when the path came from the command line.

## `inherit` vs `import`

| | Effect | Use for |
|---|---|---|
| `inherit Foo;` | Pulls another program's symbols into this class | Subclassing, extending a program |
| `import Foo;` | Brings a module's symbols into scope unqualified | Avoiding repeated `Foo.` prefixes |

Both are dependency edges. When mapping a project, read both to build the real
dependency graph — a dotted reference like `Site.Net.connect()` is an edge too, even
without an `import`.

## Recommended Project Shape

```
MyLib.pmod/            → MyLib
├── module.pmod        → MyLib's own functions (optional)
├── Client.pike        → MyLib.Client        (instantiable)
├── config.pmod        → MyLib.config        (namespace)
└── Net.pmod/          → MyLib.Net
    ├── module.pmod
    └── Socket.pike    → MyLib.Net.Socket
```

Run it with `pike -M . main.pike` from the directory containing `MyLib.pmod/`.

## Naming

Pike uses different casing per role. This is idiomatic, not inconsistent:

| Role | Convention |
|------|-----------|
| Functions, variables | `snake_case` |
| Programs, modules (identifiers) | `CamelCase` |
| Program files | `UpperCamel.pike` |
| Module files | `lower-case.pmod` (stdlib also uses `CamelCase.pmod`) |
| Constants | `UPPER_CASE` |

Never "fix" a Pike project to a single project-wide case style.

## Checklist

- [ ] `.pmod` for namespaces, `.pike` for instantiable programs
- [ ] Directory modules end in `.pmod` — do not add `module.pmod` unless the module needs
      its own symbols
- [ ] Checked the search roots with `pike --show-paths` **first** — it is free and needs
      no compilation. Only reach for `pike -e` once you know the roots are right
- [ ] The module root is on the module path (`-M`, `PIKE_MODULE_PATH`, or installed)
- [ ] For a *class*, used `resolv()`/`Program.defined()` — a file walk stops at the
      enclosing module

## Reference

- To check that code *compiles*, see `pike-check.pike` in the `pike-build-and-docs` skill
- `references/resolution.md` — resolution rules with verified worked examples
