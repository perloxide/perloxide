# Numification caches flags on literal constants in the op tree, so the same line of code can take a
# different path on a later execution.
use strict; use warnings; no warnings qw(numeric);
use JSON::PP (); use B ();
$| = 1;
sub fl { my $f = B::svref_2object($_[0])->FLAGS; join '', ($f & B::SVp_IOK ? 'i' : ''), ($f & B::SVp_NOK ? 'n' : ''), ($f & B::SVp_POK ? 'p' : ''), ($f & B::SVf_READONLY ? ' RO' : '') }
# (a) the same range expression, before and after a call that forces its right-hand literal to numify
sub span { my $l = shift; my @r = ($l .. "zz"); scalar @r }
print "(a) span('a') first: ", span("a"), "; span(5): ", span(5), "; span('a') again: ", span("a"), "\n";
# (b) a foreach alias to a literal: numifying the alias marks the constant for the next pass
my $json = JSON::PP->new;
for my $pass (1 .. 2) {
    for my $v ("10") {
        print "(b) pass $pass: literal flags before=", fl(\$v), " encode=", $json->encode([$v]);
        my $n = $v + 0;
        print " flags after=", fl(\$v), "\n";
    }
}
# (c) the mark reaches later copies made from the same literal op
for my $pass (1 .. 2) {
    my $copy = "20";                                   # copied from the constant each pass
    print "(c) pass $pass: copy encode=", $json->encode([$copy]), "\n";
    for my $alias ("20") { my $n = $alias + 0 }        # a different op holding its own "20" constant
}
