#!/usr/bin/env bash
# tiny-compiler/mayhem/build.sh — build zakirullin/tiny-compiler as the FILE-INPUT fuzz target, plus a
# clean normal-flags build of the same binary for the golden-output test (mayhem/test.sh).
#
# tiny-compiler is a tiny educational compiler for an LL(2) toy language: a single translation unit
# (src/main.c #includes all the src/*.h: lexer, parser, ASM-like codegen, VM, symbol table). `make`
# produces `compiler`, invoked as `./compiler <source-file>` — it lexes, parses, generates bytecode,
# disassembles it, and RUNS it on a VM. The Mayhem target is FILE-INPUT (CLI): `compiler @@` feeds the
# fuzz bytes as a source file, exercising the whole pipeline (scanner -> parser -> codegen -> VM). No
# external deps, no libFuzzer harness needed — the natural fuzz surface is the compiler on a source file
# (this preserves the OLD integration's target name `compiler`, which ran `/tiny-compiler/compiler /test.txt`).
#
# Two builds of the single TU (src/main.c), done sequentially:
#   (1) NORMAL-flags build  -> /mayhem/compiler-test  (honest oracle for test.sh; no sanitizer noise)
#   (2) SANITIZED build      -> /mayhem/compiler        (the fuzz target; built WITH $SANITIZER_FLAGS)
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENV, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an explicit empty value
# (--build-arg SANITIZER_FLAGS=) is honored → no-sanitizer build (the compiler's natural crash).
# tiny-compiler has no external libs to link, so the empty-sanitizer build links cleanly with no extra flags.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${CC:=clang}"
: "${MAYHEM_JOBS:=$(nproc)}"
export SANITIZER_FLAGS CC MAYHEM_JOBS

cd "$SRC"

# Upstream's Makefile hardcodes CC=gcc with `-Wall`. We compile the single TU directly with $CC so the
# project itself is built with our flags (the Makefile target is just `$(CC) -Wall -o compiler src/main.c`).
SRCS="src/main.c"

# ---------------------------------------------------------------------------
# (1) TEST build — normal flags, NO sanitizer. Produces the golden-output oracle binary that
#     mayhem/test.sh runs on program.src and diffs against the known answer ("hypsquare = 25").
# ---------------------------------------------------------------------------
$CC -Wall -O2 -g -o /mayhem/compiler-test $SRCS

# ---------------------------------------------------------------------------
# (2) FUZZ build — the PROJECT compiled WITH $SANITIZER_FLAGS so the fuzzed code is instrumented
#     (ASan+UBSan, halting, by default). /mayhem/compiler is the file-input Mayhem target.
#
#     LeakSanitizer OFF for this target: tiny-compiler is an educational compiler that, by design, never
#     frees — it allocates AST nodes / symbols and relies on process exit to reclaim memory. LSan (which
#     runs at exit, as part of ASan) therefore reports "leaks" on essentially EVERY non-trivial input,
#     which would flood the fuzzer with spurious, benign crashes and stop it exploring real defects. We
#     disable ONLY leak detection (keeping ASan's heap/stack/global overflow + use-after-free checks and
#     all of UBSan, still halting). Baked into the binary via a weak __asan_default_options so it holds no
#     matter how `compiler` is launched (fuzzer, smoke test) — not only when ASAN_OPTIONS is set. We also
#     set it in mayhem/Mayhemfile_compiler for documentation. (Cohort precedent: cproc does the same.)
# ---------------------------------------------------------------------------
if printf '%s' "$SANITIZER_FLAGS" | grep -q address; then
  cat > /tmp/asan_opts.c <<'EOF'
/* Disable LeakSanitizer for tiny-compiler's `compiler`: it never frees by design (reclaim-at-exit), so
   LSan would report benign leaks on nearly every input. Keeps the rest of ASan + UBSan active and halting. */
const char *__asan_default_options(void) { return "detect_leaks=0"; }
EOF
  $CC $SANITIZER_FLAGS -Wall -c /tmp/asan_opts.c -o /tmp/asan_opts.o
  $CC $SANITIZER_FLAGS -Wall -o /mayhem/compiler $SRCS /tmp/asan_opts.o
else
  # No-sanitizer build (e.g. --build-arg SANITIZER_FLAGS=): nothing to suppress, no override object.
  $CC $SANITIZER_FLAGS -Wall -o /mayhem/compiler $SRCS
fi

echo "build.sh: built /mayhem/compiler (sanitized fuzz target) and /mayhem/compiler-test (golden oracle)"
ls -l /mayhem/compiler /mayhem/compiler-test
