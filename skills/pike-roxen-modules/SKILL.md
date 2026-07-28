---
name: pike-roxen-modules
description: >
  Work in a Roxen WebServer codebase in Pike — recognising and navigating modules, the
  module_type taxonomy, writing MODULE_LOCATION modules with find_file and response
  mappings, writing RXML tags with RXML.Tag/RXML.Frame, the RequestID object, defvar
  configuration, and logging. Use when reading or modifying Roxen modules, adding an RXML
  tag, serving content from a Roxen module, or tracing which module handles a request.
  Triggers on: Roxen, RXML, module_type, defvar, find_file, query_location, RXML.Tag,
  RXML.Frame, MODULE_LOCATION, MODULE_TAG, RequestID, http_string_answer, roxen module.
---

# Roxen Modules

## When to Use

- Reading or modifying a Roxen module
- Writing an RXML tag, or a module that serves content
- Tracing which module handles a URL or request
- Determining whether Pike files in a tree are Roxen modules

Verified against the Roxen source, branches `6.3` and `8.3.806`. Counts below are measured
across the 170 module files in `server/modules` and `server/more_modules`.

## File Encoding

Roxen sources are **ISO-8859-1**, not UTF-8 — most carry a latin-1 `©` in the copyright
header. GNU `grep` and `ripgrep` both search them correctly, so no special flag is needed
to read them.

It matters when **writing**: preserve the existing encoding. Rewriting a latin-1 file as
UTF-8 silently changes those bytes and leaves the tree mixed-encoding. Check before
editing:

```bash
file server/modules/filesystems/filesystem.pike
# ISO-8859 text
```

## Recognising a Module

Not every `.pike` file in a Roxen tree is a module. Check these, most reliable first:

| Signal | Files | Notes |
|--------|-------|-------|
| `constant module_type = MODULE_…;` | 134 / 170 | **Strongest.** Also says what kind |
| `inherit "module";` | 129 / 170 | **`"module"`, not `"module.pike"`** |
| `#include <module.h>` | 126 / 170 | Angle-bracket include from `server/etc/include/` |
| `defvar(...)` | 92 / 170 | Declares configuration variables |

> **Do not detect on `inherit "module.pike"`.** That spelling appears in exactly **1 of
> 170** files. Pike resolves `inherit "module"` to the `module.pike` program without the
> extension; the extensionless form is idiomatic.

Real header, from `server/modules/filesystems/filesystem.pike`:

```pike
inherit "module";
inherit "socket";

constant cvs_version= "$Id: … $";
constant thread_safe=1;

#include <module.h>
#include <roxen.h>
#include <stat.h>
#include <request_trace.h>
```

Multiple inherits are normal. Angle-bracket includes resolve from `server/etc/include/`.

## The `module_type` Taxonomy

From `server/etc/include/module_constants.h`. It is a **bitfield** — a module can declare
several kinds at once (`MODULE_LOCATION | MODULE_TAG`), so read every bit.

| Constant | Bit | Role |
|----------|-----|------|
| `MODULE_ZERO` | 0 | No type; utility or base module |
| `MODULE_EXTENSION` | 1<<0 | Handles a URL extension |
| `MODULE_LOCATION` | 1<<1 | Mounted at a path; serves files |
| `MODULE_URL` | 1<<2 | Rewrites or intercepts URLs |
| `MODULE_FILE_EXTENSION` | 1<<3 | Claims file extensions |
| `MODULE_TAG` (= `MODULE_PARSER`) | 1<<4 | Provides RXML tags |
| `MODULE_LAST` / `MODULE_FIRST` | 1<<5 / 1<<6 | Runs last / first |
| `MODULE_AUTH` | 1<<7 | Authentication |
| `MODULE_MAIN_PARSER` | 1<<8 | Main content parser |
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

`MODULE_PARSER` is a compatibility alias for `MODULE_TAG` — the same bit.

## Callbacks

| Callback | Files | Purpose |
|----------|-------|---------|
| `create()` | 100 | Declare `defvar()` configuration variables |
| `start()` | 83 | Module enabled or reloaded |
| `status()` | 50 | HTML status for the admin interface |
| `find_file(path, id)` | 23 | **`MODULE_LOCATION`**: serve a file |
| `stop()` | 18 | Cleanup on disable |
| `filter(result, id)` | 13 | **`MODULE_FILTER`**: post-process a response |
| `first_try(id)` | 11 | **`MODULE_FIRST`**: intercept early |
| `query_location()` | 9 | **`MODULE_LOCATION`**: the mount path |
| `parse_rxml(...)` | 4 | RXML parsing entry point |

## Serving Content: `find_file` and Response Mappings

A `MODULE_LOCATION` module mounts at `query_location()` and answers with `find_file()`:

```pike
#include <module.h>
inherit "module";

constant module_type = MODULE_LOCATION;
constant module_name = "My Filesystem";

void create() {
  defvar("mountpoint", "/files/", "Mount point", TYPE_LOCATION,
         "Where this module is mounted.");
}

string query_location() { return query("mountpoint"); }

mixed find_file(string path, RequestID id) {
  if (path == "hello")
    return Roxen.http_string_answer("Hello", "text/plain");
  return 0;      // 0 = not mine, keep looking
}
```

`path` is relative to the mount point. Returning `0` passes the request on.

Response helpers live in `server/etc/modules/Roxen.pmod`. Signatures, verbatim:

```pike
mapping(string:mixed) http_string_answer(string text, string|void type)   // default text/html
mapping(string:mixed) http_low_answer(int status_code, string data)
mapping(string:mixed) http_status(int status_code, void|string message, mixed... args)
mapping http_redirect(string url, RequestID|void id, multiset|void prestates,
                      mapping|void variables, void|int http_code)
string http_status_message(int status_code)
```

By usage across the bundled modules: `http_status` (101), `http_string_answer` (34),
`http_redirect` (19), `http_low_answer` (19), `http_encode_url` (14),
`http_rxml_answer` (9), `http_pipe_in_progress` (9).

Use `Roxen.http_rxml_answer()` when the returned content should itself be RXML-parsed.

## Writing RXML Tags

A tag is a class inheriting `RXML.Tag`, containing a nested `Frame` class. Real example,
from `server/modules/tags/countdown.pike`, unmodified:

```pike
class TagCountdown {
  inherit RXML.Tag;
  constant name = "countdown";
  constant flags = RXML.FLAG_EMPTY_ELEMENT;

  class Frame {
    inherit RXML.Frame;

    array do_return(RequestID id) {
      result = countdown(args, id);
      return 0;
    }
  }
}
```

- `constant name` is the RXML tag name (`<countdown/>` here)
- Inside `Frame`: `args` is the tag's attribute mapping, `content` its body, and assigning
  `result` produces the output. Return `0` from `do_return` when done.
- `CACHE(seconds)` (from `roxen.h`, expands to `REQUESTID->lower_max_cache(seconds)`)
  limits how long the result may be cached.

> **The class must be named `Tag*`.** `query_tag_set()` in `server/base_server/module.pike`
> discovers tags with `glob("Tag*", indices(this_object()))`, then keeps those that are
> `is_RXML_Tag`. A class named `CountdownTag` is **silently ignored** — no error, the tag
> simply never exists. 132 of the 139 tag classes in `server/modules/tags/` follow this.
>
> To register a tag that does not follow the naming rule, build a tag set explicitly:
> ```pike
> RXML.TagSet(this_module(), "_user_tag", ({ UserTagContents() }));
> ```

Inheritance counts across `server/modules/tags/`: `RXML.Tag` 163, `RXML.Frame` 118,
`RXML.Value` 16, `RXML.Scope` 4.

Flags by usage: `FLAG_EMPTY_ELEMENT` (51), `FLAG_DONT_RECOVER` (14), `FLAG_CUSTOM_TRACE`
(5), `FLAG_SOCKET_TAG` (4), `FLAG_PROC_INSTR` (4), `FLAG_DONT_CACHE_RESULT` (4).

## The `RequestID` Object

`id` carries the request. Most-used members across the bundled modules:

| Member | Uses | What it is |
|--------|------|-----------|
| `id->misc` | 804 | Per-request scratch mapping — where modules stash state |
| `id->not_query` | 184 | The path part of the URL, without the query string |
| `id->conf` | 163 | The `Configuration` object for this virtual server |
| `id->variables` | 89 | Form and query variables |
| `id->method` | 69 | `"GET"`, `"POST"`, … |
| `id->real_variables` | 59 | Variables before any aliasing |
| `id->prestate` | 47 | Prestate multiset from the URL |
| `id->request_headers` | 37 | Incoming headers |
| `id->raw_url` | 33 | The unprocessed URL |
| `id->cookies` | 31 | Cookies |
| `id->realfile` | 27 | Filesystem path, when one applies |
| `id->remoteaddr` | 26 | Client address |

`id->misc` dominates because it is the conventional channel for passing data between
modules within one request.

## Configuration with `defvar`

```pike
void create() {
  defvar("mountpoint", "/files/", "Mount point", TYPE_LOCATION, "Help text.");
  defvar("enabled", 1, "Enabled", TYPE_FLAG, "Turn the module on.");
}
```

Read with `query("name")`, or the `QUERY(name)` macro. `QUERY()` used to be a valid lvalue
and no longer is — write with `set("var", value)`.

`TYPE_*` constants from `module.h`:

```
TYPE_STRING  TYPE_FILE  TYPE_INT  TYPE_DIR  TYPE_STRING_LIST  TYPE_MULTIPLE_STRING
TYPE_INT_LIST  TYPE_MULTIPLE_INT  TYPE_FLAG  TYPE_TOGGLE  TYPE_DIR_LIST
TYPE_LOCATION  TYPE_URL  TYPE_URL_LIST  TYPE_FILE_LIST  TYPE_PASSWORD  TYPE_TEXT
TYPE_TEXT_FIELD  TYPE_FONT  TYPE_FLOAT  TYPE_MODULE  TYPE_CUSTOM
```

`TYPE_FLAG`/`TYPE_TOGGLE`, `TYPE_STRING_LIST`/`TYPE_MULTIPLE_STRING`, and
`TYPE_INT_LIST`/`TYPE_MULTIPLE_INT` are pairs of aliases.

## Logging and Debugging

```pike
report_debug("...");     // 53 uses
report_error("...");     // 45
report_warning("...");   // 28
report_notice("...");    // 19
```

`#include <request_trace.h>` brings in `TRACE_ENTER` / `TRACE_LEAVE`, which annotate the
per-request trace shown when request tracing is enabled — the fastest way to see which
modules touched a request and in what order.

## Codebase Layout

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
server/base_server/   core: configuration.pike, roxen.pike, module.pike
server/etc/include/   module.h, module_constants.h, roxen.h, config.h
server/etc/modules/   Roxen.pmod — the http_* response helpers
```

The directory hints at a module's type, but confirm with `constant module_type`.

## Request Handling Order

1. `MODULE_FIRST` modules run `first_try()`
2. URL modules may rewrite the request
3. The `MODULE_LOCATION` module with the longest matching `query_location()` prefix gets
   `find_file()`
4. Content type is assigned, possibly by a `MODULE_TYPES` module
5. Parsers (`MODULE_TAG` / `MODULE_MAIN_PARSER`) run if the content type calls for it
6. `MODULE_FILTER` modules post-process via `filter()`
7. `MODULE_LOGGER` modules log

To find which module owns a path:

```bash
grep -rn 'query_location\|defvar("mountpoint"' --include='*.pike' .
```

## Checklist

- [ ] Identified modules by `constant module_type`, not by filename
- [ ] Used `inherit "module"` (no `.pike`)
- [ ] Checked every bit of `module_type` — it is a bitfield
- [ ] RXML tag classes named `Tag*`, or registered via an explicit `RXML.TagSet`
- [ ] `find_file` returns `0` for "not mine", a `Roxen.http_*` mapping otherwise

## Reference

- `references/module-anatomy.md` — annotated skeletons per module_type, includes, tracing
