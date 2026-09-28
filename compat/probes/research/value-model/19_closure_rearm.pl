use strict; use warnings; use Scalar::Util qw(refaddr);
my (@addr, $cl);
for my $i (1 .. 3) {
    my $x = $i * 10;
    push @addr, refaddr(\$x);
    if ($i == 1) {
        $cl = sub { $x };
        print "it1_imm=", $cl->(), " ";
        $x = 111;
        print "it1_mut=", $cl->(), " ";
    }
    print "it3_sees=", $cl->(), " " if $i == 3;
}
print "a1_ne_a2=", ($addr[0] != $addr[1] ? 1 : 0),
    " a2_eq_a3=", ($addr[1] == $addr[2] ? 1 : 0), "\n";
my (@addr2, $cl2, @keep);
for my $i (1 .. 3) {
    my $x = $i * 10;
    push @keep, \$x;
    push @addr2, refaddr(\$x);
    $cl2 = sub { $x } if $i == 1;
    print "kept_it3_sees=", $cl2->(), " " if $i == 3;
}
print "kept_all_distinct=",
    (($addr2[0] != $addr2[1] && $addr2[1] != $addr2[2] && $addr2[0] != $addr2[2]) ? 1 : 0), "\n";
