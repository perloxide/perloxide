use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# A destructor run while an exception unwinds may use eval freely: the propagating error survives.
package E; our @ISA = ('O'); sub DESTROY { print "D $_[0]{n}\n"; eval { die "inner\n" }; }
package main;
eval { my $x = E->new('e'); die "outer\n" };
print "caught: $@";
