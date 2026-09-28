use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(1,2,3); sub two { $_[0] .= "x"; $_[1] .= "y" } two($a[0],$a[0]); print "@a\n";
