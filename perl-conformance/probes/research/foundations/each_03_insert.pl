# Inserting during each(): the warning, and duplicates/skips once hsplit reorganizes buckets.
use strict; use warnings;
$| = 1;
local $SIG{__WARN__} = sub { my $m = shift; $m =~ s/ at .*//s; print "WARN: $m\n" };
my %h = map { $_ => 1 } 1..6;
my ($k) = each %h;
$h{new1} = 1;                        # insertion, no split expected at 7 keys/8 buckets? (depends)
my $c = 0; $c++ while each %h;
print "after one insert, remaining iterations=$c\n";
my %g = map { $_ => 1 } 1..5; my (%seen, $dups, $steps);
while (my ($x) = each %g) { $dups++ if $seen{$x}++; $g{"n$steps"} = 1 if ++$steps <= 50; last if $steps > 1000 }
printf "insert-each-step: steps=%d distinct=%d dups=%d final_keys=%d\n", $steps, scalar(keys %seen), $dups//0, scalar(keys %g);
