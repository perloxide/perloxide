use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# A sub's return value is a temporary of the calling statement: used or discarded, it dies at that statement's end.
sub make { O->new($_[0]) }
make('discarded'), print "rest of statement\n";
print "name: ", make('used')->{n}, "\n";
print "next statement\n";
