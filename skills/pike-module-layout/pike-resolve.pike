#!/usr/bin/env pike
//! Resolve Pike inherit and import chains to their source files.
//!
//! Answers "where does this actually come from?" deterministically, using
//! Pike's own resolver rather than guessing from filenames.
//!
//! Two passes, because they see different things:
//!
//!  - **runtime** — compiles the target and walks @[Program.inherit_tree],
//!    reporting @[Program.defined] for each. Authoritative: it is exactly what
//!    Pike loaded. Sees inherits only; `import` leaves no runtime trace.
//!  - **static** — tokenises the source with @[Parser.Pike.split] and reads the
//!    `inherit` / `import` statements as written, resolving each name. Sees
//!    imports, and still works when the file does not compile.
//!
//! Usage:
//!   pike -M <root> tools/pike-resolve.pike [options] <file.pike|Dotted.Name>
//!
//! Options:
//!   --static      skip the runtime pass (use when the target will not compile)
//!   --imports     follow imports transitively too, not just inherits
//!   --depth=N     limit recursion depth (default 10)
//!   --json        emit JSON
//!   -h, --help

constant description = "Resolve Pike inherit/import chains to source files.";

int max_depth = 10;
int want_json = 0;
int follow_imports = 0;
int static_only = 0;
int no_compile = 0;
string roxen_dir;

//! Ask Pike's own resolver where a name is defined, as "file:line".
//!
//! This is the only technique that can locate a *class inside* a module
//! (`Stdio.File` -> Stdio.pmod/module.pmod:181) or a symbol defined in C
//! (`_Stdio.Fd` -> src/modules/_Stdio/file.c:6331). Pure file lookup stops at
//! module granularity: it cannot tell `Stdio.File` from `Stdio.Buffer`, and
//! reports every statically-linked C module as unresolved.
//!
//! Compiler noise is silenced by @[master()->set_inhibit_compile_errors], set
//! up in @[main]. An earlier version of this script avoided `resolv()` on the
//! grounds that its errors "cannot be suppressed"; they can.
string resolve_via_runtime(string name)
{
  if (no_compile) return 0;
  mixed r;
  if (catch { r = master()->resolv(name); }) return 0;
  if (zero_type(r) || !r) return 0;
  program p = programp(r) ? r : (objectp(r) ? object_program(r) : 0);
  if (!p) return 0;
  string d;
  if (catch { d = Program.defined(p); }) return 0;
  return d;
}

mapping(string:int) seen = ([]);
array(string) include_roots = ({});
array(string) program_roots = ({});

//! Names bound at run time by the Roxen loader rather than provided by a file.
//! `Master` is `add_constant("Master", this)` in roxen_master.pike, so
//! `Master.Encoder` can never resolve to a path — reporting it as unresolved
//! would be misleading.
multiset(string) runtime_bound = (< "Master", "roxen", "roxenp", "Configuration",
                                    "RoxenModule", "Protocol", "ModuleInfo" >);

//! Resolve an #include. Angle form searches the include path; quote form is
//! relative to the including file first.
string resolve_include(string ref, int angled, string from_file)
{
  if (!angled) {
    string dir = dirname(from_file); if (dir == "") dir = ".";
    string cand = combine_path(dir, ref);
    if (Stdio.is_file(cand)) return cand;
  }
  foreach (include_roots + master()->pike_include_path, string root) {
    string cand = combine_path(root, ref);
    if (Stdio.is_file(cand)) return cand;
  }
  return 0;
}
int descend_system = 0;

//! Root of the Pike installation, derived from master.pike's own location.
//! Used to tell installed modules from project code. Note this must NOT be
//! "any module-path root": -M adds the project itself to that list.
string install_root;

//! True when @[path] belongs to the Pike installation rather than the project.
int is_system(string path)
{
  return path && install_root && has_prefix(path, install_root);
}

//! Locate a dotted module name on the module path, returning the file *or
//! directory* that provides it.
//!
//! Needed because @[master()->resolv] hands back a joinnode/dirnode object for
//! directory modules, whose @[object_program] is master's internal class — so
//! Program.defined() on it reports master.pike, not the module.
string locate_module(string name)
{
  array(string) parts = name / ".";
  foreach (master()->pike_module_path, string root) {
    string cur = root;
    int ok = 1;
    for (int i = 0; i < sizeof(parts); i++) {
      string seg = parts[i];
      string as_dir  = combine_path(cur, seg + ".pmod");
      string as_file = combine_path(cur, seg + ".pmod");
      string as_prog = combine_path(cur, seg + ".pike");
      if (Stdio.is_dir(as_dir))        { cur = as_dir; }
      else if (Stdio.is_file(as_file)) { cur = as_file; if (i < sizeof(parts)-1) { ok = 0; break; } }
      else if (Stdio.is_file(as_prog)) { cur = as_prog; if (i < sizeof(parts)-1) { ok = 0; break; } }
      else if (Stdio.is_file(combine_path(cur, seg + ".so")))
        { cur = combine_path(cur, seg + ".so"); if (i < sizeof(parts)-1) { ok = 0; break; } }
      else { ok = 0; break; }
    }
    if (ok) return cur;
  }
  return 0;
}

//! Normalise a path for display: absolute paths under the cwd become relative.
string tidy(string path)
{
  if (!path) return "?";
  string cwd = getcwd();
  if (has_prefix(path, cwd + "/")) return path[sizeof(cwd) + 1..];
  return path;
}

//! Strip the ":line" suffix @[Program.defined] appends.
string strip_line(string s)
{
  if (!s) return 0;
  int i = search(s, ":", sizeof(s) > 2 ? 2 : 0);
  return (i > 0) ? s[..i - 1] : s;
}

//! Resolve a dotted module name to a source path, or 0.
//! Leading-dot names (`._JSON`) are siblings of @[from_file]'s directory.
string resolve_dotted(string name, string|void from_file)
{
  if (has_prefix(name, ".") && from_file) {
    string dir = dirname(from_file);
    if (dir == "") dir = ".";
    string bare = name[1..];
    // .so covers compiled C modules (e.g. Standards.pmod/_JSON.so)
    foreach (({ ".pmod", ".pike", ".so", "" }), string ext) {
      string cand = combine_path(dir, bare + ext);
      if (Stdio.is_file(cand)) return cand;
    }
    return 0;
  }
  // Pure file lookup first. resolv() *compiles* the target, which is slow and,
  // for modules needing a runtime (Roxen's RXML), prints compiler errors we
  // cannot suppress. Locating the file answers "where does this live?" without
  // any of that.
  string located = locate_module(name);
  if (located) return located;

  // No resolv() fallback: it compiles the target, which prints compiler errors
  // for anything needing a runtime (Roxen's RXML) and cannot be silenced. File
  // lookup plus the parent-prefix fallback below answers the question without
  // compiling anything.

  // `RXML.Value` names a class *inside* RXML.pmod — there is no such file, so
  // fall back to the innermost parent that does exist on disk.
  array(string) parts = name / ".";
  while (sizeof(parts) > 1) {
    parts = parts[..sizeof(parts) - 2];
    string parent = locate_module(parts * ".");
    if (parent) {
      if (Stdio.is_dir(parent)) {
        string inner = combine_path(parent, "module.pmod");
        if (Stdio.is_file(inner)) return inner;
      }
      return parent;
    }
  }
  return 0;
}

//! Resolve a string inherit/import relative to the including file's directory.
//! Pike resolves `inherit "Foo"` against the *inheriting file's* directory, not
//! the current working directory.
string resolve_string_ref(string ref, string from_file)
{
  string dir = dirname(from_file);
  if (dir == "") dir = ".";
  // The including file's own directory first, then any extra program roots
  // (Roxen keeps the `module.pike` that modules inherit in server/base_server),
  // then Pike's own program path — the third root `pike --show-paths` prints,
  // which this script used to ignore entirely. Empty on a stock install, which
  // is why the gap went unnoticed; Roxen populates it.
  foreach (({ dir }) + program_roots + master()->pike_program_path, string d)
    foreach (({ ".pike", ".pmod", ".so", "" }), string ext) {
      string cand = combine_path(d, ref + ext);
      if (Stdio.is_file(cand)) return cand;
    }
  // Fall back to treating it as a module name.
  return resolve_dotted(replace(ref, "/", "."));
}

//! Statically extract inherit/import statements from source.
//! Returns ({ ({ "inherit"|"import", name_as_written, is_string_form }), ... })
array(array) extract_refs(string src)
{
  array(string) tok;
  if (catch { tok = Parser.Pike.split(src); }) return ({});

  array(array) out = ({});
  for (int i = 0; i < sizeof(tok); i++) {
    string t = tok[i];
    if (t != "inherit" && t != "import") continue;
    string kind = t;

    // Collect the tokens up to the terminating ';'.
    array(string) parts = ({});
    int j = i + 1;
    for (; j < sizeof(tok) && tok[j] != ";"; j++) {
      string p = tok[j];
      if (p == "" || p[0] == ' ' || p[0] == '\t' || p[0] == '\n') continue;
      if (has_prefix(p, "//") || has_prefix(p, "/*")) continue;
      parts += ({ p });
    }
    i = j;
    if (!sizeof(parts)) continue;

    // `inherit X : name;` — drop the alias.
    int colon = search(parts, ":");
    if (colon > 0) parts = parts[..colon - 1];
    if (!sizeof(parts)) continue;

    if (has_prefix(parts[0], "\"")) {
      string s = parts[0];
      out += ({ ({ kind, s[1..sizeof(s) - 2], 1 }) });
    } else {
      out += ({ ({ kind, parts * "", 0 }) });
    }
  }

  // #include lines are preprocessor directives, so Parser.Pike hands them back
  // as single tokens rather than as inherit-like statements.
  foreach (src / "\n", string line) {
    string t = String.trim_all_whites(line);
    if (!has_prefix(t, "#include")) continue;
    string rest = String.trim_all_whites(t[8..]);
    if (has_prefix(rest, "<")) {
      int e = search(rest, ">");
      if (e > 0) out += ({ ({ "include", rest[1..e-1], 2 }) });
    } else if (has_prefix(rest, "\"")) {
      int e = search(rest, "\"", 1);
      if (e > 0) out += ({ ({ "include", rest[1..e-1], 3 }) });
    }
  }
  return out;
}

//! Static walk: follow inherit (and optionally import) references from a file.
mapping walk_static(string file, int depth)
{
  mapping node = ([ "file": tidy(file), "refs": ({}) ]);
  if (depth > max_depth) { node->truncated = 1; return node; }

  // A .pmod *directory* is a module in its own right. Its code, if any, lives
  // in module.pmod inside it — follow that rather than trying to read the
  // directory as source.
  if (Stdio.is_dir(file)) {
    node->directory_module = 1;
    string inner = combine_path(file, "module.pmod");
    if (Stdio.is_file(inner)) {
      node->file = tidy(inner);
      file = inner;
    } else {
      node->note = "directory module, no module.pmod";
      return node;
    }
  }

  string src = Stdio.read_file(file);
  if (!src) { node->error = "unreadable"; return node; }

  array(array) refs = extract_refs(src);

  // Scopes through which a *bare* name in this file may be resolvable: the
  // file's own inherits and imports. `Stdio.pmod/module.pmod` does
  // `inherit _Stdio;` and later `inherit Fd;` — `Fd` exists only inside that
  // scope, so a global lookup calls it unresolved. Try each scope first.
  array(string) scopes = ({});
  foreach (refs, array r)
    if (!r[2] && r[0] != "include" && !has_value(r[1], "::")) scopes += ({ r[1] });

  foreach (refs, array ref) {
    [string kind, string name, int is_string] = ref;
    if (kind == "import" && !follow_imports && depth > 0) continue;

    // `Scope::Name` names a *named inherit's* scope, not a module path.
    // Splitting it on "." and looking for a file finds nothing, which is why
    // Calendar.Gregorian used to report four bogus unresolved references.
    string scope;
    if (!is_string && kind != "include" && has_value(name, "::"))
      scope = (name / "::")[0];

    string target;
    if (kind == "include")
      target = resolve_include(name, is_string == 2, file);
    else if (scope)
      target = 0;
    else
      target = is_string ? resolve_string_ref(name, file)
                         : resolve_dotted(name, file);

    // Pike's own resolver is the only thing that can pin down a class inside a
    // module, or a symbol implemented in C. Consult it for dotted/bare names;
    // it reports "file:line", which is strictly more than the file lookup can
    // ever return.
    string defined_at, via;
    if (kind != "include" && !is_string && !scope)
      defined_at = resolve_via_runtime(name);

    // Bare name, nothing found globally — try this file's own scopes.
    if (!target && !defined_at && kind != "include" && !is_string && !scope &&
        !has_value(name, "."))
      foreach (scopes, string s) {
        if (s == name || has_value(s, "::")) continue;
        string d = resolve_via_runtime(s + "." + name);
        if (d) { defined_at = d; via = s; break; }
      }

    // A bare name that resolves to nothing is very often a class defined in
    // this same file (Pike allows `inherit LocalClass;`). Say so rather than
    // reporting a spurious unresolved reference.
    int local_class = 0;
    if (!target && !defined_at && kind != "include" && !is_string &&
        !has_value(name, ".") && has_value(src, "class " + name))
      local_class = 1;

    int runtime_sym = 0;
    if (!target && !defined_at && kind != "include" && !is_string)
      runtime_sym = runtime_bound[(name / ".")[0]];

    // The file lookup falls back to the innermost *parent* that exists on disk,
    // so `Error.Generic -> Error.pmod` looked like a clean hit when it was only
    // the enclosing module. Say which it is.
    int approximate = target && defined_at &&
                      strip_line(defined_at) != target &&
                      !has_suffix(tidy(target), tidy(strip_line(defined_at)));

    mapping entry = ([
      "kind": kind,
      "name": (kind == "include")
                ? (is_string == 2 ? "<" + name + ">" : "\"" + name + "\"")
                : (is_string ? "\"" + name + "\"" : name),
      "resolved": target ? tidy(target) : (defined_at ? tidy(defined_at) : 0),
    ]);
    if (defined_at)  entry->defined_at = tidy(defined_at);
    if (via)         entry->via = via;
    if (approximate) entry->approximate = 1;
    if (scope)       entry->scope_ref = scope;
    if (local_class) entry->local_class = 1;
    if (runtime_sym) entry->runtime_bound = 1;
    if (target && is_system(target)) entry->system = 1;

    // Do not descend into installed modules unless asked: a single stdlib
    // import otherwise drags in the whole runtime's inherit tree.
    int recurse = ((kind == "inherit") || follow_imports) && (kind != "include") &&
                  (descend_system || !is_system(target));
    if (target && recurse && !seen[target]) {
      seen[target] = 1;
      entry->children = walk_static(target, depth + 1);
    } else if (target && seen[target]) {
      entry->repeat = 1;
    }
    node->refs += ({ entry });
  }
  return node;
}

void print_static(mapping node, string indent, int is_root)
{
  if (is_root) write("%s%s\n", indent, node->file);
  if (node->error) { write("%s  (%s)\n", indent, node->error); return; }

  if (node->note) write("%s  (%s)\n", indent, node->note);
  foreach (node->refs, mapping e) {
    string mark = e->kind;
    string note = "";
    if (e->repeat)      note = "  (already shown)";
    else if (e->system) note = "  [installed module]";
    string dest;
    if (e->scope_ref)          dest = "(scope of named inherit " + e->scope_ref + ")";
    else if (e->defined_at)    dest = e->defined_at;
    else if (e->resolved)      dest = e->resolved;
    else if (e->local_class)   dest = "(class in this file)";
    else if (e->runtime_bound) dest = "(Roxen runtime constant)";
    else                       dest = "UNRESOLVED";
    if (e->approximate) note += "  (file lookup stopped at " + e->resolved + ")";
    if (e->via) note += "  (via " + e->via + ")";
    write("%s  %s %s -> %s%s\n", indent, mark, e->name, dest, note);
    if (e->children) print_static(e->children, indent + "    ", 0);
  }
}

//! Runtime walk of the real inherit tree.
void print_runtime_tree(array tree, string indent)
{
  if (!arrayp(tree) || !sizeof(tree)) return;
  foreach (tree, mixed node) {
    if (programp(node)) {
      string d = Program.defined(node);
      write("%s%s\n", indent, d ? tidy(d) : sprintf("%O", node));
    } else if (arrayp(node)) {
      print_runtime_tree(node, indent + "  ");
    }
  }
}

int main(int argc, array(string) argv)
{
  array(string) rest = ({});
  foreach (argv[1..], string a) {
    if (a == "--json") want_json = 1;
    else if (a == "--imports") follow_imports = 1;
    else if (a == "--static") static_only = 1;
    else if (a == "--system") descend_system = 1;
    else if (a == "--no-compile") no_compile = 1;
    else if (has_prefix(a, "--roxen=")) roxen_dir = a[8..];
    else if (has_prefix(a, "--depth=")) max_depth = (int)a[8..];
    else if (a == "-h" || a == "--help") {
      write(#"pike-resolve — trace Pike inherit/import chains to source files

Usage:
  pike -M <root> pike-resolve.pike [options] <file.pike|Dotted.Name>

Options:
  --static      skip the runtime pass (use when the target will not compile)
  --imports     follow imports transitively as well as inherits
  --system      descend into installed modules too (noisy; off by default)
  --no-compile  never call resolv(); pure file lookup. Faster, but cannot
                locate a class inside a module or a symbol defined in C
  --roxen=<dir> resolve Roxen.* / RXML.* and <module.h> against a Roxen tree
  --depth=N     limit recursion depth (default 10)
  --json        emit JSON
  -h, --help    this text

The runtime pass is authoritative for inherits but cannot see imports.
The static pass sees both and works on code that does not compile.
");
      return 0;
    }
    else rest += ({ a });
  }

  if (!sizeof(rest)) {
    werror("pike-resolve: need a file or dotted module name (try --help)\n");
    return 2;
  }

  // resolv() compiles what it touches, and a module needing a runtime it does
  // not have (Roxen's RXML) will emit compiler errors while doing so. Silence
  // them: the diagnostics belong to the target's dependencies, not to the
  // question being asked here.
  if (!no_compile) master()->set_inhibit_compile_errors(lambda(){});

  string mp = Program.defined(object_program(master()));
  if (mp) install_root = dirname(dirname(strip_line(mp)));

  // Roxen keeps its modules and headers outside the Pike module path. Adding
  // them makes Roxen.*, RXML.* and <module.h> resolvable — resolution is a file
  // lookup, so this works without booting the Roxen runtime.
  if (roxen_dir) {
    string base = Stdio.is_dir(combine_path(roxen_dir, "server"))
                    ? combine_path(roxen_dir, "server") : roxen_dir;
    foreach (({ "base_server", "." }), string d) {
      string full = combine_path(base, d);
      if (Stdio.is_dir(full)) program_roots += ({ full });
    }
    foreach (({ "etc/modules" }), string d) {
      string full = combine_path(base, d);
      if (Stdio.is_dir(full)) master()->add_module_path(full);
    }
    foreach (({ "etc/include" }), string d) {
      string full = combine_path(base, d);
      if (Stdio.is_dir(full)) { master()->add_include_path(full); include_roots += ({ full }); }
    }
  }

  string target = rest[0];
  string file = Stdio.is_file(target) ? target : resolve_dotted(target);

  // Where the *named thing* actually lives. For a class inside a module this
  // differs from `file`, which can only ever be the enclosing module.
  string target_defined_at = Stdio.is_file(target) ? 0 : resolve_via_runtime(target);
  if (!file && target_defined_at) {
    string p = strip_line(target_defined_at);
    if (p && Stdio.is_file(p)) file = p;
  }
  if (!file) {
    werror("pike-resolve: cannot resolve %O\n"
           "  Is its root on the module path? Try: pike -M <root> ...\n", target);
    return 1;
  }

  mapping result = ([ "target": target, "file": tidy(file) ]);
  if (target_defined_at) {
    result->defined_at = tidy(target_defined_at);
    if (!want_json)
      write("# %s is defined at %s\n\n", target, tidy(target_defined_at));
  }

  // --- runtime pass -------------------------------------------------------
  array runtime_flat = ({});
  if (!static_only) {
    program p;
    // NB: casting a *relative* path to program resolves it against the
    // casting file's own directory (this script), not the cwd — the same rule
    // as `inherit "Foo"`. Always cast an absolute path.
    mixed err = catch {
      p = Stdio.is_file(target) ? (program)combine_path(getcwd(), target)
                                : master()->resolv(target);
    };
    if (!err && programp(p)) {
      foreach (Program.all_inherits(p), program q) {
        string d = Program.defined(q);
        if (d) runtime_flat += ({ tidy(strip_line(d)) });
      }
      result->runtime = runtime_flat;
      if (!want_json) {
        write("# runtime inherit chain (authoritative)\n");
        write("%s\n", tidy(file));
        array tree;
        if (!catch { tree = Program.inherit_tree(p); })
          print_runtime_tree(tree[1..], "  ");
        else
          foreach (runtime_flat, string f) write("  %s\n", f);
        write("\n");
      }
    } else if (!want_json) {
      if (!err)
        write("# runtime inherit chain: n/a — %O is a module, not a program\n"
              "#   (modules have no inherit chain; showing the static view)\n\n",
              target);
      else
        write("# runtime inherit chain: unavailable (target does not compile here)\n"
              "#   falling back to the static pass only\n\n");
    }
  }

  // --- static pass --------------------------------------------------------
  seen = ([ file: 1 ]);
  mapping stat = walk_static(file, 0);
  result->static = stat;

  if (want_json) {
    write("%s\n", Standards.JSON.encode(result, Standards.JSON.HUMAN_READABLE));
    return 0;
  }

  write("# static inherit%s chain (as written in source)\n",
        follow_imports ? "/import" : "");
  print_static(stat, "", 1);

  // Report anything the static pass could not resolve — these are the
  // interesting cases: a missing module path root, or a typo.
  int unresolved = 0;
  void count_unresolved(mapping n) {
    foreach (n->refs || ({}), mapping e) {
      if (!e->resolved && !e->local_class && !e->runtime_bound && !e->scope_ref)
        unresolved++;
      if (e->children) count_unresolved(e->children);
    }
  };
  count_unresolved(stat);
  if (unresolved) {
    write("\n%d unresolved reference%s — add the missing root with -M, "
          "or check the name\n", unresolved, unresolved == 1 ? "" : "s");
    return 1;
  }
  return 0;
}
