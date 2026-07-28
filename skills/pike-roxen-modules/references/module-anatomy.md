# Roxen Module Anatomy

Verified against Roxen `6.3` and `8.3.806`.

## Searching a Roxen tree

Roxen sources are ISO-8859-1. Plain `grep` treats most of them as binary and reports
nothing while exiting `1`. Use one of:

```bash
grep -a  -rn 'constant module_type' .
LC_ALL=C grep -rn 'constant module_type' .
rg --text 'constant module_type' .
```

Verified on `server/modules/filesystems/filesystem.pike`: `grep -c inherit` finds nothing
(exit 1); `grep -a -c inherit` finds 3.

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
grep -a -rn 'query_location\|defvar("mountpoint"' --include='*.pike' .
```

## Unknown extensions

Roxen has no built-in table mapping arbitrary extensions to behaviour. A
`MODULE_FILE_EXTENSION` module can claim extensions via `query_file_extensions()` and
`handle_file_extension()`; `configuration.pike` builds the extension → handler map from
those. **No module bundled with Roxen implements that hook**, so any hit is custom code.

```bash
grep -a -rn 'query_file_extensions\|handle_file_extension' --include='*.pike' .
```

If nothing claims the extension and no content-type rule matches, the file is served as-is.
