# oracle-variant: plain PRIME=0
# oracle-variant: prime PRIME=1
# oracle-variant: resurrect RESURRECT=1
# Global destruction order. Every object is held only by package-reachable SVs; each holder's address is
# recorded before destruction so DESTROY order can be compared with allocation order and arena position.
# PRIME=1 scrambles the SV head free list before any object or holder is allocated.
# RESURRECT=1 makes O1's DESTROY store its invocant in a global during global destruction.
use strict; use warnings;
use Scalar::Util qw(refaddr reftype weaken);
$| = 1;
package Obj;
sub new { my ($c, $n) = @_; bless { name => $n }, $c }
sub DESTROY {
    my $name = Scalar::Util::reftype($_[0]) eq 'HASH' ? $_[0]{name} : 'GS';
    print "DESTROY $name phase=${^GLOBAL_PHASE}\n";
    $main::SAVED = $_[0] if $ENV{RESURRECT} && $name eq 'O1' && ${^GLOBAL_PHASE} eq 'DESTRUCT';
}
package main;
our (%REG, @ARR, $WEAK, $SAVED, $GS);
if ($ENV{PRIME}) {
    my @pool = map { my $x = $_; \$x } 1 .. 400;
    undef $pool[($_ * 151) % 400] for 0 .. 399;
}
my @tmp = map { Obj->new("O$_") } 0 .. 9;           # objects blessed in order 0..9
for my $i (7, 2, 9, 0, 5, 1, 8, 3, 6, 4) {          # holders allocated in this order
    if ($i == 9) { push @ARR, $tmp[$i] } else { $REG{"k$i"} = $tmp[$i] }
}
@tmp = ();
$REG{k3}{peer} = $REG{k4}; $REG{k4}{peer} = $REG{k3};   # strong cycle
$REG{k5}{self} = $REG{k5};                              # self cycle
$REG{k6}{child} = $REG{k7};                             # O7 held twice
$REG{k2}{kid} = delete $REG{k8};                        # O8 held only inside O2
$WEAK = $REG{k1}; weaken($WEAK);                        # weak holder: phase 1 clears it without a decrement
bless \$GS, 'Obj';                                      # the glob's scalar slot is itself an object
{ my $leak = Obj->new('L'); Internals::SvREFCNT(%$leak, 2); }   # object with no holder at all
END {
    my @h;
    for my $k (sort keys %REG) { push @h, [ "\$REG{$k}", refaddr(\$REG{$k}), $REG{$k}{name}, 'root' ] }
    push @h, [ '$ARR[0]', refaddr(\$ARR[0]), $ARR[0]{name}, 'root' ];
    push @h, [ '$WEAK', refaddr(\$WEAK), 'O1', 'weak' ];
    push @h, [ '{peer} in O3', refaddr(\$REG{k3}{peer}), 'O4', 'O3' ], [ '{peer} in O4', refaddr(\$REG{k4}{peer}), 'O3', 'O4' ],
             [ '{self} in O5', refaddr(\$REG{k5}{self}), 'O5', 'O5' ], [ '{child} in O6', refaddr(\$REG{k6}{child}), 'O7', 'O6' ],
             [ '{kid} in O2', refaddr(\$REG{k2}{kid}), 'O8', 'O2' ];
    printf "HOLDER %-14s 0x%x -> %s owner=%s\n", @$_ for sort { $a->[1] <=> $b->[1] } @h;
}
