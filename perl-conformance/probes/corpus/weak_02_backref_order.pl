# The order in which weak holders are cleared is weaken order permuted by removals (Perl_sv_del_backref):
# a removed first holder advances the array start, a removed last one shortens it, and a removed middle one
# is replaced by the last entry.  Five tied holders print their names from STORE(undef); each line removes
# some before the kill.
use strict; use warnings; use Scalar::Util qw(weaken);
{ package W; sub TIESCALAR { my ($c, $n) = @_; bless { n => $n }, $c } sub FETCH { undef }
  sub STORE { my ($s, $v) = @_; push @main::cleared, $s->{n} unless defined $v } }
our @cleared;
sub run {
    my ($label, @remove) = @_;
    my $t = [];
    my @h;
    for my $n ('a' .. 'e') { tie my $x, 'W', $n; $x = $t; weaken $x; push @h, \$x }
    @cleared = ();
    for (@remove) { ${$h[$_]} = undef }
    my $removed = join ' ', @cleared;
    @cleared = ();
    undef $t;
    printf "%-11s removed [%s] cleared [%s]\n", "$label:", $removed, join(' ', @cleared);
}
run("none");
run("first a",    0);
run("middle b",   1);
run("middle c",   2);
run("last e",     4);
run("b then c",   1, 2);
run("b then d",   1, 3);
run("a then e",   0, 4);
run("e then a",   4, 0);
run("all but c",  0, 1, 3, 4);
