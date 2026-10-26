use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# An object holding another dies first; the held object dies as its holder's body is freed, after the holder's DESTROY.
{ my $outer = O->new('outer'); $outer->{inner} = O->new('inner'); }
print "after\n";
