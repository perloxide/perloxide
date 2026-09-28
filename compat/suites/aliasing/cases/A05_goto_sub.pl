use strict; use warnings; use Scalar::Util qw(refaddr weaken);
sub gg { $_[0] = "g"; "done" } sub ff { goto &gg } my $v = "v"; ff($v); print "$v\n";
