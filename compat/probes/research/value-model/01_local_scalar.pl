use strict; use warnings; use Scalar::Util qw(refaddr);
our $x = "old";
my $before = \$x;
{
    local $x = "new";
    my $inside = \$x;
    printf "inside: fresh_addr=%d old_via_ref=%s new_val=%s\n",
        (refaddr($inside) != refaddr($before)) ? 1 : 0, $$before, $x;
}
printf "after: val=%s addr_restored=%d\n", $x, (refaddr(\$x) == refaddr($before)) ? 1 : 0;

# Plain `local $x` with no assignment behaves the same way.
our $y = "orig";
my $yb = \$y;
{
    local $y;
    printf "bare: fresh_addr=%d newval=%s\n",
        (refaddr(\$y) != refaddr($yb)) ? 1 : 0, defined $y ? $y : "undef";
}
printf "bare after: val=%s addr_restored=%d\n", $y, (refaddr(\$y) == refaddr($yb)) ? 1 : 0;
