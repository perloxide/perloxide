# oracle-requires: locale de_DE.UTF-8
# A numeric cache made under one LC_NUMERIC radix, read after a runtime setlocale to the other radix.
use strict; use warnings; no warnings 'numeric';
use POSIX qw(setlocale LC_NUMERIC);
sub g { sprintf "%.17g", $_[0] }                    # formatted outside 'use locale', so the output radix is '.'
setlocale(LC_NUMERIC, "de_DE.UTF-8") or die "no de_DE locale\n";
my $s = "" . "1,5";
{ use locale; my $n = $s + 0; }                     # cached under the comma radix
setlocale(LC_NUMERIC, "C");
my ($cached_in, $fresh_in); { use locale; $cached_in = $s + 0; $fresh_in = ("" . $s) + 0; }
my $cached_out = $s + 0;
print "de cache, then setlocale C: cached under use locale=", g($cached_in), " cached outside=", g($cached_out), " fresh under use locale=", g($fresh_in), "\n";
setlocale(LC_NUMERIC, "C");
my $t = "" . "1,5";
{ use locale; my $n = $t + 0; }                     # cached under the dot radix
setlocale(LC_NUMERIC, "de_DE.UTF-8");
my ($cached_in2, $fresh_in2); { use locale; $cached_in2 = $t + 0; $fresh_in2 = ("" . $t) + 0; }
print "C cache, then setlocale de: cached under use locale=", g($cached_in2), " fresh under use locale=", g($fresh_in2), "\n";
