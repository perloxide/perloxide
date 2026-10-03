# oracle-requires: threads
# local on a threads::shared array element while the array moves under it: the element proxy names
# its target by index and by shared SV, and the restore writes the saved value through both.  The
# plain array beside it takes one restore write at the original index.  See
# probes/research/value-model/24_local_shared_elem.pl for the mechanism in shared.xs.
use strict; use warnings;
use threads; use threads::shared;

sub show {
    my ($label, @v) = @_;
    printf "%-34s (%s)\n", $label, join(', ', map { defined $_ ? $_ : 'undef' } @v);
}

for my $move (['shift', sub { shift @{ $_[0] } }], ['unshift 0', sub { unshift @{ $_[0] }, 0 }]) {
    my ($name, $op) = @$move;
    for my $kind ('plain', 'shared') {
        my @a; share(@a) if $kind eq 'shared';
        @a = (10, 20, 30);
        show "$kind, start", @a;
        {
            local $a[1] = 99;
            show "  local \$a[1] = 99", @a;
            $op->(\@a);
            show "  $name", @a;
        }
        show "$kind, after scope", @a;
        print "\n";
    }
}

# The same double write without any structural change: a second write to the element between the
# save and the restore goes to the shared SV that both magics still agree on, so it is simply
# overwritten by the restore -- the same as plain.  Only movement separates the two addresses.
for my $kind ('plain', 'shared') {
    my @a; share(@a) if $kind eq 'shared';
    @a = (10, 20, 30);
    {
        local $a[1] = 99;
        $a[1] = 77;
    }
    show "$kind, write in scope, no move", @a;
}
