use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# Only the release of the last reference runs DESTROY.
my $x = O->new('shared'); my $y = $x; my @h = ($x);
undef $x; print "x released\n";
@h = (); print "array released\n";
undef $y; print "y released\n";
