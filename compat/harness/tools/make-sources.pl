#!/usr/bin/env perl

# Generates sources.md from sources.tsv, resolving each citation pattern to a line number in a perl
# source tree checked out at the v5.44.0 tag. Usage: make-sources.pl PERL5_TREE > sources.md
# A pattern that matches no line is reported as NOT FOUND rather than silently dropped.

use strict;
use warnings;
use FindBin qw($Bin);

my ($tree) = @ARGV;
die "usage: make-sources.pl PERL5_TREE\n" unless defined $tree && -d $tree;
my (%by_probe, @order);
open my $tsv, '<', "$Bin/sources.tsv" or die "cannot read sources.tsv: $!\n";
while (my $line = <$tsv>) {
    chomp $line;
    next if $line =~ /^\s*(#|$)/;
    my ($probe, $file, $pattern, $note) = split /\t/, $line, 4;
    push @order, $probe unless $by_probe{$probe};
    my $where = '(probe only)';
    if ($file ne '-') {
        my $found;
        if (open my $src, '<', "$tree/$file") {
            while (my $s = <$src>) {
                if ($s =~ /$pattern/) { $found = $.; last }
            }
        }
        $where = defined $found ? "`$file:$found`" : "`$file` NOT FOUND";
    }
    push @{ $by_probe{$probe} }, "- $where $note";
}
print "# Source citations\n\n";
print "Line numbers refer to the perl5 repository at tag v5.44.0 and were resolved mechanically by\n";
print "`tools/make-sources.pl` from `tools/sources.tsv`. \"Probe only\" marks rules established by\n";
print "running the probe without reading the corresponding source.\n\n";
for my $probe (@order) {
    print "## $probe\n\n", join("\n", @{ $by_probe{$probe} }), "\n\n";
}
