# A tied-element proxy that acquires a second magic.  A tie on the temporary proxy $a[0] dies with the proxy
# and a fresh $a[0] goes to the array's class alone.  On a held proxy the magics chain in attachment order,
# and the get-magic skip (MGf_GSKIP) is per magic: the scalar tie's FETCH runs on every read while the
# element's FETCH runs once and is re-armed by a write; a write runs both STOREs.  weaken on such a proxy
# is cleared at the referent's death through both STOREs.
use strict; use warnings; use Scalar::Util qw(weaken isweak);
{ package TA; require Tie::Array; our @ISA = ('Tie::StdArray');
  sub STORE { my ($s, $i, $v) = @_; printf "  TA::STORE[%d] %s\n", $i, defined $v ? (ref $v ? 'ref' : $v) : 'undef'; $s->[$i] = $v; Scalar::Util::weaken($s->[$i]) if ref $v }
  sub FETCH { my ($s, $i) = @_; print "  TA::FETCH[$i]\n"; $s->[$i] }
  package TS; sub TIESCALAR { print "  TS::TIESCALAR\n"; bless { v => 'from-TS' }, $_[0] }
  sub FETCH { print "  TS::FETCH\n"; $_[0]{v} }
  sub STORE { printf "  TS::STORE %s\n", defined $_[1] ? (ref $_[1] ? 'ref' : $_[1]) : 'undef'; $_[0]{v} = $_[1]; Scalar::Util::weaken($_[0]{v}) if ref $_[1] }
  package T; sub DESTROY { print "  DESTROY\n" } }
tie my @a, 'TA'; @a = ('x');
print "1. tie the temporary proxy \$a[0]:\n";
tie $a[0], 'TS';
print "   read \$a[0] afresh: ", $a[0], "\n";
print "2. tie a held proxy, then three reads, a write, a read:\n";
my $r = \$a[0];
tie $$r, 'TS';
print "   read 1: ", $$r, "\n";
print "   read 2: ", $$r, "\n";
print "   read 3: ", $$r, "\n";
print "   write 'w':\n"; $$r = 'w';
print "   read 4: ", $$r, "\n";
print "   read \$a[0] afresh: ", $a[0], "\n";
print "3. weaken the held, doubly magical proxy, then kill the referent (both ties keep weak copies):\n";
my $t = bless [], 'T';
$$r = $t;
print "   weaken:\n"; weaken $$r;
print "   undef the referent:\n"; undef $t;
print "   read after the kill: ", (defined $$r ? 'defined' : 'undef'), "\n";
print "end\n";
