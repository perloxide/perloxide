use strict; use warnings;
local $SIG{__WARN__} = sub { print "WARN\n" };
my %h = map { $_ => 1 } 1..6; my ($k) = each %h; $h{new} = 1; each %h;
print "done\n";
