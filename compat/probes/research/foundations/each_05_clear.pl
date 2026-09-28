# Iterator and bucket-array state after %h = (), undef %h.
use strict; use warnings;
use Hash::Util qw(bucket_ratio);
my %h = map { $_ => 1 } 1..1000;
my ($k) = each %h;
%h = ();
print "bucket_ratio after %h=(): ", bucket_ratio(%h) // 'undef', "\n";
%h = map { $_ => 1 } 1..3;
my %fresh = map { $_ => 1 } 1..3;
print "buckets after refill:     ", bucket_ratio(%h), "   fresh hash: ", bucket_ratio(%fresh), "\n";
print "order after refill: @{[keys %h]}   fresh: @{[keys %fresh]}\n";
my %u = map { $_ => 1 } 1..1000; each %u; undef %u; %u = map { $_ => 1 } 1..3;
print "buckets after undef+refill: ", bucket_ratio(%u), "\n";
# each immediately after clear+refill: starts from the beginning?
my %e = map { $_ => 1 } 1..10; my ($f1) = each %e; %e = (); %e = map { $_ => 1 } 1..10;
my @all; while (my ($x) = each %e) { push @all, $x } print "each after clear+refill visits: ", scalar(@all), "\n";
