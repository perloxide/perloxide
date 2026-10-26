use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# A destructor that reblesses the object into another class runs that class's DESTROY next, in the same death.
package R; our @ISA = ('O'); sub DESTROY { print "R::DESTROY\n"; bless $_[0], 'P' }
package P; sub DESTROY { print "P::DESTROY\n" }
package main;
{ my $x = R->new('r'); }
print "after\n";
