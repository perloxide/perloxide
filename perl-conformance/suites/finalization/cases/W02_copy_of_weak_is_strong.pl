use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# The weak flag belongs to the holder: a copy of a weak reference is an ordinary strong reference.
use Scalar::Util qw(weaken isweak);
my $s = O->new('o'); my $w = $s; weaken $w; my $c = $w;
print "w weak: ", (isweak($w) ? 1 : 0), ", c weak: ", (isweak($c) ? 1 : 0), "\n";
undef $s; print "strong released\n";
undef $c; print "copy released\n";
