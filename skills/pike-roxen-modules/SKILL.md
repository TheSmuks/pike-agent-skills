---
name: pike-roxen-modules
description: >
  Find, read, and write Roxen WebServer modules in Pike — recognising a Roxen module,
  the module_type taxonomy, the registration constants and callbacks, defvar configuration,
  and how Roxen decides which module handles a given file or extension. Use when working
  in a Roxen codebase, identifying whether Pike files are Roxen modules, tracing which
  module serves a URL or file type, or figuring out what a project-specific extension
  such as .inc or .rjs actually does.
  Triggers on: Roxen, RXML, module_type, defvar, find_file, query_location, MODULE_LOCATION,
  MODULE_TAG, roxen module, .inc, .rjs, RXML tag, Roxen WebServer, module.h.
---

# Roxen Modules

## When to Use

- Determining whether a Pike file is a Roxen module, and what kind
- Navigating an unfamiliar Roxen codebase
- Tracing which module serves a URL, file, or extension
- Writing or modifying a Roxen module

Verified against the Roxen source (branches `6.3` and current `8.3.806`).

## Read This First: grep Silently Misses Roxen Files

Roxen sources are **ISO-8859-1**, not UTF-8 — most carry a latin-1 `©` in the copyright
header. In a UTF-8 locale, `grep` classifies them as binary and reports **no matches**
while exiting `1`, so a search looks like a clean "not found".

```bash
grep -c inherit server/modules/filesystems/filesystem.pike
# (no output, exit 1)          ← wrong

grep -a -c inherit server/modules/filesystems/filesystem.pike
# 3                            ← correct
```

**144 of Roxen's 170 module files are affected.** Measured across the tree:

| Search | `grep -a` | plain `grep` |
|--------|-----------|--------------|
| `inherit "module"` | **129** | 25 |
| `constant module_type` | **134** | 22 |

Plain grep undercounts by roughly 80%. **Always use `grep -a`** (or `LC_ALL=C grep`, or
`rg --text`) when searching a Roxen codebase. Getting this wrong produces confident,
completely wrong conclusions about what a codebase contains.

## Recognising a Roxen Module

A Roxen module is a `.pike` file, but **not every `.pike` file in a Roxen tree is a
module**. Check these signals, most reliable first — frequencies are from the 170
module files in Roxen's `server/modules` and `server/more_modules`:

| Signal | Files | Notes |
|--------|-------|-------|
| `constant module_type = MODULE_…;` | 134 / 170 | **Strongest signal.** Also tells you what kind |
| `inherit "module";` | 129 / 170 | Note: **`"module"`, not `"module.pike"`** |
| `#include <module.h>` | 126 / 170 | Angle-bracket include from `server/etc/include/` |
| `constant module_name` / `module_doc` | — | Display name and description |
| `defvar(...)` | 92 / 170 | Declares configuration variables |

> **Do not detect Roxen modules by `inherit "module.pike"`.** That form appears in exactly
> **1 of 170** files (`server/modules/configuration/avg_profiling.pike`). The idiomatic form
> is `inherit "module";` — Pike resolves it to the `module.pike` program without the
> extension. Detecting on the `.pike` spelling misses ~99% of real modules.

Typical header:

```pike
constant cvs_version = "$Id: … $";
constant thread_safe = 1;

#include <module.h>
#include <config.h>
inherit "module";

constant module_type = MODULE_TAG;
constant module_name = "My Tag Module";
constant module_doc  = "Describes what this does.";
```

## The `module_type` Taxonomy

From `server/etc/include/module_constants.h` — a bitfield, so a module can be several
kinds at once (`MODULE_LOCATION | MODULE_TAG`):

| Constant | Bit | Role |
|----------|-----|------|
| `MODULE_ZERO` | 0 | No type; utility or base module |
| `MODULE_EXTENSION` | 1<<0 | Handles a URL extension |
| `MODULE_LOCATION` | 1<<1 | Mounted at a path; serves files from it |
| `MODULE_URL` | 1<<2 | Rewrites or intercepts URLs |
| `MODULE_FILE_EXTENSION` | 1<<3 | Claims file extensions (see below) |
| `MODULE_TAG` (= `MODULE_PARSER`) | 1<<4 | Provides RXML tags |
| `MODULE_LAST` / `MODULE_FIRST` | 1<<5 / 1<<6 | Runs last / first in request handling |
| `MODULE_AUTH` | 1<<7 | Authentication |
| `MODULE_MAIN_PARSER` | 1<<8 | The main content parser |
| `MODULE_TYPES` | 1<<9 | Maps extensions to content types |
| `MODULE_DIRECTORIES` | 1<<10 | Directory listings |
| `MODULE_PROXY` | 1<<11 | Proxy behaviour |
| `MODULE_LOGGER` | 1<<12 | Request logging |
| `MODULE_FILTER` | 1<<13 | Post-processes responses |
| `MODULE_PROVIDER` | 1<<15 | Provides services to other modules |
| `MODULE_USERDB` | 1<<16 | User database |
| `MODULE_PROTOCOL` | 1<<28 | Protocol handler |
| `MODULE_CONFIG` | 1<<29 | Configuration interface |
| `MODULE_SECURITY` | 1<<30 | Security |
| `MODULE_EXPERIMENTAL` | 1<<31 | Marked experimental |

`MODULE_PARSER` is a compatibility alias for `MODULE_TAG` — they are the same bit.

**Read `module_type` first.** It tells you where in the request lifecycle the module runs,
which is the fastest way to understand an unfamiliar module.

## Callbacks

By frequency across the bundled modules — implement or look for these:

| Callback | Files | Purpose |
|----------|-------|---------|
| `create()` | 100 | Declare `defvar()` configuration variables |
| `start()` | 83 | Called when the module is enabled or reloaded |
| `status()` | 50 | HTML status shown in the admin interface |
| `find_file(path, id)` | 23 | **`MODULE_LOCATION`**: serve a file from the mount point |
| `stop()` | 18 | Cleanup on disable |
| `filter(result, id)` | 13 | **`MODULE_FILTER`**: post-process a response |
| `first_try(id)` | 11 | **`MODULE_FIRST`**: intercept before normal handling |
| `query_location()` | 9 | **`MODULE_LOCATION`**: the mount path |
| `parse_rxml(...)` | 4 | RXML parsing entry point |

`id` is the `RequestID` object carrying the request. `RXML_CONTEXT` is a macro for the
current RXML evaluation context, used inside tag modules.

## Configuration with `defvar`

Configuration variables are declared in `create()` and read with `query()`:

```pike
void create() {
  defvar("mountpoint", "/files/", "Mount point", TYPE_LOCATION,
         "Where this module is mounted.");
  defvar("enabled", 1, "Enabled", TYPE_FLAG, "Turn the module on.");
}

string query_location() { return query("mountpoint"); }
```

`module.h` defines the `TYPE_*` constants (`TYPE_STRING`, `TYPE_FILE`, `TYPE_INT`,
`TYPE_DIR`, `TYPE_FLAG`/`TYPE_TOGGLE`, `TYPE_STRING_LIST`, `TYPE_DIR_LIST`, …) and the
shorthand `QUERY(var)`, which expands to `query("var")`.

## Codebase Layout

Roxen's bundled modules are grouped by purpose — expect the same shape in a site tree:

```
server/modules/
├── tags/          RXML tag modules       (MODULE_TAG)
├── filesystems/   file serving           (MODULE_LOCATION)
├── graphics/      image generation
├── scripting/     cgi, php, perl, pikescript, servlet, fastcgi, webapp
├── filters/       response filters       (MODULE_FILTER)
├── security/      access control         (MODULE_SECURITY)
├── logging/       request logging        (MODULE_LOGGER)
├── proxies/       proxy modules          (MODULE_PROXY)
├── directories/   directory listings     (MODULE_DIRECTORIES)
├── database/  ldap/  throttling/  js-support/
└── configuration/  compat/  examples/  misc/
server/more_modules/  additional modules (flat, no subdirectories)
server/base_server/   core: configuration.pike, roxen.pike
server/etc/include/   module.h, module_constants.h, roxen.h, config.h
```

The directory a module lives in is a strong hint about its `module_type`, but confirm by
reading the constant — a module can declare several type bits regardless of location.

Angle-bracket includes (`#include <module.h>`) resolve from `server/etc/include/`. When an
include cannot be found, that path is what is missing from the include path.

## `.inc`, `.rjs`, and Other Extensions

**These are not Roxen WebServer concepts.** Verified across both Roxen `6.3` and `8.3.806`:

| Extension | In Roxen source |
|-----------|-----------------|
| `.rjs` | **Zero** files and **zero** code references |
| `.inc` | No files; one reference — `404.inc`, the default 404-page filename in `configuration.pike` |

So if a codebase uses `.inc` or `.rjs`, the meaning comes from **that project**, not from
Roxen. Do not assume semantics for them. Roxen decides how to treat a file from which
module handles it, so the answer is always in the configuration and the modules:

**How to find out what an extension means in a given deployment:**

1. **Look for a module claiming it.** `MODULE_FILE_EXTENSION` modules implement
   `query_file_extensions()` returning an array of extensions, plus
   `handle_file_extension()`. `configuration.pike` builds an extension → handler map from
   these.
   ```bash
   grep -a -rn "query_file_extensions\|handle_file_extension" --include='*.pike' .
   ```
   Note: **no module bundled with Roxen uses this hook** — a hit means custom code, which
   is exactly what you are looking for.

2. **Look for the extension as a literal** in module source and configuration:
   ```bash
   grep -a -rn '"\.inc"\|"\.rjs"\|\.rjs\b' --include='*.pike' --include='*.xml' .
   ```

3. **Check content-type mapping.** `MODULE_TYPES` modules supply `type_from_extension`,
   which `configuration.pike` uses to assign a content type. Whether a file is RXML-parsed
   normally follows from its content type, not its extension.

4. **Check the mount points.** `MODULE_LOCATION` modules declare `query_location()`; the
   module mounted over a path decides how files under it are served.

Report what you find rather than guessing. An extension with no module claiming it is
served as a plain file.

## Checklist

- [ ] Searched with `grep -a` / `LC_ALL=C` / `rg --text` — never plain `grep`
- [ ] Identified modules by `constant module_type`, not by filename
- [ ] Used `inherit "module"` (no `.pike`) when detecting or writing
- [ ] Read `module_type` before reading the body
- [ ] For an unknown extension: searched for a module claiming it before assuming meaning

## Reference

- `references/module-anatomy.md` — annotated module skeletons per module_type
