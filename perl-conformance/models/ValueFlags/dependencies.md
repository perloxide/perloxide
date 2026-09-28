Two Perls built with usemymalloc='n', d_malloc_good_size='undef', d_malloc_size='undef' (checked at startup; the LEN
rules hold only there).  Core modules only: B, Devel::Peek, Scalar::Util, Data::Dumper, JSON::PP, Storable, builtin,
Time::HiRes.  The locale lane needs a comma-radix locale; the harness will compile one (see profile.md) -- until that
lands, de_DE.UTF-8.  Build a tagged Perl with build-perl.sh (perlbrew from the GitHub tag; see README).

Run: VF_ROOT=<this dir> PERLS="<perl1> <perl2>" perl vf_suite.pl; a single lane in parallel across starts: perl
vf_suite.pl lane full3 DEPTH=3 PROJ=full JOBS=8 (the driver runs one child per start and merges with merge_starts.pl).
