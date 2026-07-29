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

## Tracing a Chain to Its Sources

`pike-resolve.pike` answers "where does this actually come from?" deterministically,
using Pike's own resolver rather than guessing from filenames.

```bash
pike -M . pike-resolve.pike Leaf.pike
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

Two passes, because they see different things:

| Pass | How | Sees |
|------|-----|------|
| **runtime** | compiles the target, walks `Program.inherit_tree()`, reports `Program.defined()` | exactly what Pike loaded — authoritative, but **inherits only** |
| **static** | tokenises with `Parser.Pike.split()`, resolves each name as written | inherits **and imports**, and works on code that does not compile |

`import` leaves no runtime trace, so the static pass is the only way to see it. Use
`--imports` to follow imports transitively.

```bash
pike -M . pike-resolve.pike --imports Foo.pike   # include imports
pike -M . pike-resolve.pike --roxen=/opt/roxen M.pike  # resolve Roxen + <module.h>
pike -M . pike-resolve.pike --static Broken.pike # target does not compile
pike -M . pike-resolve.pike --json Foo.pike      # machine-readable
pike pike-resolve.pike Standards.JSON            # a module, not a file
```

Installed modules are marked `[installed module]` and **not** descended into — otherwise
one stdlib import drags in the entire runtime's inherit tree. Pass `--system` to descend
anyway.

Unresolved references are reported and exit non-zero. That usually means a module-path
root is missing — add it with `-M`.

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
- [ ] The module root is on the module path (`-M`, `PIKE_MODULE_PATH`, or installed)
- [ ] Verified resolution with `pike -e` before assuming a layout works

## Reference

- `pike-resolve.pike` — trace inherit/import/include chains to source files
- To check that code *compiles*, see `pike-check.pike` in the `pike-build-and-docs` skill
- `references/resolution.md` — resolution rules with verified worked examples
