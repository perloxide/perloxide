use strict; use warnings;
use POSIX qw(setlocale LC_NUMERIC);
use locale;
setlocale(LC_NUMERIC, 'de_DE.UTF-8') or die "de_DE.UTF-8 unavailable\n";
my $s = "1,5";
my $n1 = $s + 0;
setlocale(LC_NUMERIC, 'C');
my $n2 = $s + 0;
my $n3 = sprintf '%g', $s;
print "de_first: n1=$n1 c_reread=$n2 c_g=$n3\n";

setlocale(LC_NUMERIC, 'C');
my $t = "1,5";
my ($fired, $w) = (0, 0);
{
    local $SIG{__WARN__} = sub { $w++ };
    my $m1 = $t + 0;
    setlocale(LC_NUMERIC, 'de_DE.UTF-8');
    my $m2 = $t + 0;
    print "c_first: m1=$m1 de_reread=$m2 warns=$w\n";
}

# A copy made before any numification parses fresh under the current locale;
# a copy made after carries the cache.
setlocale(LC_NUMERIC, 'C');
my $u = "2,5";
my $copy = $u;
setlocale(LC_NUMERIC, 'de_DE.UTF-8');
my $c1 = $copy + 0;
setlocale(LC_NUMERIC, 'C');
my $v = "3,5";
my $pre = do { no warnings; $v + 0 };
my $copy2 = $v;
setlocale(LC_NUMERIC, 'de_DE.UTF-8');
my $c2 = $copy2 + 0;
print "copies: fresh_under_de=$c1 cache_under_c_then_read_de=$c2\n";

# setlocale inside the warning handler, mid-conversion.
setlocale(LC_NUMERIC, 'C');
my $x = "4,5";
my $f2 = 0;
local $SIG{__WARN__} = sub { return if $f2++; setlocale(LC_NUMERIC, 'de_DE.UTF-8') };
my $w1 = $x + 0;
my $w2 = $x + 0;
my $wg = sprintf '%g', $x;
print "handler_switch: w1=$w1 reread=$w2 g=$wg\n";
