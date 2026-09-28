# oracle-requires: locale de_DE.UTF-8
# 'use locale' is lexical to the statement doing the numification; the cache follows the scalar across calls.
use strict; use warnings; no warnings 'numeric';
use POSIX qw(setlocale LC_NUMERIC);
sub g { sprintf "%.17g", $_[0] }
setlocale(LC_NUMERIC, "de_DE.UTF-8") or die "no de_DE locale\n";
sub numify_in_locale { use locale; my $n = $_[0] + 0; $n }     # $_[0] aliases the caller's scalar
sub numify_plain     { my $n = $_[0] + 0; $n }
sub numify_copy_in_locale { use locale; my ($x) = @_; my $n = $x + 0; $n }
my $a = "" . "1,5"; my $ra = numify_in_locale($a); my $ca = $a + 0;
print "callee with use locale numifies caller's scalar: callee=", g($ra), " caller reads=", g($ca), "\n";
my $b = "" . "1,5"; my $rb = numify_plain($b); my $cb; { use locale; $cb = $b + 0; }
print "callee without use locale numifies first: callee=", g($rb), " caller under use locale reads=", g($cb), "\n";
my $c = "" . "1,5"; my $rc; { use locale; $rc = numify_plain($c); }
print "caller under use locale calls a plain callee: callee=", g($rc), "\n";
my $d = "" . "1,5"; my $rd = numify_copy_in_locale($d); my $cd = $d + 0;
print "callee copies then numifies under use locale: callee=", g($rd), " caller's scalar reads=", g($cd), "\n";
