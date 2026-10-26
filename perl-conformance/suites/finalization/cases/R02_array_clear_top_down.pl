use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# Clearing an array frees its elements from the highest index down, by assignment and by undef alike.
my @a = map { O->new("a$_") } 0 .. 2;
@a = ();
print "cleared by assignment\n";
my @b = map { O->new("b$_") } 0 .. 2;
undef @b;
print "cleared by undef\n";
