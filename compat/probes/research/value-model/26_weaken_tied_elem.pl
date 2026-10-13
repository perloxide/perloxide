# weaken on an element of a tied array: the holder is the element proxy, and its set magic is the tie's STORE.
#
# An element of a tied array is reached through a proxy SV carrying PERL_MAGIC_tiedelem (p); its get magic
# FETCHes into the proxy's own slot and its set magic STOREs the slot back by index.  weaken acts on the
# proxy's own slot, so:
#   A. `weaken $a[0]` by itself: the proxy is a temporary, and weaken runs no set magic, so the tie object
#      never hears of it; the proxy dies with the statement and the tie's slot stays strong.  No effect.
#   B. A proxy kept alive by `\$a[0]`, primed by one read (an unread proxy's slot is undef and weaken is a
#      no-op on undef), then weakened, is a weak holder whose set magic is the container's: when the
#      referent dies, sv_kill_backrefs clears the proxy and SvSETMAGIC runs STORE(index, undef).
#   C. A held proxy FETCHes once: magic_getpack sets MGf_GSKIP on every tiedelem FETCH (mg.c 2240) and only a set
#      through the proxy clears it (mg.c 287), so later reads return the cached value and the weakened proxy stays
#      weak; reading `$a[0]` afresh makes a new proxy, which FETCHes and is not weak.
# The tie class below keeps its own slot weak so the referent can die at all.  The extra FETCHes in the
# 5.44.0 output (weaken in A, isweak in C) are the bundled Scalar::Util's get-magic calls, not perl's.
use strict; use warnings;
use Scalar::Util qw(weaken isweak);
{
    package TA; require Tie::Array; our @ISA = ('Tie::StdArray');
    sub STORE { my ($s, $i, $v) = @_; printf "  STORE[%d] %s\n", $i, defined $v ? 'ref' : 'undef';
                $s->[$i] = $v; Scalar::Util::weaken($s->[$i]) if ref $v }     # the tie keeps its own slot weak
    sub FETCH { my ($s, $i) = @_; print "  FETCH[$i]\n"; $s->[$i] }
    package T; sub DESTROY { print "  DESTROY\n" }
}
$| = 1;
tie my @a, 'TA';

print "A. weaken \$a[0] on the temporary proxy\n";
my $t = bless [], 'T';
$a[0] = $t;
weaken $a[0];
printf "  isweak(\$a[0])=%d\n", isweak($a[0]) ? 1 : 0;
print "  undef \$t:\n"; undef $t;
printf "  defined \$a[0]=%d (the proxy's weakening died with the statement)\n", defined $a[0] ? 1 : 0;
$a[0] = undef;

print "B. a held proxy, primed, then weakened: the kill runs the tie's STORE\n";
$t = bless [], 'T';
$a[0] = $t;
my $r = \$a[0];
my $prime = $$r;
weaken $$r;
undef $prime;
print "  undef \$t:\n"; undef $t;
print "  end of B\n";
undef $r;

print "C. a held proxy reads its cached value; a fresh \$a[0] is a new proxy\n";
$t = bless [], 'T';
$a[0] = $t;
$r = \$a[0];
$prime = $$r;
weaken $$r;
undef $prime;
my $again = $$r;
printf "  isweak(\$\$r)=%d after a second read (no FETCH: cached)\n", isweak($$r) ? 1 : 0;
undef $again;
printf "  isweak(\$a[0])=%d for a fresh proxy\n", isweak($a[0]) ? 1 : 0;
print "  undef \$t:\n"; undef $t;
print "  end of C\n";
undef $r;
print "end\n";
