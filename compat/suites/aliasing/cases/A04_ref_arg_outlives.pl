use strict; use warnings; use Scalar::Util qw(refaddr weaken);
sub mk { my $r = \$_[0]; sub { $$r } } my $x = 5; my $c = mk($x); $x = 6; print $c->(); { my $y = 1; $c = mk($y); } print " ", $c->(), "\n";
