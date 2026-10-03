# local on an element of a threads::shared array when the array moves under it.
#
# A shared array's element is reached through a proxy SV that carries two pieces of magic
# (dist/threads-shared/shared.xs:101, "element SVs may have pointers to both the shared aggregate
# and the shared element"): tied-element magic (p) that addresses the aggregate by index in mg_len,
# and shared-scalar magic (n) whose mg_ptr is the shared element SV itself.  `local $a[1]` saves
# the old proxy with both.  On scope exit, leave_scope re-fetches index 1 and runs mg_set on the
# restored proxy, and the magic chain is ordered so the scalar magic runs first
# (sharedsv_elem_mg_STORE's comment, shared.xs:1077): sharedsv_scalar_mg_set (shared.xs:946)
# writes the saved value into the shared SV its mg_ptr names, wherever that SV now sits, and then
# sharedsv_elem_mg_STORE (shared.xs:1069) writes it again at mg_len.  While nothing moves the
# array the two writes land on the same element; after a shift or unshift they land on two.
#
# The plain array runs the same steps for contrast: one save record, one restore write, at the
# original index.  No second thread is needed; the double write is a property of the proxy.
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
