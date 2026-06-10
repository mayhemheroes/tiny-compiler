#!/usr/bin/env bash
# tiny-compiler/mayhem/test.sh — golden / known-answer oracle for zakirullin/tiny-compiler.
#
# tiny-compiler ships NO test suite (it's an educational single-file compiler). It DOES document a
# known answer: the bundled program.src ("Pythagorean theorem") must produce "hypsquare = 25" (README).
# We turn that documented behaviour — plus a couple more deterministic toy programs — into a known-answer
# functional oracle: build.sh produced /mayhem/compiler-test (NORMAL flags, no sanitizer); this script
# RUNS it on each program and DIFFS the VM's "Execution result:" output against the expected values.
#
# This is an honest PATCH-grade oracle: it asserts the COMPUTED OUTPUT (the VM result), not just exit 0.
# A no-op / exit(0) "patch" produces no "hypsquare = 25" line and FAILS the diff, so it can't be
# reward-hacked. It never compiles — build.sh already built the binary with the project's normal flags.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN="$SRC/compiler-test"
[ -x "$BIN" ] || { echo "missing $BIN — run mayhem/build.sh first" >&2; emit_ctrf "tiny-compiler-golden" 0 1; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A known-answer case: <name> <program-source> <expected "Execution result:" body (exact lines)>.
# We diff only the lines AFTER "Execution result:" so the test is robust to the ASM dump above it.
passed=0; failed=0

run_case() {
  local name="$1" src="$2" want="$3"
  local prog="$WORK/$name.src"
  printf '%s' "$src" > "$prog"
  # Capture full output, then slice out the VM execution-result section.
  local out got
  out="$("$BIN" "$prog" 2>&1)" || true
  got="$(printf '%s\n' "$out" | sed -n '/^Execution result:$/,$p' | tail -n +2)"
  if [ "$got" = "$want" ]; then
    echo "PASS $name"; passed=$((passed+1))
  else
    echo "FAIL $name"
    echo "  expected:"; printf '%s\n' "$want"   | sed 's/^/    /'
    echo "  got:";      printf '%s\n' "$got"     | sed 's/^/    /'
    failed=$((failed+1))
  fi
}

# 1) The README's documented example (program.src): Pythagorean theorem -> hypsquare = 25.
run_case pythagoras \
"cath1 = 3;
cath2 = 4;
hypsquare = cath1 * cath1 + cath2 * cath2;" \
"cath1 = 3
cath2 = 4
hypsquare = 25"

# 2) Multiplication of two variables.
run_case multiply \
"a = 7;
b = 2;
c = a * b;" \
"a = 7
b = 2
c = 14"

# 3) Repeated addition of a variable.
run_case add \
"x = 10;
y = x + x + x;" \
"x = 10
y = 30"

emit_ctrf "tiny-compiler-golden" "$passed" "$failed"
