use strict; use warnings; use Scalar::Util qw(refaddr);
my @a; for (1..3) { my $x = $_; push @a, refaddr(\$x) } print "loop, ref dropped:   ", (@a == grep { $_ == $a[0] } @a) ? "same x3" : "differ", " ($a[0])\n";
sub f { my $x = shift; refaddr(\$x) } my @c = map { f($_) } 1..3; print "calls, ref dropped:  ", (@c == grep { $_ == $c[0] } @c) ? "same x3" : "differ", "\n";
my (@keep,@b); for (1..3) { my $x = $_; push @keep, \$x; push @b, refaddr(\$x) } print "loop, ref kept:      ", (3 == keys %{{map {$_=>1} @b}}) ? "3 distinct" : "repeat", "\n";
my @s; for my $i (1..3) { my $s = "str$i" x 10; push @s, refaddr(\$s) } print "string loop:         ", (@s == grep { $_ == $s[0] } @s) ? "same x3" : "differ", "\n";
my @arr=(1,2,3); my $r1 = \$arr[0]; my $a1 = refaddr($r1); undef $r1; print "element identity:    ", ($a1 == refaddr(\$arr[0]) ? "stable" : "changed"), "\n";
my @al; for (@arr) { push @al, refaddr(\$_) } print "foreach alias addr:  ", (join(",",@al) eq join(",", map { refaddr(\$arr[$_]) } 0..2)) ? "== element addrs" : "differ", "\n";
sub g { refaddr(\$_[0]) } my $y = 5; print "arg alias addr:      ", (g($y) == refaddr(\$y)) ? "== \\\$y" : "differ", "\n";
my @clos; for (1..2) { my $z = $_; push @clos, sub { \$z } } print "closure-captured:    ", (refaddr($clos[0]->()) == refaddr($clos[1]->()) ? "same" : "distinct"), "\n";
{ my @o; for my $i (1..3) { my $q = $i; my $r = \$q; push @o, refaddr($r); undef $r; } print "ref taken & dropped: ", (@o == grep { $_ == $o[0] } @o) ? "same x3" : "differ", "\n"; }
{ my @o; for my $i (1..3) { my $q = $i; my $r = \$q; push @o, refaddr($r); push @keep, $r if $i == 2 } print "kept only iter 2:    ", join(" ", map { $o[$_] == $o[0] ? "A" : "B" } 0..2), "\n"; }
