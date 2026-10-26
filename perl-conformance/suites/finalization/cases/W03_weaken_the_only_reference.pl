use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# Weakening the only reference releases the object at once.
use Scalar::Util qw(weaken);
my $x = O->new('only');
weaken $x;
print "after weaken: ", (defined $x ? 'defined' : 'undef'), "\n";
