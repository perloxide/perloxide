# A tied weak holder's STORE(undef) running in the middle of Perl_sv_kill_backrefs.
#
# sv_clear runs curse first and, only when curse commits (no resurrection), clears the weak
# referrers one at a time in weaken order; each clear is `SvRV_set(referrer, 0)`, `SvROK_off`,
# `SvWEAKREF_off`, `SvSETMAGIC(referrer)` (sv.c 6987-6990).  The set magic of a tied holder is its
# STORE, which is user code running with the later holders not yet cleared.  The comment above the
# kill (sv.c 7320, "Free back-references before magic, in case the magic calls Perl code that has
# weak references to sv") shows the intent that no Perl code reach the dying referent through a
# weak reference; the order of the two steps inside the kill is where that intent has a hole.
#
# MODE=observe (default): STORE reads a later, plain weak holder: it is still defined and weak.
# This is the only mode whose behavior is defined; it is the recorded output.  The other modes
# reach the dying referent through that later holder and are the undefined window (undefined.md):
#   copy        a strong copy kept in an outer variable and dereferenced after the drop: nothing
#               rechecks the count after the kill, sv_clear frees the body, and sv_free2 skips
#               del_SV because the count is positive (sv.c 7886-7888), so the copy points at a
#               freed SV head: "Not an ARRAY reference", then a crash or silent corruption by build
#   release     the copy is only released afterward: the release frees the freed SV again
#   transient   a strong copy that dies before STORE returns: its release takes the count back to
#               zero inside the kill and re-enters sv_clear on the SV being cleared (SIGSEGV)
#   weaken_new  a new weak reference taken inside STORE: weaken's own count decrement re-enters
#               the clear, which clears the new holder at once, then the walk crashes (SIGSEGV)
#   undef_later STORE undefs the later holder before the walk reaches it: sv_del_backref no longer
#               finds the backref magic, which sv_unmagic detached before the walk, and croaks
#               "panic: del_backref" (a perldiag (P) internal error, propagated out of the kill)
#   global      the copy is stored in a global and never touched: no visible failure, the freed
#               SV head leaks with a positive count
#   rebless     the copy is reblessed inside STORE: DESTROY runs a second time, then SIGSEGV
# KIND=hash makes the referent a blessed hash (Perl_hv_kill_backrefs); the outcomes are the same.
use strict; use warnings;
use Scalar::Util qw(weaken isweak refaddr);
{
    package Watch;
    sub TIESCALAR { my ($class, $r, $cb) = @_; my $self = bless { r => $r, cb => $cb }, $class;
                    Scalar::Util::weaken($self->{r}); $self }
    sub FETCH { $_[0]{r} }
    sub STORE { my ($self, $v) = @_; $self->{r} = $v; Scalar::Util::weaken($self->{r}) if ref $v;
                $self->{cb}->() unless defined $v }
    package Target;
    sub DESTROY { print "DESTROY\n" }
}
$| = 1;
my $mode = $ENV{MODE} // 'observe';
my $kind = $ENV{KIND} // 'array';
our $global;
my $target = $kind eq 'hash' ? bless { v => 42 }, 'Target' : bless [42], 'Target';
my $addr = refaddr $target;
my ($later, $later2, $saved);
tie my $first, 'Watch', $target, sub {
    printf "STORE(undef): later defined=%d weak=%d\n", defined $later ? 1 : 0, isweak $later ? 1 : 0;
    if ($mode eq 'copy' or $mode eq 'release') {
        $saved = $later;
        printf "STORE(undef): saved weak=%d same_addr=%d\n", isweak $saved ? 1 : 0, refaddr($saved) == $addr ? 1 : 0;
    }
    elsif ($mode eq 'transient')   { my $tmp = $later; printf "STORE(undef): tmp weak=%d\n", isweak $tmp ? 1 : 0 }
    elsif ($mode eq 'weaken_new')  { $later2 = $later; weaken $later2;
                                     printf "STORE(undef): later2 defined=%d\n", defined $later2 ? 1 : 0 }
    elsif ($mode eq 'undef_later') { undef $later; print "STORE(undef): undef later\n" }
    elsif ($mode eq 'global')      { $global = $later; print "STORE(undef): stored in global\n" }
    elsif ($mode eq 'rebless')     { my $tmp = $later; bless $tmp, 'Target'; print "STORE(undef): reblessed\n" }
};
my $primed = defined $first;    # FETCH once so $first holds the reference that weaken needs
weaken $first;
$later = $target; weaken $later;
print "before drop\n";
undef $target;
printf "after drop: later defined=%d weak=%d\n", defined $later ? 1 : 0, isweak $later ? 1 : 0;
if ($mode eq 'copy')    { printf "after drop: saved ref=%s\n", ref $saved; print "payload=", join(',', @$saved), "\n" }
if ($mode eq 'release') { print "releasing saved\n"; undef $saved; print "released saved\n" }
print "end\n";
