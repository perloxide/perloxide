use strict; use warnings; use Scalar::Util qw(refaddr weaken);
sub keep { \@_ } my $x=1; my $r = keep($x, 2); $x = 2; print "$$r[0] ", (refaddr(\$$r[0]) == refaddr(\$x) ? "same" : "diff"), "\n";
