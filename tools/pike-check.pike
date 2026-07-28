#!/usr/bin/env pike
//! Check that Pike code compiles, resolving inherits, imports and includes.
//!
//! Reports every compile error with file and line. Exits non-zero when the
//! code is wrong.
//!
//! **Roxen.** Roxen's runtime is bootstrapped, not importable: `roxenloader`
//! installs ~145 constants and swaps in `roxen_master.pike` before modules like
//! `Roxen.pmod` or `RXML.pmod` will compile. So Roxen code cannot be checked by
//! stock Pike alone.
//!
//! When a Roxen install is available this delegates to it — `./start --program`
//! runs a program inside the real, booted Roxen environment, using Roxen's own
//! modules and its own bundled Pike. Nothing is stubbed.
//!
//! When no install is configured, Roxen references are reported as
//! **unverified warnings**, never silently ignored, and the exit status says the
//! check was incomplete. A clean run of your own code is not a claim that its
//! Roxen calls are correct.
//!
//! Usage:
//!   pike tools/pike-check.pike [options] <file.pike> [more.pike ...]
//!
//! Options:
//!   --roxen=<dir>   Roxen install (the directory containing ./start)
//!   -M <dir>        extra module path root (repeatable)
//!   -I <dir>        extra include path root (repeatable)
//!   --quiet         only report problems
//!   -h, --help

constant description = "Check that Pike code compiles, including Roxen code.";

int quiet = 0;
array(string) exclude_globs = ({ "*/.git/*", "*/build/*", "*/.build/*", "*/node_modules/*" });
string roxen_dir;
array(string) extra_M = ({});
array(string) extra_I = ({});

//! Identifiers supplied by the Roxen runtime rather than by Pike. Used to tell
//! "your code is wrong" from "Roxen was not available to check against".
multiset(string) roxen_symbols = (<
  "Roxen", "RXML", "RequestID", "Configuration", "RoxenModule", "Master",
  "roxen", "roxenp", "roxenloader", "Protocol", "ModuleInfo", "ArgCache",
  "DBManager", "Stat", "Privs", "Font", "FontHandler", "CacheEntry",
  "report_debug", "report_error", "report_warning", "report_notice",
  "report_fatal", "cache", "cache_lookup", "cache_set", "cache_remove",
  "parse_html", "http_decode_string", "utf8_string", "LocaleString",
  "_cur_rxml_context", "ErrorContainer", "AdminUser", "SSLProtocol",
  "WebSocketAPI", "Concurrent", "CFUserDBModule", "NewLDAP",
>);

//! Locate a Roxen install. A real install has ./start and a bundled Pike
//! under lib/; a bare source checkout has ./start but no lib/.
string find_roxen()
{
  array(string) candidates = ({});
  if (roxen_dir) candidates += ({ roxen_dir });
  if (getenv("ROXEN_DIR")) candidates += ({ getenv("ROXEN_DIR") });
  candidates += ({ "/usr/local/roxen", "/opt/roxen", "/usr/lib/roxen",
                   combine_path(getenv("HOME") || "/", "roxen") });

  foreach (candidates, string c) {
    if (!c || !Stdio.is_dir(c)) continue;
    // Accept either <dir>/start or <dir>/server/start.
    foreach (({ "start", "server/start" }), string s)
      if (Stdio.is_file(combine_path(c, s))) return c;
  }
  return 0;
}

//! True when the install bundles its own Pike, which is what makes its module
//! set actually compilable.
int has_bundled_pike(string dir)
{
  return Stdio.is_file(combine_path(dir, "lib/master.pike")) ||
         Stdio.is_file(combine_path(dir, "lib/pike/master.pike"));
}

//! Collect Pike source files under a directory, recursively.
//! .cmod is deliberately excluded: it is C, compiled by `pike -x precompile`,
//! not by the Pike compiler.
array(string) collect(string path)
{
  if (Stdio.is_file(path)) return ({ path });
  if (!Stdio.is_dir(path)) return ({});

  array(string) out = ({});
  foreach (sort(get_dir(path) || ({})), string e) {
    if (e == "." || e == "..") continue;
    string full = combine_path(path, e);
    int skip = 0;
    foreach (exclude_globs, string g) if (glob(g, "/" + full)) skip = 1;
    if (skip) continue;

    if (Stdio.is_dir(full)) out += collect(full);
    else if (has_suffix(e, ".pike") || has_suffix(e, ".pmod")) out += ({ full });
  }
  return out;
}

//! Headers supplied by Roxen rather than by Pike.
multiset(string) roxen_headers = (<
  "module.h", "roxen.h", "config.h", "request_trace.h", "version.h",
  "security.h", "stat.h", "module_constants.h", "variables.h", "macros.h",
>);

//! Find #include directives the compiler will not be able to resolve.
//! Checked up front: an unresolvable include makes compile_string() throw
//! before the error handler can report anything useful.
array(array(string)) bad_includes(string src, string file)
{
  array(array(string)) out = ({});
  foreach (src / "\n"; int n; string line) {
    string t = String.trim_all_whites(line);
    if (!has_prefix(t, "#include")) continue;
    string rest = String.trim_all_whites(t[8..]);
    string name; int angled = 0;
    if (has_prefix(rest, "<")) { int e = search(rest, ">"); if (e > 0) { name = rest[1..e-1]; angled = 1; } }
    else if (has_prefix(rest, "\"")) { int e = search(rest, "\"", 1); if (e > 0) name = rest[1..e-1]; }
    if (!name) continue;

    int found = 0;
    if (!angled) {
      string d = dirname(file); if (d == "") d = ".";
      if (Stdio.is_file(combine_path(d, name))) found = 1;
    }
    if (!found)
      foreach (master()->pike_include_path, string root)
        if (Stdio.is_file(combine_path(root, name))) { found = 1; break; }

    if (!found) out += ({ ({ name, (string)(n + 1), angled ? "1" : "0" }) });
  }
  return out;
}

//! Does this source reference Roxen at all?
int mentions_roxen(string src)
{
  foreach (({ "Roxen.", "RXML.", "RequestID", "inherit \"module\"",
              "<module.h>", "<roxen.h>", "roxenp(", "id->misc" }), string m)
    if (has_value(src, m)) return 1;
  return 0;
}

//! Pull "Undefined identifier X" names out of a compiler error blob.
multiset(string) undefined_names(string errs)
{
  multiset(string) out = (<>);
  foreach (errs / "\n", string line) {
    int pos = search(line, "Undefined identifier ");
    if (pos < 0) continue;
    string rest = line[pos + sizeof("Undefined identifier ")..];
    sscanf(rest, "%[A-Za-z_0-9]", string name);
    if (name && sizeof(name)) out[name] = 1;
  }
  return out;
}

//! Compile one file in-process, returning the error text ("" on success).
string compile_here(string file)
{
  string errs = "";
  object handler = class {
    string acc = "";
    void compile_error(string f, int l, string m) { acc += sprintf("%s:%d: %s\n", f, l, m); }
    void compile_warning(string f, int l, string m) { acc += sprintf("%s:%d: warning: %s\n", f, l, m); }
  }();

  mixed err = catch {
    compile_string(Stdio.read_file(file), combine_path(getcwd(), file), handler);
  };
  errs = handler->acc;
  if (err && errs == "")
    errs = sprintf("%s\n", describe_error(err));
  return errs;
}

//! Compile inside a real Roxen install, via its own ./start --program.
//! This is the only way to check Roxen code without stubbing: the environment
//! is booted exactly as the server boots it.
string compile_in_roxen(string file, string rdir)
{
  string server = Stdio.is_file(combine_path(rdir, "server/start"))
                    ? combine_path(rdir, "server") : rdir;

  string abs = combine_path(getcwd(), file);
  string runner = combine_path(server, ".pike-check-runner.pike");

  Stdio.write_file(runner, sprintf(#"
int main() {
  object h = class {
    string acc = \"\";
    void compile_error(string f, int l, string m) { acc += sprintf(\"%%s:%%d: %%s\\n\", f, l, m); }
    void compile_warning(string f, int l, string m) { acc += sprintf(\"%%s:%%d: warning: %%s\\n\", f, l, m); }
  }();
  mixed e = catch { compile_string(Stdio.read_file(%O), %O, h); };
  write(\"%%s\", h->acc);
  if (e && h->acc == \"\") write(\"%%s\\n\", describe_error(e));
  return 0;
}
", abs, abs));

  mapping res = Process.run(({ "./start", "--program", ".pike-check-runner.pike" }),
                            ([ "cwd": server ]));
  rm(runner);

  string out = (res->stdout || "") + (res->stderr || "");
  // Keep only lines about the file under test; Roxen's own boot chatter and any
  // errors inside Roxen's modules are not the user's problem.
  array(string) keep = ({});
  foreach (out / "\n", string l)
    if (has_value(l, abs) || has_value(l, file)) keep += ({ l });
  return keep * "\n";
}

int main(int argc, array(string) argv)
{
  array(string) files = ({});
  for (int i = 1; i < argc; i++) {
    string a = argv[i];
    if (has_prefix(a, "--roxen=")) roxen_dir = a[8..];
    else if (a == "-M" && i + 1 < argc) extra_M += ({ argv[++i] });
    else if (a == "-I" && i + 1 < argc) extra_I += ({ argv[++i] });
    else if (a == "--quiet") quiet = 1;
    else if (has_prefix(a, "--exclude=")) exclude_globs += ({ a[10..] });
    else if (a == "-h" || a == "--help") {
      write(#"pike-check — check that Pike code compiles

Usage:
  pike pike-check.pike [options] <file.pike> [more.pike ...]

Options:
  --roxen=<dir>   Roxen install (the directory containing ./start)
  -M <dir>        extra module path root (repeatable)
  -I <dir>        extra include path root (repeatable)
  --quiet         only report problems
  --exclude=<glob> skip matching paths (repeatable)
  -h, --help      this text

A directory argument is walked recursively; every .pike and .pmod under it is
checked. .cmod is skipped — that is C, built by `pike -x precompile`.

Exit status:
  0  everything compiled
  1  compile errors in your code
  2  compiled, but Roxen references could not be verified (no install configured)

Roxen code needs a real Roxen install: its runtime is bootstrapped by
roxenloader, so stock Pike cannot resolve Roxen.* or RXML.* on its own. Point
--roxen at your install and compilation happens inside it, via ./start
--program. Without one, Roxen references are reported as unverified warnings —
never silently accepted.
");
      return 0;
    }
    else files += ({ a });
  }

  if (!sizeof(files)) { werror("pike-check: need a file or directory (try --help)\n"); return 2; }

  // Expand directories.
  array(string) targets = ({});
  foreach (files, string f) {
    if (Stdio.is_dir(f)) {
      array(string) found = collect(f);
      if (!quiet) write("# %s: %d Pike file%s\n", f, sizeof(found),
                        sizeof(found) == 1 ? "" : "s");
      targets += found;
    } else targets += ({ f });
  }
  files = targets;
  if (!sizeof(files)) { werror("pike-check: no Pike files found\n"); return 2; }

  foreach (extra_M, string d) master()->add_module_path(d);
  foreach (extra_I, string d) master()->add_include_path(d);

  string rdir = find_roxen();
  int roxen_usable = rdir && has_bundled_pike(rdir);

  if (!quiet && rdir && !roxen_usable)
    write("note: %s looks like a Roxen source checkout, not an install "
          "(no bundled Pike under lib/)\n", rdir);

  int errors = 0, unverified = 0, ok_files = 0, bad_files = 0, warn_files = 0;

  foreach (files, string f) {
    if (!Stdio.is_file(f)) { werror("pike-check: no such file: %s\n", f); errors++; continue; }
    string src = Stdio.read_file(f);
    int needs_roxen = mentions_roxen(src);

    // Resolve includes first — an unresolvable one throws out of compile_string
    // and buries the real message in a backtrace.
    array(array(string)) missing_inc = ({});
    if (!(needs_roxen && roxen_usable)) missing_inc = bad_includes(src, f);
    if (sizeof(missing_inc)) {
      array(string) rox = ({}), other = ({});
      foreach (missing_inc, array(string) mi)
        if (roxen_headers[mi[0]]) rox += ({ mi[0] }); else other += ({ mi[0] });

      foreach (missing_inc, array(string) mi)
        if (!roxen_headers[mi[0]])
          write("%s:%s: cannot find include file %s\n", f, mi[1], mi[0]);

      if (sizeof(other)) { errors += sizeof(other); bad_files++; }
      if (sizeof(rox)) {
        unverified += sizeof(rox); warn_files++;
        write("\n!! %s: %d Roxen header%s could NOT be resolved: %s\n",
              f, sizeof(rox), sizeof(rox) == 1 ? "" : "s", sort(rox) * ", ");
        if (!rdir)
          write("   No Roxen install found. Pass --roxen=<dir>, or set ROXEN_DIR.\n");
        else if (!roxen_usable)
          write("   %s has no bundled Pike under lib/ — point --roxen at a real install.\n", rdir);
        write("   This file was NOT compiled; its correctness is unknown.\n");
      }
      continue;
    }

    string errs;
    if (needs_roxen && roxen_usable) {
      errs = compile_in_roxen(f, rdir);
      if (!quiet) write("# %s — checked inside Roxen at %s\n", f, rdir);
    } else {
      errs = compile_here(f);
    }

    if (errs == "" || !sizeof(String.trim_all_whites(errs))) {
      ok_files++;
      if (!quiet) write("%s: OK\n", f);
      continue;
    }

    // Split real errors from unresolved Roxen runtime symbols.
    multiset(string) undef = undefined_names(errs);

    // `import Roxen;` fails with "Module is neither mapping nor object" —
    // the message never names the module, so attribute it from the source.
    if (needs_roxen && !roxen_usable) {
      foreach (errs / "\n", string l) {
        if (!has_value(l, "Module is neither mapping nor object")) continue;
        foreach (({ "Roxen", "RXML" }), string m)
          if (has_value(src, "import " + m) || has_value(src, "inherit " + m))
            undef[m] = 1;
      }
    }
    multiset(string) roxen_undef = (<>);
    foreach (indices(undef), string n)
      if (roxen_symbols[n]) roxen_undef[n] = 1;

    array(string) real_lines = ({}), roxen_lines = ({});
    foreach (errs / "\n", string l) {
      if (l == "") continue;
      int is_roxen = 0;
      foreach (indices(roxen_undef), string n)
        if (has_value(l, "Undefined identifier " + n)) is_roxen = 1;
      if (sizeof(roxen_undef) && has_value(l, "Module is neither mapping nor object"))
        is_roxen = 1;
      if (is_roxen) roxen_lines += ({ l }); else real_lines += ({ l });
    }

    // Sweep up follow-on errors, but only those on a line that already has an
    // unresolved Roxen symbol. Filtering by message alone misattributes
    // consequences of the user's own mistakes.
    if (sizeof(roxen_undef)) {
      multiset(string) roxen_locs = (<>);
      foreach (roxen_lines, string l) {
        string loc;
        if (sscanf(l, "%s: %*s", loc) && loc) roxen_locs[loc] = 1;
      }
      array(string) filtered = ({});
      foreach (real_lines, string l) {
        string loc;
        int consequence =
          has_value(l, "Too many arguments") || has_value(l, "Indexing on illegal type") ||
          has_value(l, "Calling a void expression") || has_value(l, "Illegal program pointer") ||
          has_value(l, "Got     :") || has_value(l, "Expected:") || has_value(l, "Index   :");
        if (consequence && sscanf(l, "%s: %*s", loc) && loc && roxen_locs[loc])
          roxen_lines += ({ l });
        else filtered += ({ l });
      }
      real_lines = filtered;
    }

    foreach (real_lines, string l) write("%s\n", l);
    errors += sizeof(real_lines);
    if (sizeof(real_lines)) bad_files++;

    if (sizeof(roxen_undef)) {
      unverified += sizeof(roxen_undef);
      warn_files++;
      write("\n!! %s: %d Roxen reference%s could NOT be verified: %s\n",
            f, sizeof(roxen_undef), sizeof(roxen_undef) == 1 ? "" : "s",
            sort(indices(roxen_undef)) * ", ");
      foreach (roxen_lines, string l) write("     %s\n", l);
      if (!rdir)
        write("   No Roxen install found. Pass --roxen=<dir> (the directory\n"
              "   containing ./start), or set ROXEN_DIR.\n");
      else if (!roxen_usable)
        write("   %s has no bundled Pike under lib/, so its modules cannot be\n"
              "   compiled. Point --roxen at a real install.\n", rdir);
      write("   These are NOT confirmed correct — this check was incomplete.\n");
    }
  }

  if (sizeof(files) > 1 && !quiet)
    write("\n%d file%s checked: %d ok, %d with errors, %d with unverified Roxen\n",
          sizeof(files), sizeof(files) == 1 ? "" : "s", ok_files, bad_files, warn_files);

  if (errors) {
    write("\nFAILED: %d error%s in %d file%s\n", errors, errors == 1 ? "" : "s",
          bad_files, bad_files == 1 ? "" : "s");
    return 1;
  }
  if (unverified) {
    write("\nINCOMPLETE: your code compiled, but %d Roxen reference%s went "
          "unverified.\n", unverified, unverified == 1 ? "" : "s");
    return 2;
  }
  if (!quiet) write("\nOK: everything compiled\n");
  return 0;
}
