use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(1,2,3); my @r; for (@a) { push @r, \$_ } ${$r[0]} = 9; print "@a ", (refaddr(\$a[0]) == refaddr($r[0]) ? "same" : "diff"), "\n";
