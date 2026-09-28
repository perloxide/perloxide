use strict; use warnings; use lib '/tmp/probe'; use fl; *fl=\&fl::fl;
use constant ZZ => "zz"; use constant TEN => "10"; use constant ELEVEN => 11;
print "TEN fresh flags: ", fl(\TEN), "   ZZ fresh: ", fl(\ZZ), "   ELEVEN: ", fl(\ELEVEN), "\n";
my $lo = "aa";
sub cnt { my @r = ($lo .. ZZ); scalar @r }
print "runtime range to ZZ: before=", cnt(); { no warnings; my $x = ZZ + 0; } print " after ZZ+0 elsewhere=", cnt(), " flags(ZZ)=", fl(\ZZ), "\n";
use constant ABC => "abc";
sub band { no warnings; my $r = ABC & $_[0]; join " ", map { sprintf "%02x", ord } split //, $r }
print "ABC & 'xyz' fresh: [", band("xyz"), "]"; { no warnings; my $x = ABC + 1 } print " after ABC+1 elsewhere: [", band("xyz"), "] flags(ABC)=", fl(\ABC), "\n";
# same-site plain literal under a *non-bitwise* mark-sensitive op: range, executed twice with a variable left side
sub rng { my @r = ($_[0] .. "e"); scalar @r }
print "range site ('a'..'e'): ", rng("a"); { no warnings; for my $v ("e") { } } print " again: ", rng("a"), "\n";
# does the range op mark its (non-readonly) operands?
{ my ($l,$r) = ("a","e"); my @x = ($l..$r); print "range operand marks: l=", fl(\$l), " r=", fl(\$r), "\n"; my ($n1,$n2)=("1","3"); my @y=($n1..$n2); print "numeric-looking range operand marks: ", fl(\$n1), " / ", fl(\$n2), "\n"; }
# bitwise on a non-readonly var persists
{ no warnings; my $v = "10"; my $r = $v & 5; print "var after '&' numeric: ", fl(\$v), "\n"; my $w = "10"; $r = $w & "abc"; print "var after '&' string: ", fl(\$w), "\n"; }
# readonly literal via alias + bitwise
{ no warnings; for my $v ("10") { my $r = $v & 5; print "aliased literal after '&' numeric: ", fl(\$v), "\n"; } }
