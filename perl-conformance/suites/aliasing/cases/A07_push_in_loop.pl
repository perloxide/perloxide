use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(1,2); my @o; for (@a) { push @a, $_+10 if $_ < 3; push @o, $_ } print "@o | @a\n";
