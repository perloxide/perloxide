package O; sub new { bless { t => $_[1] }, $_[0] } sub DESTROY { print "d$_[0]{t} " }
package main; $| = 1;
sub h3 { O->new("h"); }
h3(), O->new("q");
print "next\n";
