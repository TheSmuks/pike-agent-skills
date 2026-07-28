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

mapping(string:int) seen = ([]);
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
  mixed r;
  if (catch { r = master()->resolv(name); }) return 0;
  if (undefinedp(r) || !r) return 0;
  if (programp(r)) {
    string d = Program.defined(r);
    if (d) return strip_line(d);
  }
  // For module objects (dirnode/joinnode) Program.defined() would report
  // master.pike, so find the module on disk instead.
  return locate_module(name);
}

//! Resolve a string inherit/import relative to the including file's directory.
//! Pike resolves `inherit "Foo"` against the *inheriting file's* directory, not
//! the current working directory.
string resolve_string_ref(string ref, string from_file)
{
  string dir = dirname(from_file);
  if (dir == "") dir = ".";
  foreach (({ ".pike", ".pmod", ".so", "" }), string ext) {
    string cand = combine_path(dir, ref + ext);
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

  foreach (extract_refs(src), array ref) {
    [string kind, string name, int is_string] = ref;
    if (kind == "import" && !follow_imports && depth > 0) continue;

    string target = is_string ? resolve_string_ref(name, file)
                              : resolve_dotted(name, file);

    // A bare name that resolves to nothing is very often a class defined in
    // this same file (Pike allows `inherit LocalClass;`). Say so rather than
    // reporting a spurious unresolved reference.
    int local_class = 0;
    if (!target && !is_string && !has_value(name, ".") &&
        has_value(src, "class " + name))
      local_class = 1;
    mapping entry = ([
      "kind": kind,
      "name": is_string ? "\"" + name + "\"" : name,
      "resolved": target ? tidy(target) : 0,
    ]);
    if (local_class) entry->local_class = 1;
    if (target && is_system(target)) entry->system = 1;

    // Do not descend into installed modules unless asked: a single stdlib
    // import otherwise drags in the whole runtime's inherit tree.
    int recurse = ((kind == "inherit") || follow_imports) &&
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
    string mark = e->kind == "import" ? "import" : "inherit";
    string note = "";
    if (e->repeat)      note = "  (already shown)";
    else if (e->system) note = "  [installed module]";
    string dest = e->resolved ? e->resolved
                : (e->local_class ? "(class in this file)" : "UNRESOLVED");
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
    else if (has_prefix(a, "--depth=")) max_depth = (int)a[8..];
    else if (a == "-h" || a == "--help") {
      write(#"pike-resolve — trace Pike inherit/import chains to source files

Usage:
  pike -M <root> pike-resolve.pike [options] <file.pike|Dotted.Name>

Options:
  --static      skip the runtime pass (use when the target will not compile)
  --imports     follow imports transitively as well as inherits
  --system      descend into installed modules too (noisy; off by default)
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

  string mp = Program.defined(object_program(master()));
  if (mp) install_root = dirname(dirname(strip_line(mp)));

  string target = rest[0];
  string file = Stdio.is_file(target) ? target : resolve_dotted(target);
  if (!file) {
    werror("pike-resolve: cannot resolve %O\n"
           "  Is its root on the module path? Try: pike -M <root> ...\n", target);
    return 1;
  }

  mapping result = ([ "target": target, "file": tidy(file) ]);

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
      if (!e->resolved && !e->local_class) unresolved++;
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
