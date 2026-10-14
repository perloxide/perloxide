# oracle-requires: threads
# Weak references to a threads::shared object are per thread.  A thread reaches a shared referent through
# its own proxy SV, and a weak reference is a weak reference to that proxy: it is cleared when the thread's
# last strong reference dies, whether or not the shared referent lives on in another thread.  The referent
# itself dies, and DESTROY runs, in whichever thread drops the last proxy.  So no thread can hold only a
# weak reference to a shared object, and nothing in another thread can resurrect a shared object from its
# DESTROY: by the time one thread's DESTROY runs, every other thread's weak reference is already undef.
# Every step is handed off with a condition variable, so the interleaving is the one written here.
use strict; use warnings;
use threads; use threads::shared;
use Scalar::Util qw(weaken isweak);
$| = 1;

my $step :shared = 0;
sub reach { my ($n) = @_; lock $step; $step = $n; cond_broadcast $step }
sub await { my ($n) = @_; lock $step; cond_wait $step until $step >= $n }
sub show  { my ($who, $label, @v) = @_; printf "%-5s %-52s %s\n", $who, $label, join ', ', @v }
{ package T; sub DESTROY { printf "%-5s DESTROY\n", "t" . threads->tid } }

print "A. main weakens; the child holds the object; main drops its strong reference\n";
{
    $step = 0;
    my $obj = shared_clone(bless { v => 42 }, 'T');    # the unshared original dies here: one DESTROY in main
    my $w = $obj; weaken $w;
    my $t = threads->create(sub {
        my $mine = $obj; await 1;
        show 'child', 'payload while main\'s weak ref is already undef', $mine->{v};
        my $w2 = $mine; weaken $w2;
        show 'child', 'its own weak ref: isweak, defined', isweak($w2) ? 1 : 0, defined $w2 ? 1 : 0;
        reach 2; await 3;
        return 0;                                        # the child's references die here: DESTROY in the child
    });
    undef $obj;
    show 'main', 'defined($w) after undef $obj, child still holds it', defined $w ? 1 : 0;
    reach 1; await 2; reach 3; $t->join;
    show 'main', 'defined($w) after join', defined $w ? 1 : 0;
}

print "\nB. the child holds only a weak reference: it is undef at once, the object alive in main\n";
{
    $step = 0;
    my $obj = shared_clone({ v => 42 }); bless $obj, 'T';
    my $t = threads->create(sub {
        my $w2 = $obj; weaken $w2;
        undef $obj;                                      # the child's last strong reference
        show 'child', 'defined($w2) with main still holding the object', defined $w2 ? 1 : 0;
        reach 1; await 2;
        show 'child', 'defined($w2) after main\'s DESTROY', defined $w2 ? 1 : 0;
        return 0;
    });
    await 1;
    show 'main', 'payload', $obj->{v};
    undef $obj;                                          # last reference anywhere: DESTROY in main
    reach 2; $t->join;
}
print "end\n";
