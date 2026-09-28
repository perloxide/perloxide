use strict; use warnings;
package O; sub new { bless {}, shift } sub DESTROY { print "d " }
package main; $| = 1;
sub o { O->new() }
print "IF1: ";
if (o()) { print "body "; }
print "| IF2: ";
if (o()) { my $z = 1; print "body "; }
print "|\n";
