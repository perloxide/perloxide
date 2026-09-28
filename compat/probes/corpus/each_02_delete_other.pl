# Deleting a key other than the current one during each().
use strict; use warnings;
my @keys = ('a'..'z');
my %h = map { $_ => 1 } @keys;
my @order = keys %h;                 # this also resets the iterator
my %pos; @pos{@order} = 0..$#order;
# (1) delete an already-visited key, (2) delete a not-yet-visited key
my ($first) = each %h;               # position 0
my $third = $order[2];
delete $h{$third};                   # unvisited -> expect it to be skipped
my @rest; while (my ($k) = each %h) { push @rest, $k }
my @expect = grep { $_ ne $first && $_ ne $third } @order;
print "unvisited-deleted skipped, remaining order preserved: ", ("@rest" eq "@expect" ? "yes" : "NO"), "\n";
# (3) delete current, then delete its chain successor (hv_delete_common patches HeNEXT of the lazy entry)
my %c = map { $_ => 1 } 1..2000; my (%v, $d);
while (my ($k) = each %c) {
    $d++ if $v{$k}++;
    delete $c{$k};
    # delete some other still-present key too, arbitrary but deterministic
    my $o = $k + 1; delete $c{$o} if exists $c{$o};
}
printf "delete current + delete other: visited=%d dups=%d left=%d\n", scalar(keys %v), $d//0, scalar(keys %c);
