use strict; use warnings; no warnings 'numeric';
use Data::Dumper; $Data::Dumper::Indent = 0; $Data::Dumper::Terse = 1;
my $clean = "10"; my $dirty = "10abc"; my $pad = " 10";
my ($x, $y, $z) = ($clean + 0, $dirty + 0, $pad + 0);
print "xs=", (defined &Data::Dumper::Dumpxs ? 1 : 0),
    " clean=", Dumper($clean), " dirty=", Dumper($dirty), " pad=", Dumper($pad), "\n";
