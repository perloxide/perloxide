use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(1,2,3); my @o; for my $x (@a) { for my $y (@a) { shift @a if $y==2 } push @o, $x } print "@o | @a\n";
