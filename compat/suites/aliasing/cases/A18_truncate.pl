use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(1,2,3); my @o; for (@a) { $#a = 0 if $_==1; push @o, $_ } print "@o | @a\n";
