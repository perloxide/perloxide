use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# `.=` on the last reference frees the object at the statement's end; plain assignment frees it inside the operation.
my $x = O->new('assign');
$x = 5, print "rest of assignment statement\n";
print "next statement\n";
my $y = O->new('concat');
$y .= 's', print "rest of concatenation statement\n";
print "next statement\n";
