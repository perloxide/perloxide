use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my @a=(1,2,3); my @s; for my $x (@a) { push @s, sub { $x } } $a[0]=99; print join(",", map { $_->() } @s), "\n";
