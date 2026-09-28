use strict; use warnings;
package O; sub new { bless {}, shift } sub DESTROY { print "d " }
package main; $| = 1;
sub o { O->new() }
print "IF: ";
if (o()) { print "body "; }
print "| WHILE: ";
my $n = 0;
sub mk { $n++ < 1 ? O->new() : 0 }
while (mk()) { print "body "; }
print "|\n";
