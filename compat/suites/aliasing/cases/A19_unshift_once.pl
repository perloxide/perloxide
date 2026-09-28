use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my $done; my @a=(1,2,3); my @o; for (@a) { unshift @a, 0 if $_==1 && !$done++; push @o, $_ } print "@o | @a\n";
