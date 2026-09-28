# oracle-requires: locale de_DE.UTF-8
# setlocale inside a numeric-warning handler during a numification. The IV conversion path parses the NV
# before the warning; the NV conversion path parses it after the handler returns.
use strict; use warnings;
use POSIX qw(setlocale LC_NUMERIC);
use B ();
sub g { sprintf "%.17g", $_[0] }
sub fl { my $f = B::svref_2object($_[0])->FLAGS; join '', ($f & B::SVp_IOK ? 'i' : ''), ($f & B::SVp_NOK ? 'n' : ''), ($f & B::SVp_POK ? 'p' : '') }
for my $case (['de', 'C'], ['C', 'de_DE.UTF-8']) {
    my ($start, $switch_to) = @$case;
    my $start_name = $start eq 'de' ? 'de_DE.UTF-8' : 'C';
    for my $path (['IV path ($s + 0)', sub { use locale; my $n = $_[0] + 0; }], ['NV path (sqrt $s)', sub { use locale; my $n = sqrt $_[0]; }]) {
        setlocale(LC_NUMERIC, $start_name) or die;
        my $s = "" . "2,25x";
        my $handler_ran = 0;
        {
            local $SIG{__WARN__} = sub { $handler_ran++; setlocale(LC_NUMERIC, $switch_to) };
            $path->[1]->($s);
        }
        no warnings 'numeric';
        my $cached = $s + 0;                       # read back the cache outside use locale
        printf "start %-11s handler switches to %-11s %-18s handler_ran=%d flags=%s cached NV=%s\n", $start_name, $switch_to, $path->[0], $handler_ran, fl(\$s), g($cached);
    }
}
