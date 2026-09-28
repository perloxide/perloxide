use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my %h=(a=>1,b=>2); my @o; for (values %h) { delete $h{a}; push @o, defined $_ ? $_ : "undef" } print "@o | ", join(",", sort keys %h), "\n";
