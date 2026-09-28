use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my $x = 1; sub hh { $_[0] = 2; die "boom\n" } eval { hh($x) }; print "$x ", ($@ =~ s/\n//r), "\n";
