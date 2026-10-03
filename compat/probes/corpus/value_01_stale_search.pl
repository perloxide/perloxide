# Search for pure-Perl paths where a numeric cache disagrees with a fresh parse of the current string,
# or where the choice of cached slot (IV versus NV) changes a printed value.
use strict; use warnings; no warnings qw(numeric void);
sub fresh { my $c = "" . $_[0]; $c }        # a new scalar holding only the string
sub show { my ($label, $cached, $recomputed) = @_;
    my $line = sprintf "%-44s cached=%-24s fresh=%-24s %s", $label, $cached, $recomputed, ($cached eq $recomputed ? '' : 'DIFFERS');
    $line =~ s/ +$//;   # the marker column is empty when the two agree
    print "$line\n" }
# negative zero: does an integer cache lose the sign that a fresh parse keeps?
for my $str ("-0", "-0.0", "-0e0", "+0", "00") {
    for my $op (['$s + 0', sub { my $x = $_[0] + 0 }], ['$s | 0', sub { my $x = $_[0] | 0 }], ['int $s', sub { my $x = int $_[0] }], ['$a[$s]', sub { my @a; my $x = $a[$_[0]] }]) {
        my $s = fresh($str); $op->[1]->($s);
        show(qq{"$str" after $op->[0]: sprintf "%g"}, sprintf("%g", $s), sprintf("%g", fresh($str)));
    }
}
# in-place writers not covered by the matrix
my @writers = (
  [ 'print into PerlIO::scalar',   sub { open my $fh, '+<', \$_[0] or die; print {$fh} "7"; close $fh } ],
  [ 'read() at offset 0',          sub { open my $fh, '<', \"7" or die; read($fh, $_[0], 1, 0) } ],
  [ 'sysread-like via read offset 1', sub { open my $fh, '<', \"7" or die; read($fh, $_[0], 1, 1) } ],
  [ '$s = reverse $s',             sub { $_[0] = reverse $_[0] } ],
  [ '$s = join "", $s, "7"',       sub { $_[0] = join "", $_[0], "7" } ],
  [ '$s = lc $s',                  sub { $_[0] = lc $_[0] } ],
  [ '$s = $s . "7"',               sub { $_[0] = $_[0] . "7" } ],
  [ 'chomp',                       sub { chomp $_[0] } ],
  [ '${\substr($s,0,1)} = "7"',    sub { my $r = \substr($_[0], 0, 1); $$r = "7" } ],
  [ 'utf8::decode',                sub { utf8::decode($_[0]) } ],
  [ '4-arg select on bit vector',  sub { my ($w, $e); select($_[0], $w, $e, 0) } ],
  [ 'sprintf into self',           sub { $_[0] = sprintf "%s7", $_[0] } ],
);
for my $w (@writers) {
    my $s = fresh("15"); my $n = $s + 0;          # cache: IOK 15
    eval { $w->[1]->($s); 1 } or do { print "$w->[0]: died: $@"; next };
    show("$w->[0] (\"15\" numified first)", do { no warnings; sprintf "%.17g", $s + 0 }, do { no warnings; sprintf "%.17g", fresh($s) + 0 });
}
# ++ after numification versus magic string increment
for my $str ("Az", "a9", "zz", "09", "18446744073709551615", "10") {
    my $plain = fresh($str); $plain++;
    my $marked = fresh($str); { no warnings; my $n = $marked + 0; } $marked++;
    printf "%-22s plain++ => %-22s  after (\$s+0), \$s++ => %s\n", qq{"$str"}, $plain, $marked;
}
