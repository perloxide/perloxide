#!/bin/sh
# usage: sizes.sh /path/to/perl
# Compiles sizes.c against that perl's CORE headers and library and prints the structure sizes.
P=${1:?usage: sizes.sh /path/to/perl}
A=$($P -MConfig -e 'print $Config{archlibexp}') || exit 1
CC=$($P -MConfig -e 'print $Config{cc}')
FLAGS=$($P -MConfig -e 'print $Config{ccflags}')
LIBS=$($P -MConfig -e 'print $Config{perllibs}')
OUT=$(mktemp) || exit 1
trap 'rm -f "$OUT"' EXIT
$CC -I"$A/CORE" $FLAGS -o "$OUT" "$(dirname "$0")/sizes.c" -L"$A/CORE" -lperl $LIBS 2>/dev/null || exit 1
echo "$($P -e 'print $^V') $($P -MConfig -e 'print $Config{archname}')"
LD_LIBRARY_PATH="$A/CORE" "$OUT"
