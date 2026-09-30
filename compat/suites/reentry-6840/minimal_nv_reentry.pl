#!/usr/bin/env perl
use strict;
use warnings;
my $x = '12x';
local $SIG{__WARN__} = sub { $x = 99 };
my $r = sprintf '%.17g', $x;
print "$r\n";
