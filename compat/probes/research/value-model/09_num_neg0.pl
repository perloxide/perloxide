my $a = "-0"; my $v = $a + 0;
printf "intfirst: plus=%s g=%s\n", $a + 0, sprintf("%g", $a);
my $b = "-0"; my $g = sprintf "%g", $b;
printf "gfirst: g=%s plus=%s\n", $g, $b + 0;
