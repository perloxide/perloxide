use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# The temporaries of a foreach list live until the loop is left.
for my $x (O->new('a'), O->new('b')) { print "iteration $x->{n}\n" }
print "after loop\n";
