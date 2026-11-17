#!/bin/sh
# Package an already built Linux tcc (./configure && make in the source root) as a RELOCATABLE directory:
#
#   tinycc-track/bin/tcc
#   tinycc-track/lib/tcc/{libtcc1.a, *.o, include/}     the -B directory
#   tinycc-track/{include,lib,share}/...                 libtcc, docs (as `make install` lays them out)
#
#   .github/package-linux.sh [output.tar.gz]   (default: tinycc-track-linux-x86_64.tar.gz)
#
# tcc has its library directory compiled in (CONFIG_TCCDIR, /usr/local/lib/tcc). Used from anywhere else it needs
#   tinycc-track/bin/tcc -B tinycc-track/lib/tcc ...
# The package is checked that way here: a program is compiled with -t, linked and run from a copy of the package
# outside the source tree.
set -eu

OUT=${1:-tinycc-track-linux-x86_64.tar.gz}
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

make install DESTDIR="$STAGE/root" >/dev/null
mv "$STAGE/root/usr/local" "$STAGE/tinycc-track"

T=$STAGE/tinycc-track
printf '#include <stdio.h>\n#include <math.h>\nint main(void){ printf("%%g\\n", sqrt(2.25)); return 0; }\n' > "$STAGE/t.c"
"$T/bin/tcc" -B"$T/lib/tcc" -t "$STAGE/t.track" "$STAGE/t.c" -o "$STAGE/t" -lm
[ "$("$STAGE/t")" = 1.5 ] || { echo "package check: the program did not print 1.5"; exit 1; }
[ -s "$STAGE/t.track" ] || { echo "package check: no track file"; exit 1; }

tar -czf "$OUT" -C "$STAGE" tinycc-track
echo "packaged $OUT ($(du -h "$OUT" | cut -f1))"
