use strict; use warnings;
my %h = map { $_ => 1 } 1 .. 10;
my $count = 0;
while (my ($k) = each %h) { delete $h{$k}; $count++ }
print "delcur: iters=$count left=", scalar(keys %h), "\n";

%h = map { $_ => 1 } "a" .. "j";
my (@seen, $victim);
while (my ($k) = each %h) {
    push @seen, $k;
    if (!defined $victim) {
        ($victim) = grep { $_ ne $k } sort keys %h;
        delete $h{$victim};
    }
}
my $returned = grep { $_ eq $victim } @seen;
print "delother: victim_returned=$returned iters=", scalar(@seen), "\n";

%h = map { $_ => 1 } 1 .. 8;
my $warned = 0;
local $SIG{__WARN__} = sub { $warned++ if $_[0] =~ /each\(\)/ };
my (%seen, $i);
$i = 0;
while (my ($k) = each %h) {
    $seen{$k}++;
    if ($i++ == 2) { $h{"n$_"} = 1 for 1 .. 40 }
    last if $i > 500;
}
my $dups = grep { $seen{$_} > 1 } keys %seen;
my $missed = grep { !exists $seen{$_} } keys %h;
print "insert: iters=$i dups=$dups missed=$missed warned=$warned\n";

%h = map { $_ => 1 } 1 .. 10;
my ($k1) = each %h;
my $nk = keys %h;
my ($k1b) = each %h;
print "keys_resets=", ($k1b eq $k1 ? 1 : 0), "\n";
%h = map { $_ => 1 } 1 .. 10;
($k1) = each %h;
my $sc = scalar(%h);
my $ex = exists $h{5};
my ($k2) = each %h;
print "scalar_exists_preserve=", ($k2 ne $k1 ? 1 : 0), "\n";
