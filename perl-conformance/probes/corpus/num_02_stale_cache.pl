use strict; use warnings;
our $x = "3abc";
{ local $SIG{__WARN__} = sub { $x = "7xyz" }; my $n = $x + 0; }
no warnings;
printf "string=%s  numeric=%s  (a fresh \"7xyz\" numifies to %s)\n", $x, $x + 0, "7xyz" + 0;
