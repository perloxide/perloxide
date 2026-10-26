use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# An exception thrown by DESTROY becomes an "(in cleanup)" warning and does not propagate.
package X; our @ISA = ('O'); sub DESTROY { print "D $_[0]{n}\n"; die "from DESTROY\n" }
package main;
{ my $x = X->new('x'); }
print "still running\n";
