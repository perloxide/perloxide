# local on an array element, traced by SV identity through structural changes.
#
# Facts shown (each line prints the SV addresses last, so the columns stay aligned after the
# harness rewrites addresses to ADDRn):
#   - the save stack holds the element's SV, not its value: a reference taken before the local
#     names that SV, reads the pre-local value throughout the scope, and a write through it is
#     what the restore brings back (3 -> 27 -> 729 while the SV is out of the array);
#   - the SV that local installs is an ordinary element: shift moves it and finally returns it,
#     and it lives on in $r2 after the scope with the localized value;
#   - shift returns the element's SV itself, not a copy (the addresses match the array's);
#   - the restore is by the original index into whatever the array has become: an emptied
#     array is extended to that index, and the skipped slots are holes (exists is false), not
#     undef elements;
#   - taking references to the array in lvalue context (\(@x)) vivifies the holes.
use strict; use warnings;
$| = 1;

sub fmt { my ($v) = @_; !defined $v ? 'undef' : ref $v ? '\\' . fmt($$v) : $v }
sub list { '(' . join(', ', map { fmt($_) } @_) . ')' }
sub addrs { join ' ', map { "$_" } @_ }
sub line { my ($code, $name, $value, @refs) = @_;
    if (@refs) { printf "%-20s# %-4s= %-28s=> %s\n", $code, $name, $value, addrs(@refs) }
    else       { printf "%-20s# %-4s= %s\n", $code, $name, $value } }
sub blank { print "\n" }
sub exists_lines { my ($x) = @_;
    printf "%-20s# \$#x = %-3d => scalar(\@x) = %d\n", '', $#$x, scalar @$x;
    printf "%-20s# \$x[%d] %s\n", '', $_, exists $x->[$_] ? 'exists' : 'does not exist' for 0 .. 2 }

my @x = (1, 2, 3);
line 'my @x = (1, 2, 3);', '@x', list(@x), \(@x);
my $r = \$x[2];
line 'my $r = \$x[2];', '$r', fmt($r), $r;
my $r2 = $r;
line 'my $r2 = $r;', '$r2', fmt($r2), $r2;
blank;

print "do {                # scope begins\n";
do {
    blank;
    local $x[2] = 5;
    line '  local $x[2] = 5;', '@x', list(@x), \(@x);
    line '', '$r', fmt($r), $r;
    line '', '$r2', fmt($r2), $r2;
    blank;
    $r2 = \shift @x;
    line '  $r2 = \shift @x;', '@x', list(@x), \(@x);
    line '', '$r', fmt($r), $r;
    line '', '$r2', fmt($r2), $r2;
    blank;
    $$r **= 3;
    line '  $$r **= 3;', '$r', fmt($r), $r;
    blank;
    $r2 = \shift @x;
    line '  $r2 = \shift @x;', '@x', list(@x), \(@x);
    line '', '$r', fmt($r), $r;
    line '', '$r2', fmt($r2), $r2;
    blank;
    $$r **= 2;
    line '  $$r **= 2;', '$r', fmt($r), $r;
    line '', '$r2', fmt($r2), $r2;
    blank;
    $r2 = \shift @x;
    line '  $r2 = \shift @x;', '@x', list(@x);
    line '', '$r', fmt($r), $r;
    line '', '$r2', fmt($r2), $r2;
    blank;
    exists_lines(\@x);
    blank;
    print "}                   # scope ends\n";
};
blank;
exists_lines(\@x);
blank;

my @y = \(@x);
line 'my @y = \(@x);', '@y', list(@y), @y;
blank;
exists_lines(\@x);
blank;
line '', '@x', list(@x), \(@x);
line '', '$r', fmt($r), $r;
line '', '$r2', fmt($r2), $r2;
blank;
$$r **= 2;
line '$$r **= 2;', '$r', fmt($r), $r;
blank;
line '', '@x', list(@x), \(@x);
line '', '$r', fmt($r), $r;
line '', '$r2', fmt($r2), $r2;
