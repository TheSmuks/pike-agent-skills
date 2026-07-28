---
name: pike-build-and-docs
description: >
  Build, install, and document Pike code with stock tooling — pike -x module to install,
  pike -x precompile for .cmod C modules, and the extract_autodoc/join_autodoc/
  autodoc_to_html pipeline for //! documentation comments. Use when packaging a Pike
  module for installation, working with .cmod C extensions, writing or rendering Pike
  autodoc, or setting up a Pike build in CI.
  Triggers on: pike -x module, precompile, cmod, C module, autodoc, extract_autodoc,
  //! comments, Pike build, install Pike module, Pike documentation, refdoc.
---

# Pike Build and Docs

## When to Use

- Installing a Pike module so other code can find it
- Working with `.cmod` C extension source
- Writing or rendering `//!` documentation
- Setting up a Pike build or docs step in CI

## Do You Even Need a Build?

**Pure Pike needs no build step.** `.pike` and `.pmod` files are compiled on load. If the
project has no `.cmod` files and no autotools files, there is nothing to build — put the
module root on the module path and run it.

```bash
pike -M ./lib main.pike
```

Only reach for the tooling below when C sources or installation are actually involved.

## Stock Tools

| Task | Command | Ships with Pike? |
|------|---------|------------------|
| Install a module | `pike -x module` | yes |
| `.cmod` → `.c` | `pike -x precompile` | yes |
| `.c` → loadable `.so` | `make` via `configure.in` / `Makefile.in` | **no** |
| Inspect build flags | `pike -x cflags`, `pike -x features` | yes |
| Extract autodoc | `pike -x extract_autodoc` | yes |
| Combine autodoc | `pike -x join_autodoc` | yes |
| Render autodoc | `pike -x autodoc_to_html`, `autodoc_to_split_html` | yes |

See everything available on your install:

```bash
ls $(pike -e 'write("%s\n", master()->pike_module_path[0]);')/Tools.pmod/Standalone.pmod/
```

> **"Ships with Pike" means upstream Pike, not every package.** Distributions split it up.
> On Debian/Ubuntu the base `pike8.0` package omits `precompile` and `module` — they are in
> `pike8.0-dev`, and `pike -x precompile` fails with a missing-file error until you install
> it. Rocky/RHEL do not package Pike at all; it must be built from source.
>
> Probe the interface rather than assuming presence:
>
> ```bash
> pike -x precompile --help    # exits 0 and prints usage when available
> ```

## C Modules

The split matters, and it is easy to state wrongly:

```
foo.cmod  --[ pike -x precompile ]-->  foo.c  --[ cc + make ]-->  foo.so
          \_______ stock Pike _______/        \___ external ___/
```

`pike -x precompile` ("Converts .pmod-files to .c files") is stock Pike and handles the
Pike-specific half. Producing the shared object needs a **C compiler, `make`, and
autotools** — tools outside Pike.

> A project containing `.cmod` files **cannot be built by Pike alone.** When reporting
> build requirements, say this explicitly rather than describing the build as "autotools"
> or as "Pike" — it is both, in sequence.

Pure-Pike projects never touch this path.

## Autodoc

Documentation is the `//!` comment placed directly above a declaration:

```pike
//! Adds two integers.
//! @param a
//!   First addend.
//! @param b
//!   Second addend.
//! @returns
//!   The sum.
int add(int a, int b) { return a + b; }
```

Common tags: `@param`, `@returns`, `@throws`, `@seealso`, `@example`, `@deprecated`.

### Extract

```bash
pike -x extract_autodoc --builddir=build Doc.pike
# → build/Doc.pike.xml  (plus a .stamp file)
```

The flag is **`--builddir`**. To walk a whole source tree instead of naming files:

```bash
pike -x extract_autodoc --srcdir=. --builddir=/tmp/adbuild   # NOT ./build — see below
```

`--srcdir` triggers recursion and takes precedence over file arguments — do not pass both
expecting the file list to win.

Two constraints that bite on real trees:

- **`--builddir` does not create intermediate directories.** A nested path such as
  `Site.pmod/Server.pike` generates its XML but fails to write it. Use `--srcdir` instead.
- **`--builddir` must sit outside `--srcdir`**, or the walk recurses into its own output
  and fails.

Verified output for the example above:

```xml
<autodoc><namespace name='predef'>
<class name='Doc'><docgroup homogen-name='add' homogen-type='method'>
<doc><text><p>Adds two integers.</p></text>
<group><param name="a"/><text><p>First addend.</p></text></group>
<group><returns/><text><p>The sum.</p></text></group></doc>
<method name='add'><source-position file='Doc.pike' first-line='6'/>
<arguments><argument name='a'><type><int/></type></argument>
           <argument name='b'><type><int/></type></argument></arguments>
<returntype><int/></returntype>
</method></docgroup></class></namespace></autodoc>
```

Note it captures parameter **types** and the **source position** — so the extracted XML
is a usable index of a codebase's API, not just prose.

### Combine and render

```bash
pike -x join_autodoc  build/all.xml build/          # merge per-file XML
pike -x autodoc_to_html build/all.xml html/         # single-page
pike -x autodoc_to_split_html build/all.xml html/   # one page per module
```

Run each with `--help` to confirm argument order on your version before wiring into CI —
these take positional arguments that differ between the tools.

## Installing a Module

```bash
pike -x module           # "Pike module installer"
```

Run from the module's source directory. Verify afterwards from the runtime rather than
trusting the exit code:

```bash
pike -e 'write("%O\n", undefinedp(master()->resolv("MyLib")));'   # 0 = installed
```

## CI

```yaml
- name: Docs
  run: |
    # builddir must be outside srcdir, or the walk recurses into its own output
    B=$(mktemp -d)
    pike -x extract_autodoc --srcdir=. --builddir="$B"
    test -n "$(find "$B" -name '*.xml')" || { echo "no autodoc extracted"; exit 1; }
```

The `test` guard matters: extraction succeeds quietly when it finds nothing to extract,
so an empty `build/` is the failure mode to watch for.

## Checklist

- [ ] Confirmed a build is actually needed (`.cmod` or autotools present)
- [ ] For `.cmod`: documented the C toolchain requirement, not just "autotools"
- [ ] Used `--builddir` (not `--dumpfile`) for extraction
- [ ] Verified installation from the runtime, not from an exit code

## Reference

- `references/autodoc-tags.md` — autodoc tag reference and pipeline details
