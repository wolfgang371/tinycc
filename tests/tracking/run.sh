#!/bin/sh
# Smoke test of the -t symbol tracking (the mincut instrumentation).
#
#   tests/tracking/run.sh [path/to/tcc] [--standalone]    (default: ./tcc, run from the source root)
#
# Runs anywhere `make test` runs: Linux, and MSYS2 on Windows (where ./tcc finds tcc.exe). It checks
#   1. a successful compile writes the track file, one JSON object per line,
#   2. every symbol kind mincut relies on is reported with the file it is used in (sample.c) or declared in
#      (sample.h): function call, extern variable, macro, typedef, struct/union with its kind, field access,
#   3. a failed compile leaves no track file behind (not even a stale one from an earlier run).
set -eu

TCC=${1:-./tcc}
HERE=$(dirname "$0")
TOP=$HERE/../..
OUT=${TMPDIR:-/tmp}/tcc-tracking-$$
mkdir -p "$OUT"
trap 'rm -rf "$OUT"' EXIT

# An in-tree build is pointed at its headers and runtime. The standalone tcc.exe (win32/build-standalone.sh)
# carries its own and is run without such flags: pass --standalone as the second argument.
if [ "${2:-}" = --standalone ]; then
  FLAGS=""
else
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) FLAGS="-B$TOP/win32 -I$TOP/include -I$TOP/win32/include" ;;
    *)                    FLAGS="-B$TOP -I$TOP/include" ;;
  esac
fi

fail() { echo "FAIL: $*"; exit 1; }

# --- 1. successful compile writes the track file ---------------------------------------------------------------
# shellcheck disable=SC2086
"$TCC" $FLAGS -c "$HERE/sample.c" -o "$OUT/sample.o" -t "$OUT/sample.track" || fail "tcc did not compile sample.c"
[ -s "$OUT/sample.track" ] || fail "no track file written"

# every line is a JSON object (checked strictly when a Python is available)
PY=$(command -v python3 || command -v python || true)
if [ -n "$PY" ]; then
  "$PY" -c '
import json, sys
for n, line in enumerate(open(sys.argv[1], encoding="utf-8", errors="replace"), 1):
    line = line.strip()
    if line:
        obj = json.loads(line)
        assert isinstance(obj, dict) and "event" in obj, "line %d: not an event object" % n
' "$OUT/sample.track" || fail "track file is not one JSON event per line"
else
  if grep -v '^{"event":".*}$' "$OUT/sample.track" | grep -q .; then fail "track file has a non-event line"; fi
fi

# --- 2. the symbols mincut needs --------------------------------------------------------------------------------
expect() { # <what> <extended regex>
  grep -Eq "$2" "$OUT/sample.track" || fail "missing $1  (pattern: $2)"
  echo "ok   $1"
}
USE='"file":"[^"]*sample\.c"'
DECL='"file":"[^"]*sample\.h"'
expect "function call (FUNCTION_USAGE helper)"       "\"event\":\"FUNCTION_USAGE\",\"name\":\"helper\",$USE"
expect "function declaration from header"            "\"event\":\"FUNCTION_DECL\",\"name\":\"helper\",.*$DECL"
expect "extern variable use (EXTERN global_counter)" "\"event\":\"EXTERN\",\"name\":\"global_counter\",.*$USE"
expect "extern variable use (VAR_USE global_counter)" "\"event\":\"VAR_USE\",\"name\":\"global_counter\",.*$USE"
expect "macro expansion (MACRO_USAGE SCALE)"         "\"event\":\"MACRO_USAGE\",\"name\":\"SCALE\",.*$USE"
expect "macro definition from header"                "\"event\":\"MACRO_DECL\",\"name\":\"SCALE\",.*$DECL"
expect "typedef use (TYPEDEF_USAGE count_t)"         "\"event\":\"TYPEDEF_USAGE\",\"name\":\"count_t\",$USE"
expect "typedef use in sizeof (TYPEDEF_USAGE value_t)" "\"event\":\"TYPEDEF_USAGE\",\"name\":\"value_t\",$USE"
expect "struct declaration with kind"                "\"event\":\"STRUCT_DECL\",\"kind\":\"struct\",\"name\":\"point\",$DECL"
expect "union declaration with kind"                 "\"event\":\"STRUCT_DECL\",\"kind\":\"union\",\"name\":\"value\",$DECL"
expect "field access via -> (FIELD point_t.x)"       "\"event\":\"FIELD\",\"struct\":\"point_t\",\"operator\":\"->\",\"field\":\"x\",.*$USE"
expect "field access via . (FIELD value_t.i)"        "\"event\":\"FIELD\",\"struct\":\"value_t\",\"operator\":\"\\.\",\"field\":\"i\",.*$USE"
expect "include of the header (INCLUDE sample.h)"    "\"event\":\"INCLUDE\",.*\"included\":\"sample\\.h\""

# --- 3. a failed compile leaves no track file -------------------------------------------------------------------
printf 'int broken( { return 0; }\n' > "$OUT/broken.c"
echo stale > "$OUT/broken.track"
# shellcheck disable=SC2086
if "$TCC" $FLAGS -c "$OUT/broken.c" -o "$OUT/broken.o" -t "$OUT/broken.track" 2>/dev/null; then
  fail "broken.c compiled"
fi
[ ! -e "$OUT/broken.track" ] || fail "a failed compile left a track file"
echo "ok   failed compile leaves no track file"

echo "tracking smoke test passed"
