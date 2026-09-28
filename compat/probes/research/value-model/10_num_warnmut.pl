use strict; use warnings;
my $s = "10abc";
my $first;
{
    local $SIG{__WARN__} = sub { $s = "999" };
    $first = $s + 0;
}
my $second = do { no warnings; $s + 0 };
print "first=$first s=$s second=$second\n";
