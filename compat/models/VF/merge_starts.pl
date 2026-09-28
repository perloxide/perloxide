#!/usr/bin/perl
# merge_starts.pl LANE VER -- merge per-start runs (TAG=suite_LANE_VER_START) into one lane report + one transitions table +
# one starts file, as if the lane had run in one process.  Per-start tables are keyed by start, so concatenation is exact.
use strict; use warnings; our $ROOT = $ENV{VF_ROOT} || '.'; my ($lane,$ver)=@ARGV; my $tag = "suite_${lane}_$ver";
my (@rows,%sum); my @starts = map { /suite_${lane}_${ver}_(\w+)\.txt$/ ? $1 : () } glob("$ROOT/starts.${tag}_*.txt");
open my $T,'>',"$ROOT/transitions.$tag.txt" or die; open my $S,'>',"$ROOT/starts.$tag.txt" or die; open my $R,'>',"$ROOT/suite/$lane.$ver.txt" or die;
for my $c (@starts) { my $t = "${tag}_$c"; for my $f ("$ROOT/transitions.$t.txt") { open my $in,'<',$f or next; print $T $_ while <$in>; close $in } for my $f ("$ROOT/starts.$t.txt") { open my $in,'<',$f or next; print $S $_ while <$in>; close $in }
  open my $in,'<',"$ROOT/suite/$lane.$ver.$c.txt" or next; while (<$in>) { if (/^oracle=(.*)/) { my $h=$1; while ($h =~ /(\w+)=(\d+)/g) { $sum{$1} += $2 } $sum{head} //= $h } else { push @rows, $_ } } close $in }
(my $head = $sum{head}//'') =~ s/(\w+)=(\d+)/$1 eq 'starts' ? "starts=".scalar(@starts) : ($1 eq 'seed' || $1 eq 'depth' || $1 eq 'walks') ? "$1=$2" : "$1=$sum{$1}"/ge; print $R "oracle=$head\n", @rows; close $R; close $T; close $S; print "merged ", scalar(@starts), " starts into $lane.$ver\n";
