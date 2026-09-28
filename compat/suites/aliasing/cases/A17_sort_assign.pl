use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(3,1,2); my @o; for (@a) { @a = sort @a if $_==3; push @o, $_ } print "@o | @a\n";
