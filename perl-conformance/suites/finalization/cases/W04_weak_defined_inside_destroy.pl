use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# Outside global destruction, weak references to a dying object are cleared after its DESTROY returns.
use Scalar::Util qw(weaken);
our $w;
package Peek; our @ISA = ('O'); sub DESTROY { print "in DESTROY weak is ", (defined $main::w ? 'defined' : 'undef'), "\n" }
package main;
my $s = Peek->new('p'); $w = $s; weaken $w;
undef $s;
print "after: weak is ", (defined $w ? 'defined' : 'undef'), "\n";
