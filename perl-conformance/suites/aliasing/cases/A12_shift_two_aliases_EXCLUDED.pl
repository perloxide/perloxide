use strict; use warnings; use Scalar::Util qw(refaddr weaken);
our @g=(1,2,3); sub three { my $z = shift @g; $_[0] .= "!"; $_[1] .= "?"; $z . " [" . join(" ",@g) . "] " . $_[0] . " " . $_[1] } print three($g[0],$g[0]), " | @g\n";
