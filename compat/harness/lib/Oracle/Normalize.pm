package Oracle::Normalize;

# Output normalization for comparing runs.
#
# exact(): rewrites every hexadecimal token of six or more digits after "0x" to ADDR1, ADDR2, ... in
# order of first appearance across the channels of one run (stdout, then stderr, then fd 3). Equal
# addresses stay equal and distinct addresses stay distinct, so address identity relationships are
# preserved while absolute values (which change with ASLR) are not. The ", Perl interpreter: 0x..."
# suffix that threaded builds append to some warnings is removed first.
#
# canonical(): replaces every such token with a plain ADDR and sorts the lines of each channel, so two
# runs compare equal when they print the same multiset of lines in any order. Address identity is not
# preserved in this form.

use strict;
use warnings;

my $ADDRESS = qr/0x([0-9a-fA-F]{6,})/;
my $INTERPRETER_SUFFIX = qr/, Perl interpreter: 0x[0-9a-fA-F]+/;

sub exact {
    my (@channels) = @_;
    my %name;
    my $next = 0;
    return map {
        my $text = $_;
        $text =~ s/$INTERPRETER_SUFFIX//g;
        $text =~ s/$ADDRESS/ $name{lc $1} \/\/= 'ADDR' . ++$next /ge;
        $text;
    } @channels;
}

sub canonical {
    my (@channels) = @_;
    return map {
        my $text = $_;
        $text =~ s/$INTERPRETER_SUFFIX//g;
        $text =~ s/$ADDRESS/ADDR/g;
        $text .= "\n" if length $text && substr($text, -1) ne "\n";
        join '', sort split /^/, $text;
    } @channels;
}

1;
