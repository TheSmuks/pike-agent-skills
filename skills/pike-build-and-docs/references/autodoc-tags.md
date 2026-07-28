# Autodoc Reference

Verified against Pike 8.0.1116.

## Comment form

`//!` directly above the declaration. No blank line between the comment and the
declaration — a gap detaches the documentation from its target.

```pike
//! One-line summary.
//!
//! Longer description, which may span
//! multiple lines.
//!
//! @param name
//!   What this parameter means.
//! @returns
//!   What comes back.
//! @throws
//!   When and why it throws.
//! @seealso
//!   @[other_function], @[Some.Module]
//! @example
//!   int r = add(1, 2);
int add(int a, int b) { return a + b; }
```

## Tags

| Tag | Use |
|-----|-----|
| `@param <name>` | One per parameter, on its own line, description indented below |
| `@returns` | Return value |
| `@throws` | Error conditions |
| `@seealso` | Cross-references, using `@[Target]` |
| `@example` | Usage snippet |
| `@deprecated` | Marks a symbol deprecated |
| `@note` | Callout |
| `@[Symbol]` | Inline cross-reference (works inside any text) |

Module-level documentation goes in `module.pmod` (or the top of the `.pmod` file), above
everything else.

## Pipeline

```bash
# 1. extract — per file, or recurse a tree
pike -x extract_autodoc --builddir=build Doc.pike
pike -x extract_autodoc --srcdir=. --builddir=/tmp/adbuild   # outside srcdir

# 2. join — merge into one document
pike -x join_autodoc build/all.xml build/

# 3. render
pike -x autodoc_to_html build/all.xml html/
pike -x autodoc_to_split_html build/all.xml html/
```

`join_autodoc` usage, from its own help:

```
pike -x join_autodoc <destination.xml> <builddir>
pike -x join_autodoc [--post-process] [-q|--quiet] [-v|--verbose] <dest.xml> files...
```

## extract_autodoc flags

```
--srcdir=<dir>        recurse this tree (takes precedence over file arguments)
--builddir=<dir>      where XML is written (default ./)
--imgsrc=<dir>        image source directory
--imgdir=<dir>        image output directory
--root=<module>       namespace root (default predef::)
--compat              compatibility mode
--no-dynamic
--keep-going          continue past errors
-q, --quiet
-v, --verbose
-h, --help
```

There is **no `--dumpfile`**. Two further constraints, both hit in practice:

- **`--builddir` does not create intermediate directories.** Passing a nested path such as
  `Site.pmod/Server.pike` generates the XML but fails to write it. Use `--srcdir` for trees.
- **`--builddir` must sit outside `--srcdir`**, or the walk recurses into its own output.

Output naming is derived: `<builddir>/<file>.xml`, plus a `.stamp` file. Extraction is
incremental — a file is re-extracted only when its source is newer than the existing XML.

## Extracted XML

For the `add` example above:

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

Parameter types, return type, and `source-position` are all captured — the XML is a
machine-readable API index, useful beyond rendering HTML.

## Failure modes

| Symptom | Cause |
|---------|-------|
| Empty `build/`, exit 0 | Nothing matched — check `--srcdir` and that comments use `//!` |
| Docs missing for one symbol | Blank line between the `//!` block and the declaration |
| `Failed to read file "--dumpfile=..."` | That flag does not exist; use `--builddir` |
| Nothing re-extracted after edits | Incremental build — the `.xml` is newer than the source; delete `build/` |

Guard extraction in CI, since an empty result exits `0`:

```bash
pike -x extract_autodoc --srcdir=. --builddir=/tmp/adbuild   # outside srcdir
test -n "$(find build -name '*.xml')" || { echo "no autodoc extracted"; exit 1; }
```

## Related tools

```
pike -x assemble_autodoc      assemble a full documentation tree
pike -x git_export_autodoc    export autodoc from git history
pike -x pike_to_html          syntax-highlight Pike source as HTML
```
