use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# unweaken turns a weak holder back into a counted one.
use Scalar::Util qw(weaken unweaken isweak);
my $s = O->new('o'); my $w = $s; weaken $w; unweaken $w;
print "isweak: ", (isweak($w) ? 1 : 0), "\n";
undef $s; print "original released\n";
undef $w; print "unweakened released\n";
