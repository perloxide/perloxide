# weaken on a held tied-element proxy whose slot has never been read is a silent no-op (sv_rvweaken returns
# on !SvOK), and which Scalar::Util predicates run get-magic on their argument decides what happens next:
# a predicate that FETCHes primes the proxy with a *strong* copy, after which the referent cannot die while
# the proxy lives.  The second part records, per function, whether one call FETCHes.
use strict; use warnings; use Scalar::Util qw(weaken unweaken isweak blessed reftype refaddr readonly);
{ package TA; require Tie::Array; our @ISA = ('Tie::StdArray');
  sub STORE { my ($s, $i, $v) = @_; printf "  STORE[%d] %s\n", $i, defined $v ? "ref" : "undef"; $s->[$i] = $v; Scalar::Util::weaken($s->[$i]) if ref $v }
  sub FETCH { my ($s, $i) = @_; print "  FETCH[$i]\n"; $s->[$i] }
  package T; sub DESTROY { print "  DESTROY\n" } }
tie my @a, 'TA';
my $t = bless [], 'T';
$a[0] = $t;
print "primed held proxy: read, weaken, undef the referent:\n";
{ my $r = \$a[0]; my $primed = defined $$r; weaken $$r; print "  undef \$t:\n"; undef $t; print "  after: defined via proxy = ", (defined $$r ? 1 : 0), "\n"; }
my $t2 = bless [], 'T'; $a[0] = $t2;
print "unprimed held proxy: weaken (no-op on an undef slot), read (primes a strong copy), undef the referent:\n";
{ my $r = \$a[0]; weaken $$r; my $primed = defined $$r; print "  undef \$t2:\n"; undef $t2; print "  after: defined via proxy = ", (defined $$r ? 1 : 0), "\n"; print "  drop the proxy:\n"; }
print "which predicates FETCH (one call each on a fresh unprimed proxy):\n";
my $u = bless [], 'T'; $a[1] = $u;
for my $f (['isweak', \&isweak], ['blessed', \&blessed], ['reftype', \&reftype], ['refaddr', \&refaddr], ['readonly', \&readonly], ['weaken', \&weaken], ['unweaken', \&unweaken], ['defined', sub { defined $_[0] }], ['ref', sub { ref $_[0] }]) {
  my $r = \$a[1];
  print "  $f->[0]:\n"; $f->[1]->($$r);
}
print "end\n";
