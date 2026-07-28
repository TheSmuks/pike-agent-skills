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

MKTS="$(dirname "$(readlink -f "$(command -v pike)")")/../include/pike/mktestsuite"
if [ -x "$MKTS" ]; then
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
check "precompile converts .cmod to .c" "Converts" \
  sh -c "grep -h 'constant description' \"\$(pike -e 'write(\"%s\n\", master()->pike_module_path[0]);')\"/Tools.pmod/Standalone.pmod/precompile.pike"
check "module installer is available" "Pike module installer" \
  sh -c "grep -h 'constant description' \"\$(pike -e 'write(\"%s\n\", master()->pike_module_path[0]);')\"/Tools.pmod/Standalone.pmod/module.pike"
check "monger (stock package manager) is available" "Monger" pike -x monger --help
echo

echo "-----------------------------------------"
printf 'passed: %d   failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
