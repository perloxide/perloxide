Perls built with usemymalloc='n', d_malloc_good_size='undef', d_malloc_size='undef' (the LEN rules hold only there).
Core modules only: B, Devel::Peek, Scalar::Util, Data::Dumper, JSON::PP, Storable, builtin, POSIX.  The locale recipe
uses the harness's compiled comma-radix locale (`../../locales`, `../../profile.md`).

Run, once per Perl, with the perlbrew build name as the tag:

    PERL_CONFORMANCE_PERL=/path/to/perl TAG=5.44.0 perl generators/vf_gen.pl

which merges the run into reports/transitions.tsv, matrix.tsv and copy.tsv and rewrites reports/coverage.txt.  Replay
the model against a recorded version with `perl-conformance replay ValueFlags/transitions` (or `/matrix`, `/copy`), or
REPLAY=1 TAG=<version> TABLE=<table> perl generators/vf_gen.pl.  The handler matrix reads `../../perl-bugs.md`.

Explore beyond the recipes, storing nothing, with:

    PERL_CONFORMANCE_PERL=/path/to/perl TAG=5.44.0 [DEPTH=2] [WALK=500 WALK_DEPTH=10] perl generators/vf_explore.pl

Its candidate paths ($WORK/pinned.<version>.tsv) are added to generators/pinned.tsv by hand.
