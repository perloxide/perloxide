use strict; use warnings; use Scalar::Util qw(refaddr weaken);
my %h=(k=>1); sub hk { $_[0] = 5 } hk($h{nokey}); hk($h{k}); sub hk2 { 1 } hk2($h{other}); print join(",", map {"$_=$h{$_}"} sort keys %h), " other:", (exists $h{other} ? "created":"absent"), "\n";
