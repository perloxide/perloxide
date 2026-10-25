# What a later weak holder sees from inside a tied holder's STORE(undef), without upgrading it: the
# destructor has run and the object is already un-blessed (blessed undef, method calls die "unblessed
# reference"), while ref, refaddr and the elements are intact, readable and writable, and nothing crashes.
# The upgrades -- a strong copy, a new weak reference, a rebless -- are the undefined window of
# 25_kill_backrefs_reentry.pl; this probe stays on the defined side of it.
use strict; use warnings; use Scalar::Util qw(weaken isweak refaddr blessed reftype);
{ package Watch;
  sub TIESCALAR { my ($c, $r, $cb) = @_; my $s = bless { r => $r, cb => $cb }, $c; Scalar::Util::weaken($s->{r}); $s }
  sub FETCH { $_[0]{r} }
  sub STORE { my ($s, $v) = @_; $s->{r} = $v; Scalar::Util::weaken($s->{r}) if ref $v; $s->{cb}->() unless defined $v }
  package Target; sub DESTROY { print "DESTROY\n" } sub hello { "hello" } }
$| = 1;
my $target = bless [42, 'x'], 'Target';
my $addr = refaddr $target;
my $later;
tie my $first, 'Watch', $target, sub {
    printf "in STORE: defined=%d isweak=%d ref=%s reftype=%s blessed=%s same_addr=%d elems=%d first=%s\n",
        defined $later ? 1 : 0, isweak($later) ? 1 : 0, ref $later, reftype $later, blessed($later) // 'undef',
        refaddr($later) == $addr ? 1 : 0, scalar @$later, $later->[0];
    my $m = eval { $later->hello; "returned" } // "died: $@"; $m =~ s/ at \S+ line \d+\.\n//; print "in STORE: method call $m\n";
    $later->[0] = 43; push @$later, 'y'; print "in STORE: wrote element and pushed: elems=", scalar @$later, " first=$later->[0]\n";
};
my $primed = defined $first; weaken $first;
$later = $target; weaken $later;
undef $target;
printf "after the kill: later defined=%d\n", defined $later ? 1 : 0;
print "end\n";
