use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# A reference cycle keeps both objects alive past their scope; breaking it releases them in chain order.
use Scalar::Util qw(weaken);
my $handle;
{ my $a = O->new('a'); my $b = O->new('b'); $a->{peer} = $b; $b->{peer} = $a; $handle = $a; weaken $handle; }
print "scope left, handle ", (defined $handle ? 'defined' : 'undef'), "\n";
$handle->{peer}{peer} = undef;
print "cycle broken, handle ", (defined $handle ? 'defined' : 'undef'), "\n";
