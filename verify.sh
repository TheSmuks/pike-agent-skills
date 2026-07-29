#!/bin/sh
# Re-run every command documented in these skills against the local Pike.
# Exits non-zero if any documented behaviour no longer holds.
#
# Usage: ./verify.sh

set -u

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

check() { # check <label> <expected-substring> <command...>
  label=$1; want=$2; shift 2
  got=$("$@" 2>&1)
  case "$got" in
    *"$want"*) ok "$label" ;;
    *) bad "$label" "expected '$want', got: $(printf '%s' "$got" | head -1)" ;;
  esac
}

HERE_SKILLS=$(cd "$(dirname "$0")/skills" && pwd)
command -v pike >/dev/null 2>&1 || { echo "pike not found in PATH"; exit 1; }
echo "Pike: $(pike --version 2>&1 | head -1)"
echo

# ---------------------------------------------------------------- module layout
echo "pike-module-layout"

mkdir -p "$TMP/mm/NoMarker.pmod" "$TMP/mm/Deep.pmod/Inner.pmod"
echo 'string hi() { return "no-marker-ok"; }' > "$TMP/mm/NoMarker.pmod/Greeter.pike"
echo 'string who() { return "flat-ok"; }'     > "$TMP/mm/Flat.pmod"
echo 'string who() { return "nested-ok"; }'   > "$TMP/mm/Deep.pmod/Inner.pmod/module.pmod"
echo 'string greet() { return "prog-ok"; }'   > "$TMP/mm/Prog.pike"

check ".pmod dir is a module without module.pmod" "no-marker-ok" \
  pike -M "$TMP/mm" -e 'write("%s\n", NoMarker.Greeter()->hi());'
check ".pmod file is a module" "flat-ok" \
  pike -M "$TMP/mm" -e 'write("%s\n", Flat.who());'
check "nested .pmod dirs form a dotted namespace" "nested-ok" \
  pike -M "$TMP/mm" -e 'write("%s\n", Deep.Inner.who());'
check ".pike is an instantiable program" "prog-ok" \
  pike -M "$TMP/mm" -e 'write("%s\n", Prog()->greet());'
check "--show-paths reports a module path" "Module path" \
  pike --show-paths
echo

# ---------------------------------------------------------------------- testing
echo "pike-testing"

cat > "$TMP/testsuite.in" <<'EOF'
test_eq(1+1, 2)
test_equal(({1,2}), ({1,2}))
test_true(arrayp(({1,2})))
test_false(stringp(5))
test_any([[ int x = 3; return x*2; ]], 6)
EOF

# mktestsuite ships inside the Pike installation, but distributions disagree on
# where. Source installs put it at <prefix>/include/pike/; Debian/Ubuntu use
# /usr/include/pike<version>/pike/. Check both rather than assuming one.
MKTS=""
for c in \
  "$(dirname "$(readlink -f "$(command -v pike)")")/../include/pike/mktestsuite" \
  /usr/include/pike*/pike/mktestsuite \
  /usr/local/include/pike*/pike/mktestsuite
do
  [ -f "$c" ] && { MKTS=$c; break; }
done

if [ -n "$MKTS" ] && [ -x "$MKTS" ]; then
  ok "mktestsuite present at <prefix>/include/pike/mktestsuite"
  if "$MKTS" "$TMP/testsuite.in" > "$TMP/testsuite" 2>/dev/null; then
    check "all 5 macro forms expand and run" "Total tests: 5" \
      pike -x test_pike "$TMP/testsuite"
  else
    bad "mktestsuite expansion (is m4 installed?)"
  fi
else
  printf '  skip mktestsuite not found — skipping m4 path\n'
fi

# hand-written testsuite (no m4)
cat > "$TMP/handwritten" <<'EOF'
hw:1: test 1, expected result: EQ
mixed a() { return 1+1; }
mixed b() { return 2; }
....
hw:2: test 2, expected result: TRUE
mixed a() { return stringp("x"); }
....
EOF
check "hand-written testsuite runs without m4" "Total tests: 2" \
  pike -x test_pike "$TMP/handwritten"

# the silent-pass trap
check "running the unexpanded .in reports zero tests" "Total tests: 0" \
  pike -x test_pike "$TMP/testsuite.in"

# failing suite exits non-zero
cat > "$TMP/failing" <<'EOF'
hw:1: test 1, expected result: EQ
mixed a() { return 1+1; }
mixed b() { return 3; }
....
EOF
if pike -x test_pike "$TMP/failing" >/dev/null 2>&1; then
  bad "test_pike exits non-zero on failure" "exited 0"
else
  ok "test_pike exits non-zero on failure"
fi

# report_result does NOT set exit code
cat > "$TMP/selftest.pike" <<'EOF'
int main() {
  Tools.Testsuite.report_result(0, 1);
  return 0;
}
EOF
if pike "$TMP/selftest.pike" >/dev/null 2>&1; then
  ok "report_result() alone leaves exit code 0 (documented trap)"
else
  bad "report_result() exit-code behaviour changed"
fi
echo

# ------------------------------------------------- documented name resolution
# The skill now teaches one-liners instead of shipping a resolver. Each command
# it documents is checked here against the real Pike, because a documented
# command that does not run is the failure mode that started all this.
echo "name resolution"

mkdir -p "$TMP/res/A.pmod"
echo 'int x(){ return 42; }'                  > "$TMP/res/A.pmod/B.pike"
printf 'import A;\nint f(){ return B()->x(); }\n' > "$TMP/res/User.pike"

FILE_DEF=$(pike -e 'write("%O\n", Program.defined(Stdio.File));' 2>&1)
BUF_DEF=$(pike -e 'write("%O\n", Program.defined(Stdio.Buffer));' 2>&1)
case "$FILE_DEF" in *"module.pmod:"*)
  ok "Program.defined() gives file:line for a class in a module" ;; *)
  bad "Program.defined() gives file:line for a class in a module" "$FILE_DEF" ;; esac
if [ "$FILE_DEF" != "$BUF_DEF" ]; then
  ok "two classes in one module resolve differently"
else
  bad "two classes in one module resolve differently" "both: $FILE_DEF"
fi

BARE=$(cd "$TMP/res" && pike -M . -e 'write("%O\n", undefinedp(master()->resolv("B")));' 2>&1)
case "$BARE" in *1*)
  ok "a bare imported name does NOT resolve (the documented trap)" ;; *)
  bad "a bare imported name does NOT resolve (the documented trap)" "$BARE" ;; esac

QUAL=$(cd "$TMP/res" && pike -M . -e 'write("%O\n", Program.defined(master()->resolv("A.B")));' 2>&1)
case "$QUAL" in *"A.pmod/B.pike"*)
  ok "qualifying with the import scope resolves it" ;; *)
  bad "qualifying with the import scope resolves it" "$QUAL" ;; esac

DIRMOD=$(cd "$TMP/res" && pike -M . -e 'write("%O\n", Program.defined(object_program(master()->resolv("A"))));' 2>&1)
case "$DIRMOD" in *master.pike*)
  ok "a directory module reports master.pike (documented as a lie)" ;; *)
  bad "a directory module reports master.pike (documented as a lie)" "$DIRMOD" ;; esac

IDX=$(cd "$TMP/res" && pike -M . -e 'write("%O\n", indices(master()->resolv("A")));' 2>&1)
case "$IDX" in *'"B"'*)
  ok "indices() lists what an imported scope provides" ;; *)
  bad "indices() lists what an imported scope provides" "$IDX" ;; esac

PATHS=$(pike --show-paths 2>&1)
case "$PATHS" in *"Module path"*)
  ok "pike --show-paths reports the search roots" ;; *)
  bad "pike --show-paths reports the search roots" ;; esac
echo
# --------------------------------------------------- documented compile checks
# No tool ships any more, so what must hold is that the commands the skill
# documents actually behave as documented.
echo "compile checking"

mkdir -p "$TMP/cc/Lib.pmod"
echo 'int a(){ return 1; }'                 > "$TMP/cc/Good.pike"
echo 'int m(){ return 2; }'                 > "$TMP/cc/Lib.pmod/Mixin.pike"
echo 'int b(){ return no_such_fn_xyz(); }'  > "$TMP/cc/Broken.pike"

( cd "$TMP/cc" && pike -e 'compile_file("Good.pike");' ) >/dev/null 2>&1
[ $? -eq 0 ] && ok "compile_file() exits 0 on clean code" \
             || bad "compile_file() exits 0 on clean code"

( cd "$TMP/cc" && pike -e 'compile_file("Broken.pike");' ) >/dev/null 2>&1
[ $? -ne 0 ] && ok "compile_file() exits non-zero on broken code" \
             || bad "compile_file() exits non-zero on broken code"

CCERR=$( cd "$TMP/cc" && pike -e 'compile_file("Broken.pike");' 2>&1 )
case "$CCERR" in *"Broken.pike:1:"*)
  ok "compile_file() reports file:line" ;; *)
  bad "compile_file() reports file:line" "$CCERR" ;; esac

# The documented trap: -c is not a Pike flag, so it checks nothing.
CFLAG=$( cd "$TMP/cc" && pike -c Good.pike 2>&1 )
case "$CFLAG" in *"Unknown option"*)
  ok "pike -c is not a compile check (documented trap)" ;; *)
  bad "pike -c is not a compile check (documented trap)" "$CFLAG" ;; esac

# The other trap: passing a file to pike runs it.
RUNIT=$( cd "$TMP/cc" && pike Good.pike 2>&1 )
case "$RUNIT" in *"no main"*)
  ok "pike <file> runs rather than checks it (documented trap)" ;; *)
  bad "pike <file> runs rather than checks it (documented trap)" "$RUNIT" ;; esac

# A .pmod DIRECTORY must be excluded, or a tree sweep invents failures.
DIRERR=$( cd "$TMP/cc" && pike -e 'compile_file("Lib.pmod");' 2>&1 )
case "$DIRERR" in *"Bad argument 1 to cpp"*)
  ok "a .pmod directory breaks compile_file (why -type f matters)" ;; *)
  bad "a .pmod directory breaks compile_file (why -type f matters)" "$DIRERR" ;; esac

# A prune that matches "." discards the whole tree, so the sweep passes by
# checking nothing — the same silent green as an unexpanded testsuite.in.
PRUNED=$( cd "$TMP/cc" && find . -name '.*' -prune -o -type f -name '*.pike' -print | wc -l )
GUARDED=$( cd "$TMP/cc" && find . -mindepth 1 -name '.*' -prune -o -type f -name '*.pike' -print | wc -l )
if [ "$PRUNED" -eq 0 ] && [ "$GUARDED" -gt 0 ]; then
  ok "-name '.*' -prune matches '.' and finds nothing (needs -mindepth 1)"
else
  bad "-name '.*' -prune matches '.' and finds nothing (needs -mindepth 1)" "$PRUNED / $GUARDED"
fi

NFILES=$( cd "$TMP/cc" && find . -type f \( -name '*.pike' -o -name '*.pmod' \) | wc -l )
NALL=$( cd "$TMP/cc" && find . \( -name '*.pike' -o -name '*.pmod' \) | wc -l )
if [ "$NFILES" -lt "$NALL" ]; then
  ok "-type f excludes .pmod directories from a tree sweep"
else
  bad "-type f excludes .pmod directories from a tree sweep" "$NFILES vs $NALL"
fi
echo
# ------------------------------------------------------------ runtime discovery
echo "pike-runtime-discovery"

check "resolv() returns UNDEFINED for a missing module" "1" \
  pike -e 'write("%O\n", undefinedp(master()->resolv("No.Such.Module")));'
check "resolv() finds an existing module" "0" \
  pike -e 'write("%O\n", undefinedp(master()->resolv("Standards.JSON")));'
check "_typeof() reports a function signature" "function(" \
  pike -e 'write("%O\n", _typeof(Stdio.File()->read));'
check "Program.defined() returns file:line" "Stdio.pmod" \
  pike -e 'write("%O\n", Program.defined(Stdio.File));'
check "indices() lists module symbols" "File" \
  pike -e 'write("%O\n", filter(indices(Stdio), lambda(string s){ return has_prefix(s,"F"); }));'
check "standalone tool descriptions are readable" "testsuite" \
  pike -e 'write("%s\n", Tools.Standalone["test_pike"]->description);'
check "pike_module_path is introspectable" "modules" \
  pike -e 'write("%O\n", master()->pike_module_path);'

cat > "$TMP/bt.pike" <<'EOF'
int main() {
  mixed err = catch { ((array)0)[5]; };
  if (err) write("%s", describe_backtrace(err));
  return 0;
}
EOF
check "describe_backtrace() renders a trace" "Cannot cast" pike "$TMP/bt.pike"
echo

# --------------------------------------------------------------- build and docs
echo "pike-build-and-docs"

mkdir -p "$TMP/ad/build"
cat > "$TMP/ad/Doc.pike" <<'EOF'
//! Adds two integers.
//! @param a
//!   First addend.
//! @returns
//!   The sum.
int add(int a, int b) { return a + b; }
EOF

( cd "$TMP/ad" && pike -x extract_autodoc --builddir=build Doc.pike >/dev/null 2>&1 )
if [ -f "$TMP/ad/build/Doc.pike.xml" ]; then
  ok "extract_autodoc --builddir produces XML"
  check "extracted XML carries parameter docs" "First addend" cat "$TMP/ad/build/Doc.pike.xml"
  check "extracted XML carries source position" "source-position" cat "$TMP/ad/build/Doc.pike.xml"
else
  bad "extract_autodoc --builddir produced no XML"
fi

check "join_autodoc documents its usage" "join_autodoc" pike -x join_autodoc --help
# These probe the documented interface rather than a file path, so they stay valid
# wherever a distribution chooses to install the tools.
#
# Note: Debian/Ubuntu split the C-module tooling out of the base `pike8.0` package.
# If precompile/module are missing there, install `pike8.0-dev`.
check "precompile converts .cmod to .c" "cmod" pike -x precompile --help
check "module installer is available" "Pike module installer" pike -x module --help
check "monger (stock package manager) is available" "Monger" pike -x monger --help
echo

# ------------------------------------------------------------------- install
# The tools bug survived three releases because every check ran from a git
# clone, where tools/ trivially exists. Test from an *installed* tree instead —
# that is the only state a user ever sees.
echo "install"
INSTDIR="$TMP/inst"
INSTALLER=$(cd "$(dirname "$0")" && pwd)/install.sh
mkdir -p "$INSTDIR"
"$INSTALLER" "$INSTDIR/dest" >/dev/null 2>&1

# --help must not be treated as a target (it once was, and printed "Unknown target")
if "$INSTALLER" --help >/dev/null 2>&1; then ok "--help exits 0"; else bad "--help exits 0"; fi
"$INSTALLER" --nope >/dev/null 2>&1 && bad "unknown option exits non-zero" \
                                    || ok "unknown option exits non-zero"

# --dry-run must change nothing
"$INSTALLER" --dry-run "$INSTDIR/dry" >/dev/null 2>&1
[ -d "$INSTDIR/dry" ] && bad "--dry-run writes nothing" "it created the directory" \
                      || ok "--dry-run writes nothing"

# a provenance stamp, so a later reader can tell where an install came from
[ -f "$INSTDIR/dest/.pike-agent-skills" ] \
  && ok "install records provenance" || bad "install records provenance"

# --uninstall removes what it installed
"$INSTALLER" --uninstall "$INSTDIR/dest" >/dev/null 2>&1
[ -d "$INSTDIR/dest/pike-testing" ] && bad "--uninstall removes skills" \
                                    || ok "--uninstall removes skills"
# and they must actually run from there, not just exist
echo

# INSTALL.md is agent-facing; keep it honest about the URL trap.
HERE_ROOT=$(cd "$(dirname "$0")" && pwd)
if [ -f "$HERE_ROOT/INSTALL.md" ] && grep -q "only \`SKILL.md\`" "$HERE_ROOT/INSTALL.md"; then
  ok "INSTALL.md warns that URL installs drop bundled tools"
else
  bad "INSTALL.md warns about the URL trap"
fi
echo

# ------------------------------------------------------------------ repo health
echo "repo consistency"

HERE=$(cd "$(dirname "$0")" && pwd)
if [ -f "$HERE/AGENTS.md" ] && [ -f "$HERE/.github/instructions/pike.instructions.md" ]; then
  if sed '1,4d' "$HERE/.github/instructions/pike.instructions.md" | \
       diff -q - "$HERE/AGENTS.md" >/dev/null 2>&1; then
    ok "AGENTS.md and the Copilot instructions body are in sync"
  else
    bad "AGENTS.md and .github/instructions/pike.instructions.md have drifted"
  fi
fi

if grep -rqE '(^|[^-a-z])tools/pike-' "$HERE_SKILLS"/*/SKILL.md 2>/dev/null; then
  bad "no stale tools/ paths in skills" "a SKILL.md still points at tools/"
else
  ok "no stale tools/ paths in skills"
fi

for s in pike-module-layout pike-testing pike-runtime-discovery pike-build-and-docs; do
  if [ -f "$HERE/skills/$s/SKILL.md" ]; then
    if head -5 "$HERE/skills/$s/SKILL.md" | grep -q "name: $s"; then
      ok "skills/$s frontmatter name matches its directory"
    else
      bad "skills/$s frontmatter name does not match its directory"
    fi
  else
    bad "skills/$s/SKILL.md missing"
  fi
done
echo

echo "-----------------------------------------"
printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
