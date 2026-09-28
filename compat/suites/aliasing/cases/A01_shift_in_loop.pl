use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(1,2,3,4); my @o; for (@a) { my $s = shift @a; push @o, "s=$s _=$_ [@a]" } print join(" | ", @o), "\n";
