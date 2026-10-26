use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# DESTROY receives exactly the object, runs in phase RUN for a death during the program, and as a method of its class.
package Q; our @ISA = ('O'); sub DESTROY { print "args ", scalar(@_), " ref ", ref($_[0]), " phase ${^GLOBAL_PHASE}\n" }
package main;
{ my $x = Q->new('q'); }
print "after\n";
