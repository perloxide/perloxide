use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my %h=(a=>1,b=>2); $_ *= 10 for values %h; print join(",", map {"$_=$h{$_}"} sort keys %h), "\n";
