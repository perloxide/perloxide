use strict; use warnings; use Scalar::Util qw(refaddr);
our %h = (k => 1);
my $old = \$h{k};
{
    local $h{k} = 9;
    printf "helem: rebound=%d old_via_ref=%s new_val=%s\n",
        (refaddr(\$h{k}) != refaddr($old)) ? 1 : 0, $$old, $h{k};
}
printf "helem after: val=%s addr_restored=%d\n", $h{k}, (refaddr(\$h{k}) == refaddr($old)) ? 1 : 0;

our @a = (10, 20);
{
    local $a[5] = 50;
    printf "absent: len_in=%d a5=%s\n", scalar(@a), $a[5];
}
printf "absent after: len=%d exists5=%d\n", scalar(@a), exists $a[5] ? 1 : 0;

our @b = (10, 20);
{
    local $b[5] = 50;
    $b[7] = 70;
}
printf "grow after: len=%d exists5=%d b7=%s\n",
    scalar(@b), exists $b[5] ? 1 : 0, defined $b[7] ? $b[7] : 'undef';

# What does restore target if the array is clobbered inside the scope?
our @c = (1, 2, 3);
my $oldc = \$c[1];
{
    local $c[1] = 99;
    @c = ();
}
printf "clobber after: len=%d exists1=%d c1=%s old_ref_still=%s\n",
    scalar(@c), exists $c[1] ? 1 : 0, defined $c[1] ? $c[1] : 'undef', $$oldc;
