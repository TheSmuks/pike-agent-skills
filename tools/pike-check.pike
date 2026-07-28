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
//! **Known limitation.** A `.pmod` submodule compiled standalone loses its place
//! in the module namespace, so sibling references resolved through the parent
//! (`Calendar.pmod/Timezone.pmod` reaching `Calendar.TZnames`) fail here while
//! being perfectly correct in context. Measured on Pike 8.0.1116's own stdlib:
//! 534 of 545 modules compile clean; of the 11 that do not, 7 need GTK bindings
//! that are not built and 3 are this submodule-context case.
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
int strict = 0;
int use_color = -1;   // -1 = auto

//! Colour only when writing to a terminal, and never when NO_COLOR is set
//! (https://no-color.org). --color / --no-color override the guess.
int colorize()
{
  if (use_color >= 0) return use_color;
  if (getenv("NO_COLOR")) return 0;
  mixed t; catch { t = Stdio.stdout->tcgetattr(); };
  return t ? 1 : 0;
}

string C_RED = "\033[31m", C_YEL = "\033[33m", C_GRN = "\033[32m",
       C_BOLD = "\033[1m", C_DIM = "\033[2m", C_OFF = "\033[0m";

string c(string code, string text) { return colorize() ? code + text + C_OFF : text; }

//! Emit a diagnostic in `file:line:col: message` form with an absolute path,
//! which editors and terminals turn into a clickable link.
string diag(string file, int line, string msg, string kind)
{
  string loc = sprintf("%s:%d:1", combine_path(getcwd(), file), line);
  string head = c(C_BOLD, loc) + ":";
  string tag = (kind == "warning") ? c(C_YEL, " warning: ")
             : (kind == "note")    ? c(C_DIM, " ")
             :                       c(C_RED, " error: ");
  return head + tag + msg;
}

//! Re-render a raw compiler line ("path:12: message") as a clickable diagnostic.
string reformat(string line)
{
  string path, msg; int ln;
  if (sscanf(line, "%s:%d: %s", path, ln, msg) == 3) {
    int is_warn = has_prefix(msg, "warning: ");
    if (is_warn) msg = msg[9..];
    return diag(path, ln, msg, is_warn ? "warning" : "error");
  }
  return line;
}
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

//! Where the remembered Roxen path is kept, so it is asked for once.
string config_file()
{
  string home = getenv("HOME");
  if (!home) return 0;
  string xdg = getenv("XDG_CONFIG_HOME") || combine_path(home, ".config");
  return combine_path(xdg, "pike-agent-skills", "roxen-path");
}

//! True once the question has been answered, including a deliberate skip —
//! so "no thanks" is remembered and the prompt does not return every run.
int roxen_asked()
{
  string cf = config_file();
  return cf && Stdio.is_file(cf);
}

string read_saved_roxen()
{
  string cf = config_file();
  if (!cf || !Stdio.is_file(cf)) return 0;
  string v = String.trim_all_whites(Stdio.read_file(cf) || "");
  return sizeof(v) ? v : 0;
}

void save_roxen(string dir)
{
  string cf = config_file();
  if (!cf) return;
  mixed e = catch {
    Stdio.mkdirhier(dirname(cf));
    Stdio.write_file(cf, dir + "\n");
  };
  if (!e && !quiet) write("   remembered in %s\n", cf);
}

//! Is this a real install (rather than a source checkout)?
int looks_like_roxen(string c)
{
  if (!c || !Stdio.is_dir(c)) return 0;
  foreach (({ "start", "server/start" }), string s)
    if (Stdio.is_file(combine_path(c, s))) return 1;
  return 0;
}

//! Locate a Roxen install, in order of authority: explicit flag, environment,
//! remembered answer, then the usual install locations.
string find_roxen()
{
  array(string) candidates = ({});
  if (roxen_dir) candidates += ({ roxen_dir });
  if (getenv("ROXEN_DIR")) candidates += ({ getenv("ROXEN_DIR") });
  string saved = read_saved_roxen();
  if (saved) candidates += ({ saved });
  candidates += ({ "/usr/local/roxen", "/opt/roxen", "/usr/lib/roxen",
                   "/usr/local/roxen/server", "/srv/roxen",
                   combine_path(getenv("HOME") || "/", "roxen"),
                   combine_path(getenv("HOME") || "/", "Roxen") });

  foreach (candidates, string c)
    if (looks_like_roxen(c)) return c;
  return 0;
}

//! Interactive only: ask once, then remember. Never prompts in CI or when the
//! output is piped — there the unverified warning is the right answer.
int interactive()
{
  mixed t; catch { t = Stdio.stdin->tcgetattr(); };
  return t ? 1 : 0;
}

string prompt_for_roxen()
{
  if (!interactive()) return 0;
  write("\n%s This code uses Roxen, and no Roxen install was found.\n",
        c(C_YEL + C_BOLD, "?"));
  write("   Enter the path to your Roxen install (the directory containing\n"
        "   ./start), or press Enter to skip and report it as unverified.\n");
  write("   > ");
  string line = Stdio.stdin->gets();
  if (!line) return 0;
  line = String.trim_all_whites(line);
  if (!sizeof(line)) {
    save_roxen("");                       // remember the skip
    write("   skipped — rerun with --roxen=<dir> to set it later.\n");
    return 0;
  }
  line = (line[0] == '~' && getenv("HOME"))
           ? combine_path(getenv("HOME"), line[2..]) : line;
  if (!looks_like_roxen(line)) {
    write("   %s no ./start under %s — skipping.\n", c(C_RED, "not a Roxen install:"), line);
    return 0;                             // not remembered: it was a mistake
  }
  save_roxen(line);
  return line;
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

//! Compile one file in a child pike, returning the error text ("" on success).
//!
//! A subprocess rather than compile_string() in this process, because some
//! failures are reported by the master directly to stderr (a runtime error
//! while resolving a dependency, e.g. Calendar.pmod/Event.pmod). Those bypass
//! any compile-error handler, so in-process they appear as unattributed
//! backtraces and the file that caused them cannot be identified. A child also
//! stops one bad file from poisoning the module cache for the rest of the run.
string compile_here(string file)
{
  string abs = combine_path(getcwd(), file);
  string snippet = sprintf(
    "object h = class {\n"
    "  string acc = \"\";\n"
    "  void compile_error(string f, int l, string m) { acc += f + \":\" + l + \": \" + m + \"\\n\"; }\n"
    "  void compile_warning(string f, int l, string m) { acc += f + \":\" + l + \": warning: \" + m + \"\\n\"; }\n"
    "}();\n"
    "mixed e = catch { compile_string(Stdio.read_file(%O), %O, h); };\n"
    "write(h->acc);\n"
    "if (e && h->acc == \"\") write(\"__THREW__ \" + (describe_error(e)/\"\\n\")[0] + \"\\n\");\n",
    abs, abs);

  array(string) cmd = ({ "pike" });
  foreach (extra_M, string d) cmd += ({ "-M", d });
  foreach (extra_I, string d) cmd += ({ "-I", d });
  cmd += ({ "-e", snippet });

  mapping res = Process.run(cmd, ([ "cwd": dirname(abs) ]));
  string out = (res->stdout || "");
  string err = (res->stderr || "");

  // Anything the child wrote to stderr is a failure the handler could not
  // capture. Attribute it to this file and keep only the informative head.
  if (String.trim_all_whites(err) != "" || has_prefix(out, "__THREW__")) {
    string first;
    if (has_prefix(out, "__THREW__")) first = String.trim_all_whites(out[9..]);
    else {
      array(string) el = (err / "\n") - ({ "" });
      first = sizeof(el) ? String.trim_all_whites(el[0]) : "compilation failed";
    }
    string acc = sprintf("%s:0: %s\n", file, first);
    int shown = 0;
    foreach ((err / "\n") - ({ "" }), string l) {
      if (has_value(l, "/lib/master.pike")) continue;
      if (String.trim_all_whites(l) == first) continue;
      if (shown++ >= 2) break;
      acc += sprintf("%s:0:   %s\n", file, String.trim_all_whites(l));
    }
    return acc + (has_prefix(out, "__THREW__") ? "" : out);
  }
  return out;
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
    else if (a == "--strict") strict = 1;
    else if (a == "--color") use_color = 1;
    else if (a == "--no-color") use_color = 0;
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
  --strict        treat compiler warnings as errors
  --color / --no-color   force colour on or off (default: auto, honours NO_COLOR)

Diagnostics are printed as absolute `file:line:col: message`, which most
editors and terminals render as a clickable link.
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

  // Ask once, on the first run that actually needs Roxen.
  if (!rdir) {
    int any_needs_roxen = 0;
    foreach (files, string f) {
      string src = Stdio.read_file(f);
      if (src && mentions_roxen(src)) { any_needs_roxen = 1; break; }
    }
    if (any_needs_roxen && !roxen_asked()) rdir = prompt_for_roxen();
  }

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
          write("%s\n", diag(f, (int)mi[1],
                              sprintf("cannot find include file %s", mi[0]), "error"));

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

    // Warnings are not failures. Pike's own SSL.pmod/Session.pike compiles with
    // type warnings; counting those as errors would fail correct code.
    array(string) warn_lines = ({}), err_lines = ({});
    foreach (errs / "\n", string l) {
      if (l == "") continue;
      if (has_value(l, ": warning: ")) warn_lines += ({ l }); else err_lines += ({ l });
    }
    if (strict) { err_lines += warn_lines; warn_lines = ({}); }

    if (!sizeof(err_lines)) {
      ok_files++;
      if (!quiet) {
        write("%s %s%s\n", c(C_GRN, "OK"), f, sizeof(warn_lines)
                ? c(C_DIM, sprintf(" (%d warning%s)", sizeof(warn_lines),
                          sizeof(warn_lines) == 1 ? "" : "s")) : "");
        foreach (warn_lines, string l) write("  %s\n", reformat(l));
      }
      continue;
    }
    errs = err_lines * "\n";

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

    foreach (real_lines, string l) write("%s\n", reformat(l));
    errors += sizeof(real_lines);
    if (sizeof(real_lines)) bad_files++;

    if (sizeof(roxen_undef)) {
      unverified += sizeof(roxen_undef);
      warn_files++;
      write("\n%s %s: %d Roxen reference%s could NOT be verified: %s\n", c(C_YEL + C_BOLD, "!!"),
            f, sizeof(roxen_undef), sizeof(roxen_undef) == 1 ? "" : "s",
            sort(indices(roxen_undef)) * ", ");
      foreach (roxen_lines, string l) write("     %s\n", reformat(l));
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
    write("\n%s %d error%s in %d file%s\n", c(C_RED + C_BOLD, "FAILED:"),
          errors, errors == 1 ? "" : "s", bad_files, bad_files == 1 ? "" : "s");
    return 1;
  }
  if (unverified) {
    write("\n%s your code compiled, but %d Roxen reference%s went unverified.\n",
          c(C_YEL + C_BOLD, "INCOMPLETE:"), unverified, unverified == 1 ? "" : "s");
    return 2;
  }
  if (!quiet) write("\n%s everything compiled\n", c(C_GRN + C_BOLD, "OK:"));
  return 0;
}
