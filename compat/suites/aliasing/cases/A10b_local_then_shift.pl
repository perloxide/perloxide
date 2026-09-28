use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(1,2); my @o; for (@a) { { local $_ = "L"; shift @a; } push @o, $_ } print "@o | @a\n";
