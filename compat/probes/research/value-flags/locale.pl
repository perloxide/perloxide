use strict; no warnings; use POSIX qw(setlocale LC_NUMERIC); use B;
sub fl { my $f=B::svref_2object($_[0])->FLAGS; join ",", grep { $f & B->can("SV".$_)->() } qw(f_IOK f_NOK f_POK p_IOK p_NOK p_POK) }
my $ok = setlocale(LC_NUMERIC, "de_DE.UTF-8"); print "setlocale: ", ($ok // "FAILED"), "\n";
{ use locale; my $x="3,5"; my $n = $x + 0; print "de: '3,5'+0 = $n flags=", fl(\$x), "\n"; my $y = $x; no locale; print "  outside: cached x+0=", $x+0, " copy y+0=", $y+0, " fresh '3,5'+0=", "3,5"+0, "\n"; my $s = 3.5; { use locale; print "  stringify 3.5 in de: ", "$s", " flags=", fl(\$s), "\n"; } print "  stringify 3.5 in C: $s\n"; }
{ use locale; my $x="3.5"; my $n = $x + 0; print "de: '3.5'+0 = $n flags=", fl(\$x), "\n"; }
{ use locale; my $x="3,5"; my $n = $x | 0; print "de: '3,5'|0 = $n flags=", fl(\$x), "\n"; my $z="3,5"; my $g = sprintf "%.17g", $z; print "de: %.17g of '3,5' = $g flags=", fl(\$z), "\n"; }
{ my $x="3,5"; my $n; { use locale; $n = $x * 1.5; } print "de nv-path then C: x+0=", $x+0, " flags=", fl(\$x), "\n"; }
{ use locale; setlocale(LC_NUMERIC, "C"); my $x="3,5"; my $n = $x+0; print "use locale but LC_NUMERIC=C: '3,5'+0=$n flags=", fl(\$x), "\n"; setlocale(LC_NUMERIC, "de_DE.UTF-8"); print "  then de, cached: ", $x+0, "\n"; my $w="3,5"; print "  fresh in de: ", $w+0, "\n"; }
{ use locale; my $x="1e3,5"; print "de: '1e3,5'+0=", $x+0, " flags=", fl(\$x), "\n"; my $v="3,5x"; print "de: '3,5x'+0=", $v+0, " flags=", fl(\$v), "\n"; }
{ my $x="3,5"; { use locale; my $t = $x + 0; } { use locale; my $s = "$x"; } print "str after: $x\n"; }
{ use locale; my $s = 3.5; my $t = "$s"; print "3.5 stringified in de: [$t]; then outside: [", do { no locale; "$s" }, "]\n"; }
