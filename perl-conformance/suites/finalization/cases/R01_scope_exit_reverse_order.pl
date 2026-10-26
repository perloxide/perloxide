use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# Lexicals die at scope exit in reverse order of declaration.
{ my $a = O->new('a'); my $b = O->new('b'); my $c = O->new('c'); print "end of block\n"; }
print "after block\n";
