# Numification of "3abc": when is the numeric cache installed relative to the 'numeric' warning handler?
use strict; use warnings; use B ();
sub flags { my $f = B::svref_2object(\$_[0])->FLAGS; join '', ($f & B::SVf_IOK ? 'I' : '-'), ($f & B::SVf_NOK ? 'N' : '-'), ($f & B::SVf_POK ? 'P' : '-'), ($f & B::SVp_IOK ? 'i' : '-') }
our $x;
# (a) handler inspects the scalar under conversion
$x = "3abc";
{ local $SIG{__WARN__} = sub { print "  in handler: flags=", flags($x), "\n" }; my $n = $x + 0; print "(a) result=$n after: flags=", flags($x), "\n"; }
# (b) handler assigns to the scalar under conversion
$x = "3abc";
{ local $SIG{__WARN__} = sub { $x = "7xyz" }; my $n = $x + 0; print "(b) result=$n  \$x=$x  flags=", flags($x), "\n"; }
# (c) handler dies
$x = "3abc";
{ local $SIG{__WARN__} = sub { die "boom\n" }; my $n = eval { $x + 0 }; print "(c) eval=", ($n // 'undef'), " \$\@=$@", "    flags=", flags($x), "\n"; }
# (d) second conversion warns again iff no cache was installed
$x = "3abc"; my $count = 0;
{ local $SIG{__WARN__} = sub { $count++; die "boom\n" if $count == 1 }; eval { my $n = $x + 0 }; my $n2 = $x + 0; my $n3 = $x + 0; print "(d) warnings seen=$count\n"; }
