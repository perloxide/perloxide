use strict; use warnings; use B;
sub hmax { B::svref_2object($_[0])->MAX }
my %h = map { $_ => 1 } 1 .. 100;
my $m1 = hmax(\%h);
%h = ();
my $m2 = hmax(\%h);
my %g = map { $_ => 1 } 1 .. 100;
my $m3 = hmax(\%g);
undef %g;
my $m4 = hmax(\%g);
print "populated_max=$m1 after_empty_assign=$m2 (kept=", ($m2 == $m1 ? 1 : 0),
    ") populated2=$m3 after_undef=$m4 (kept=", ($m4 == $m3 ? 1 : 0), ")\n";
