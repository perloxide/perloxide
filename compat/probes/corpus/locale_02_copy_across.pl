# oracle-requires: locale radix_comma.UTF-8
# Copies carry the cached value, not the radix; an uncached copy parses under the radix in effect when it is read.
use strict; use warnings; no warnings 'numeric';
use POSIX qw(setlocale LC_NUMERIC);
sub g { sprintf "%.17g", $_[0] }
setlocale(LC_NUMERIC, "radix_comma.UTF-8") or die "no radix_comma locale\n";
my $s = "" . "1,5"; { use locale; my $n = $s + 0; } my $copy = $s;
setlocale(LC_NUMERIC, "C");
my $r1; { use locale; $r1 = $copy + 0; }
print "copy of a de-cached scalar, read under C use locale: ", g($r1), "\n";
my $u = "" . "1,5"; my $ucopy;
{ setlocale(LC_NUMERIC, "radix_comma.UTF-8"); $ucopy = $u; }        # copied while de is set, never numified
setlocale(LC_NUMERIC, "C");
my $r2; { use locale; $r2 = $ucopy + 0; }
print "uncached copy made under de, first numified under C use locale: ", g($r2), "\n";
setlocale(LC_NUMERIC, "C");
my $v = "" . "1,5"; { use locale; my $n = $v + 0; } my $vcopy = $v;
setlocale(LC_NUMERIC, "radix_comma.UTF-8");
my $r3; { use locale; $r3 = $vcopy + 0; }
print "copy of a C-cached scalar, read under de use locale: ", g($r3), "\n";
