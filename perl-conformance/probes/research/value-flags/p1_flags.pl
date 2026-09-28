use strict; use warnings; use lib '/tmp/probe'; use fl; use Scalar::Util qw(isdual dualvar);
*show = \&fl::show; *fl = \&fl::fl;
{ my $s="10"; show('"10" fresh',\$s); my $t=$s+0; show('"10" after +0',\$s); my $c=$s; show('  copy of it',\$c); }
{ my $s="10"; my $t=$s*1.5; show('"10" after *1.5 (sv_2nv)',\$s); }
{ my $s="10"; my $t=sprintf("%g",$s); show('"10" after %g',\$s); }
{ my $s="1.5"; my $t=$s+0; show('"1.5" after +0',\$s); }
{ my $s="1.5"; my $t=$s*1.5; show('"1.5" after *1.5',\$s); }
{ no warnings; my $s="abc"; my $t=$s+0; show('"abc" after +0',\$s); }
{ no warnings; my $s="3abc"; my $t=$s+0; show('"3abc" after +0',\$s); }
{ no warnings; my $s="3abc"; my $t=$s*1.5; show('"3abc" after *1.5',\$s); }
{ my $s="1e3"; my $t=$s+0; show('"1e3" after +0',\$s); }
{ my $s="18446744073709551615"; my $t=$s+0; show('"UV_MAX" after +0',\$s); }
{ my $s="18446744073709551616"; my $t=$s+0; show('"UV_MAX+1" after +0',\$s); }
{ my $s="1e19"; my $t=$s+0; show('"1e19" after +0',\$s); }
{ my $s="-1e19"; my $t=$s+0; show('"-1e19" after +0',\$s); }
{ my $s="-0"; my $t=$s+0; show('"-0" after +0',\$s); my $g=sprintf("%g",$s); show("\"-0\" +0 then %g (prints $g)",\$s); }
{ my $s="-0"; my $g=sprintf("%g",$s); show("\"-0\" %g first (prints $g)",\$s); my $t=$s+0; my $g2=sprintf("%g",$s); show("\"-0\" %g, +0, %g (prints $g2)",\$s); }
{ my $i=10; show('10 fresh',\$i); my $t="$i"; show('10 after "$i"',\$i); print "   isdual(10 after stringify) = ", (isdual($i)?1:0), "\n"; }
{ my $i=10; my $t=$i*1.5; show('10 after *1.5',\$i); }
{ my $n=3.0; show('3.0 fresh',\$n); my $t=$n+1; show('3.0 after +1',\$n); }
{ my $n=3.5; my $t=$n+1; show('3.5 after +1',\$n); my $u="$n"; show('3.5 then "$n"',\$n); }
{ my $b=!!1; show('!!1',\$b); my $c=!!0; show('!!0',\$c); }
{ my $d=dualvar(3,"77"); show('dualvar(3,"77")',\$d); }
{ no warnings; my $s="12\0xyz"; my $t=$s+0; show('"12\\0xyz" after +0',\$s); }
{ no warnings; my $s="0x10"; my $t=$s+0; show("\"0x10\" after +0 (=$t)",\$s); }
{ my $s=" 12 "; my $t=$s+0; show('" 12 " after +0',\$s); }
{ my $s="Inf"; my $t=$s+0; show('"Inf" after +0',\$s); }
