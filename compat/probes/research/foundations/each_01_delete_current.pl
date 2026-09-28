# Deleting the key most recently returned by each(): every key visited once, no warning.
use strict; use warnings;
my %h = map { $_ => 1 } 'a'..'z', 'aa'..'az';
my $n = keys %h; my (%seen, $dups);
while (my ($k) = each %h) { $dups++ if $seen{$k}++; delete $h{$k}; }
printf "start=%d visited=%d dups=%d left=%d\n", $n, scalar(keys %seen), $dups//0, scalar(keys %h);
