# Validate the traversal model: visit bucket (riter ^ xhv_rand) & max for riter = 0..max; chain order within a bucket.
use strict; use warnings;
use Hash::Util qw(bucket_array hash_traversal_mask);
for my $n (5, 40, 700) {
    my %h; $h{"k$_"} = 1 for 1..$n;
    my @actual = keys %h;                          # creates the aux struct (xhv_rand)
    my $mask = hash_traversal_mask(\%h);
    my @buckets = map { ref $_ ? $_ : ((undef) x $_) } @{ bucket_array(\%h) };
    my $max = $#buckets;
    my @model = map { @{ $buckets[($_ ^ $mask) & $max] // [] } } 0..$max;
    printf "n=%-4d buckets=%-5d mask=0x%08x model==keys: %s\n", $n, $max+1, $mask, ("@model" eq "@actual" ? "yes" : "NO");
}
