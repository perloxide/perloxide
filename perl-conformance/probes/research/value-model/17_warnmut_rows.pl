use strict; use warnings;
sub row {
    my ($label, $handler) = @_;
    my $pid = open my $fh, '-|';
    die "fork: $!" unless defined $pid;
    if (!$pid) {
        my $x = '12x';
        my $fired = 0;
        local $SIG{__WARN__} = sub { return if $fired++; $handler->(\$x) };
        my $n = 0 + $x;
        my $re = do { no warnings; 0 + $x };
        print "$x:$n:$re";
        exit 0;
    }
    my $out = do { local $/; <$fh> };
    close $fh;
    my $sig = $? & 127;
    printf "%-12s %s%s\n", $label, $out // '', $sig ? " SIG$sig" : "";
}
row('str+nv',  sub { ${$_[0]} = '99';   my $z = sprintf '%.17g', ${$_[0]} });
row('str+iv',  sub { ${$_[0]} = '99';   my $z = ${$_[0]} + 0 });
row('str5+iv', sub { ${$_[0]} = '99.5'; my $z = ${$_[0]} + 0 });
row('num',     sub { ${$_[0]} = 99 });

# The excluded perl bug: outer %.17g with a numeric-99 handler.
my $pid = open my $fh, '-|';
die "fork: $!" unless defined $pid;
if (!$pid) {
    my $x = '12x';
    my $fired = 0;
    local $SIG{__WARN__} = sub { return if $fired++; $x = 99 };
    my $n = sprintf '%.17g', $x;
    print "n=$n";
    exit 0;
}
my $out = do { local $/; <$fh> };
close $fh;
my $sig = $? & 127;
print "segv_check:  ", ($sig ? "SIG$sig" : "no-crash out=$out"), "\n";
