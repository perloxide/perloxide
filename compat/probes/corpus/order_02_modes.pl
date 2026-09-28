# oracle-variant: noise0 NOISE=0
# oracle-variant: noise3 NOISE=3
# oracle-variant: noise50 NOISE=50
# Does iteration order depend on unrelated prior hash activity? Run with different PERL_HASH_SEED/PERTURB settings.
use strict; use warnings;
if ($ENV{NOISE}) { my %junk; $junk{$_} = 1 for 1..$ENV{NOISE}; }
my %h; $h{$_} = 1 for 'a'..'p';
print join(' ', keys %h), "\n";
