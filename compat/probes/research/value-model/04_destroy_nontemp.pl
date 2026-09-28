package O; sub new { bless {}, shift } sub DESTROY { print "d " }
package main; $| = 1;
my $x = O->new;
print "assign ";
$x = 5;
print "| ";
my $y = O->new;
print "undef ";
undef $y;
print "|\n";
