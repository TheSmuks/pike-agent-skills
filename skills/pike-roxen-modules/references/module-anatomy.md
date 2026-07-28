# Roxen Module Anatomy

Verified against Roxen `6.3` and `8.3.806`.

## File encoding

Roxen sources are ISO-8859-1 (latin-1 `©` in the copyright header). GNU `grep` and
`ripgrep` search them correctly with no special flags. Preserve the encoding when editing
— rewriting a file as UTF-8 changes those bytes. Confirm with `file <path>`.

## Real module header

From `server/modules/filesystems/filesystem.pike`, unmodified:

```pike
// This is a roxen module. Copyright © 1996 - 2009, Roxen IS.

// This is a virtual "file-system".
// It will be located somewhere in the name-space of the server.
// Also inherited by some of the other filesystems.

inherit "module";
inherit "socket";

constant cvs_version= "$Id: baf6929760419c01da3e00e759dadbd86ca8ccff $";
constant thread_safe=1;

#include <module.h>
#include <roxen.h>
#include <stat.h>
#include <request_trace.h>
```

Points worth noting:

- `inherit "module";` — no `.pike` extension
- Multiple inherits are normal (`"socket"` here)
- Angle-bracket includes resolve from `server/etc/include/`
- `cvs_version` and `thread_safe` are conventional on nearly every module

## Common includes

| Include | Provides |
|---------|----------|
| `<module.h>` | `TYPE_*` constants, `QUERY()`, `GLOBVAR()`, `TAGDOCUMENTATION` |
| `<module_constants.h>` | the `MODULE_*` type bits (pulled in via `module.h`/`roxen.h`) |
| `<roxen.h>` | core Roxen definitions |
| `<config.h>` | build configuration |
| `<request_trace.h>` | `TRACE_ENTER` / `TRACE_LEAVE` request tracing macros |
| `<stat.h>` | stat helpers |

## Skeletons by module_type

### MODULE_LOCATION — serve files from a mount point

```pike
#include <module.h>
inherit "module";

constant module_type = MODULE_LOCATION;
constant module_name = "My Filesystem";

void create() {
  defvar("mountpoint", "/files/", "Mount point", TYPE_LOCATION,
         "Where in the virtual filesystem this module appears.");
}

string query_location() { return query("mountpoint"); }

mixed find_file(string path, RequestID id) {
  // return a string, a Stdio.File, a response mapping, or 0 for "not mine"
  return 0;
}
```

### MODULE_TAG — provide RXML tags

```pike
#include <module.h>
inherit "module";

constant module_type = MODULE_TAG;
constant module_name = "My Tags";

// RXML_CONTEXT refers to the current RXML evaluation context.
```

Tag modules live in `server/modules/tags/` in the bundled tree — 33 files, the largest
single group after `graphics`.

### MODULE_FILTER — post-process responses

```pike
constant module_type = MODULE_FILTER;

mapping filter(mapping result, RequestID id) {
  // mutate and return result, or 0 to leave it untouched
  return 0;
}
```

### MODULE_FIRST — intercept before normal handling

```pike
constant module_type = MODULE_FIRST;

mixed first_try(RequestID id) {
  return 0;   // 0 = continue to normal handling
}
```

### MODULE_PROVIDER — offer services to other modules

```pike
constant module_type = MODULE_PROVIDER;
string query_provides() { return "my-service"; }
```

## Combining types

`module_type` is a bitfield, so combinations are normal:

```pike
constant module_type = MODULE_LOCATION | MODULE_TAG;
```

Such a module both mounts at a path and contributes RXML tags — read every bit before
assuming what a module does.

## Configuration variables

```pike
void create() {
  defvar("name", default_value, "Human Label", TYPE_STRING, "Help text.");
}
```

Read with `query("name")`, or the `QUERY(name)` macro which expands to `query("name")`.
`QUERY()` used to be a valid lvalue; it no longer is — use `set("var", value)` to write.

Available `TYPE_*` constants from `module.h`:

```
TYPE_STRING  TYPE_FILE  TYPE_INT  TYPE_DIR  TYPE_STRING_LIST  TYPE_MULTIPLE_STRING
TYPE_INT_LIST  TYPE_MULTIPLE_INT  TYPE_FLAG  TYPE_TOGGLE  TYPE_DIR_LIST
TYPE_LOCATION  TYPE_URL  TYPE_URL_LIST  TYPE_FILE_LIST  TYPE_PASSWORD  TYPE_TEXT
TYPE_TEXT_FIELD  TYPE_FONT  TYPE_FLOAT  TYPE_MODULE  TYPE_CUSTOM
```

`TYPE_FLAG` and `TYPE_TOGGLE` are the same value, as are `TYPE_STRING_LIST` /
`TYPE_MULTIPLE_STRING` and `TYPE_INT_LIST` / `TYPE_MULTIPLE_INT`.

## Tracing which module handles a request

1. `MODULE_FIRST` modules run `first_try()` first.
2. URL modules may rewrite the request.
3. The `MODULE_LOCATION` module whose `query_location()` is the longest matching prefix
   gets `find_file()`.
4. Content type is assigned, potentially by a `MODULE_TYPES` module supplying
   `type_from_extension`.
5. Parsers (`MODULE_TAG` / `MODULE_MAIN_PARSER`) run if the content type calls for it.
6. `MODULE_FILTER` modules post-process via `filter()`.
7. `MODULE_LOGGER` modules log.

To find the module owning a path, search for its mount point:

```bash
grep -rn 'query_location\|defvar("mountpoint"' --include='*.pike' .
```

## RXML tag skeleton

```pike
#include <module.h>
inherit "module";

constant module_type = MODULE_TAG;
constant module_name = "My Tags";

class TagGreet {                        // MUST be named Tag*
  inherit RXML.Tag;
  constant name = "greet";              // <greet name="..."/>
  constant flags = RXML.FLAG_EMPTY_ELEMENT;

  class Frame {
    inherit RXML.Frame;

    array do_return(RequestID id) {
      CACHE(60);                        // cacheable for 60s
      result = "Hello, " + (args->name || "world");
      return 0;
    }
  }
}
```

Inside `Frame`:

| Name | What it is |
|------|-----------|
| `args` | mapping of the tag's attributes |
| `content` | the tag body (for non-empty elements) |
| `result` | assign to produce output |
| `id` | the `RequestID` passed to `do_return` |

Drop `FLAG_EMPTY_ELEMENT` for a container tag `<greet>…</greet>`, and read `content`.

### Tag discovery

`query_tag_set()` (`server/base_server/module.pike`) does:

```pike
filter(rows(this_object(), glob("Tag*", indices(this_object()))), …)
```

then keeps entries whose `is_RXML_Tag` is true. Consequences:

- A tag class **not** named `Tag*` is silently skipped — no warning, the tag just does not
  exist. This is the most common reason a newly written tag "does nothing".
- To register such a class anyway, construct a tag set explicitly:
  ```pike
  RXML.TagSet(this_module(), "_user_tag", ({ UserTagContents() }));
  ```
  `server/modules/tags/rxmltags.pike` does this for its `IfIs` and `UserTagContents`
  classes.

## Request tracing

```pike
#include <request_trace.h>
```

`TRACE_ENTER` / `TRACE_LEAVE` add entries to the per-request trace. With request tracing
enabled, that trace shows every module that touched the request and in what order — the
quickest way to answer "why did this URL return that?".

Logging, by usage across the bundled modules:

```pike
report_debug("...");     // 53
report_error("...");     // 45
report_warning("...");   // 28
report_notice("...");    // 19
```
