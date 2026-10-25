#!/bin/sh
# Fails if any blessed output under the reference carries trailing whitespace.  Editors and git strip it, so a blessed
# file that depends on it is corrupted the first time anyone touches it; a probe that would print it is rewritten to
# delimit its output instead.  `perl-conformance bless` refuses such output at blessing time; this covers the suites, whose
# expected files are written by hand from the supported versions.
cd "$(dirname "$0")/.." || exit 2
bad=$(grep -rln '[[:space:]]$' probes/corpus/expected suites/*/expected 2>/dev/null)
if [ -n "$bad" ]; then echo "trailing whitespace in blessed output:"; echo "$bad"; exit 1; fi
echo "blessed outputs clean"
