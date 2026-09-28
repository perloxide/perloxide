#!/bin/sh
# usage: ./run.sh /path/to/interpreter [expected-dir]   (default expected: 5.44.0)
# Each expected file ends with "exit=N". Cases named *_EXCLUDED read freed memory in perl and are not run.
P=${1:-perl}; E=${2:-expected/5.44.0}; fail=0
for c in cases/*.pl; do n=$(basename $c .pl); case $n in *_EXCLUDED) continue;; esac
  if ( $P $c 2>&1; echo "exit=$?" ) | diff -q - $E/$n.out >/dev/null; then echo "ok   $n"; else echo "FAIL $n"; fail=1; fi; done; exit $fail
