#!/bin/sh
# A deliberately wrong "implementation" for exercising `perl-conformance check`: stock perl 5.44.0 with the hash seed
# forced to 1, so hash iteration order differs from the pinned seed-0 reference run.
PERL_HASH_SEED=1 exec /opt/perlbrew/perls/perl-5.44.0/bin/perl "$@"
