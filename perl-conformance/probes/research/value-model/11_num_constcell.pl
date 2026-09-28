use strict; use warnings; use JSON::PP;
my $j = JSON::PP->new;
sub probe {
    my $enc = $j->encode([ $_[0] ]);
    { no warnings; my $n = $_[0] + 0; }
    return $enc;
}
my @out;
for my $i (1, 2) { push @out, probe("10"); }
print "const: @out\n";
