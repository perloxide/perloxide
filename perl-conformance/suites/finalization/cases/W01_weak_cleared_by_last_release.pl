use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# A weak reference does not count; when the last strong one goes, the weak one reads undef.
use Scalar::Util qw(weaken);
my $s = O->new('o'); my $w = $s; weaken $w;
print "weak defined: ", (defined $w ? 1 : 0), "\n";
undef $s;
print "weak defined: ", (defined $w ? 1 : 0), "\n";
