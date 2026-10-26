use strict; use warnings; $| = 1;
$SIG{__WARN__} = sub { my $m = $_[0]; $m =~ s/ at \S+ line \d+\.$//m; print "warn: $m" };
package O; sub new { my ($c, $n) = @_; bless { n => $n }, $c }
sub DESTROY { print "D $_[0]{n}\n" }
package main;
# A temporary made in a condition dies at the next drain: after an if body has run, but at the first statement of a
# while body.  A lexical declared in an if condition belongs to the enclosing block and lives to its end.
if (O->new('if')) { print "if body\n" }
print "after if\n";
my $n = 0;
while ($n++ < 1 and O->new('while')) { print "while body\n" }
print "after while\n";
{ if (my $k = O->new('lexical')) { print "if body with lexical\n" } print "after if, same block\n"; }
print "after block\n";
