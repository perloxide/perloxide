use strict; use warnings; use Scalar::Util qw(refaddr);
my (@a1, @a2, @keep);
for my $i (1 .. 3) { my $x = $i; my $r = \$x; push @a1, refaddr($r); }
for my $i (1 .. 3) { my $x = $i; push @keep, \$x; push @a2, refaddr(\$x); }
print "ref_dropped_same_addr=", (($a1[0] == $a1[1] && $a1[1] == $a1[2]) ? 1 : 0), "\n";
print "ref_kept_distinct=",
    (($a2[0] != $a2[1] && $a2[1] != $a2[2] && $a2[0] != $a2[2]) ? 1 : 0), "\n";
