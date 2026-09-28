use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(1,2,3); my @o; for (@a) { weaken(my $w = \$_) if $_ == 2; push @o, $_ } print "@o | @a\n";
