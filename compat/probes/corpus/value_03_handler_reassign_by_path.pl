# A numeric-warning handler that reassigns the scalar under conversion, per conversion path.
# IV path (S_sv_2iuv_common): value parsed before the warning, installed after it.
# NV path (Perl_sv_2nv_flags): warning first, then Atof on whatever the scalar holds afterward.
use strict; use warnings;
use B ();
sub fl { my $f = B::svref_2object($_[0])->FLAGS; join '', ($f & B::SVp_IOK ? 'i' : ''), ($f & B::SVp_NOK ? 'n' : ''), ($f & B::SVp_POK ? 'p' : '') }
for my $path (['IV path ($s + 0)', sub { my $n = $_[0] + 0 }], ['NV path (sqrt $s)', sub { my $n = sqrt $_[0] }], ['NV path (sprintf "%g")', sub { my $n = sprintf "%g", $_[0] }]) {
    my $s = "" . "3abc";
    { local $SIG{__WARN__} = sub { $s = "49" }; $path->[1]->($s); }
    no warnings 'numeric';
    printf "%-24s string=%-4s flags=%-4s numeric read=%s  (a fresh \"49\" reads 49)\n", $path->[0], $s, fl(\$s), $s + 0;
}
