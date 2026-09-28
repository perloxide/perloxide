use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(1,2,3); my @o; for (@a) { @a = (7,8,9) if $_==1; push @o, $_ } print "@o | @a\n";
