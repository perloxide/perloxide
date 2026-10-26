use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# With no DESTROY in the hierarchy, AUTOLOAD is called for it.
package A; our $AUTOLOAD; sub new { bless {}, $_[0] } sub AUTOLOAD { print "AUTOLOAD $AUTOLOAD\n"; return }
package main;
{ my $x = A->new; }
print "after\n";
