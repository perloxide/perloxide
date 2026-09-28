use strict; use warnings; use Devel::Peek;
sub flags {
    my $file = "/tmp/peek.$$";
    open my $save, '>&', \*STDERR or die "dup: $!";
    open STDERR, '>', $file or die "redirect: $!";
    Dump($_[0]);
    open STDERR, '>&', $save or die "restore: $!";
    my $out = do { local (@ARGV, $/) = ($file); <> };
    my ($fl) = $out =~ /FLAGS = \(([^)]*)\)/;
    my ($iv) = $out =~ /\bIV = (\S+)/;
    my ($nv) = $out =~ /\bNV = (\S+)/;
    return sprintf "(%s) IV=%s NV=%s", $fl // '?', $iv // '-', $nv // '-';
}
my $s = "10"; { no warnings; my $n = $s + 0; }
print "plus10:    ", flags($s), "\n";
my $one = "1"; $one++;
print "one_inc:   ", flags($one), " val=$one\n";
my $nine = "9"; $nine++;
print "nine_inc:  ", flags($nine), " val=$nine\n";
my $az = "Az"; $az++;
print "az_inc:    ", flags($az), " val=$az\n";
my $dirty = "10abc"; { no warnings; my $n = $dirty + 0; }
print "dirty:     ", flags($dirty), "\n";
my $pad = " 10"; { no warnings; my $n = $pad + 0; }
print "pad:       ", flags($pad), "\n";
my $g1 = "-0"; my $t = sprintf "%g", $g1;
my $p1 = $g1 + 0;
print "gfirst:    ", flags($g1), " g_again=", sprintf("%g", $g1), " plus=$p1\n";
my $i1 = "-0"; my $u = $i1 + 0;
print "intfirst:  ", flags($i1), " g=", sprintf("%g", $i1), "\n";
