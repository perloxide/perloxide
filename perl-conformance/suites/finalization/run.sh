#!/bin/sh
# usage: ./run.sh /path/to/interpreter [VERSION]
# Compares the interpreter against the outputs blessed on VERSION (default: the newest line of ../../supported-versions).
# Each expected file ends with "exit=N".  Cases named *_EXCLUDED read freed memory in perl and are not run.
P=${1:-perl}; V=${2:-$(grep -v '^#' ../../supported-versions | grep . | tail -1)}; E=expected/$V; fail=0
[ -d "$E" ] || { echo "no blessing for version $V in $(pwd)" >&2; exit 2; }
for c in cases/*.pl; do n=$(basename $c .pl); case $n in *_EXCLUDED) continue;; esac
  if ( $P $c 2>&1; echo "exit=$?" ) | diff -q - $E/$n.out >/dev/null; then echo "ok   $n"; else echo "FAIL $n"; fail=1; fi; done; exit $fail
