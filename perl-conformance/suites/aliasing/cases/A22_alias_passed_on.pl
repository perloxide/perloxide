use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(1,2,3); sub inner { $_[0]++ } for (@a) { inner($_) } print "@a\n";
